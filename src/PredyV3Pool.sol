//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/math/SafeMath.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";
import "v3-periphery/libraries/TransferHelper.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "v3-core/contracts/libraries/FixedPoint128.sol";
import "v3-periphery/interfaces/ISwapRouter.sol";
import "./interfaces/IPredyV3Pool.sol";
import "./interfaces/IPricingModule.sol";
import "./interfaces/IProductVerifier.sol";
import "./vendors/IUniswapV3PoolOracle.sol";
import "forge-std/console2.sol";
import "./libraries/BaseToken.sol";
import "./Constants.sol";

contract PredyV3Pool is IPredyV3Pool, Ownable, Constants {
    using BaseToken for BaseToken.TokenState;
    using SafeMath for uint256;

    struct PerpStatus {
        uint256 tokenId;
        int24 lower;
        int24 upper;
        uint128 borrowedLiquidity;
        uint256 cumulativeFee;
        uint256 cumulativeFeeForLP;
        uint256 cumFee0;
        uint256 cumFee1;
        uint256 lastTouchedTimestamp;
    }

    struct Vault {
        uint256 margin;
        uint256 collateralAmount0;
        uint256 collateralAmount1;
        bool[] isCollateral;
        bytes32[] lptIndex;
        uint128[] lptLiquidity;
        uint256[] lptFeeGrowth;
    }

    struct ExtraVaultParam {
        address owner;
        bool isLiquidationRequired;
        bool isClosed;
        InstantDebtType[] debtInstant;
        uint256[] fee0Last;
        uint256[] fee1Last;
    }

    struct CloseParams {
        bool zeroToOne;
        uint256 amount;
        uint256 amountOutMinimum;
        uint256 penaltyAmount0;
        uint256 penaltyAmount1;
    }

    address token0;
    address token1;
    bool public override isMarginZero;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public uniswapPool;
    ISwapRouter public immutable swapRouter;
    uint24 private constant FEE_TIER = 500;

    mapping(address => address) public strategies;

    IProductVerifier public productVerifier;
    IPricingModule public pricingModule;

    uint256 lastTouchedTimestamp;

    mapping(bytes32 => PerpStatus) ranges;

    mapping(uint256 => mapping(uint256 => PerpStatus)) perpStatuses;

    uint256 vaultIdCount;

    mapping(uint256 => Vault) public vaults;
    mapping(uint256 => ExtraVaultParam) extraVaultParams;
    mapping(uint256 => BaseToken.AccountState) public accountState0;
    mapping(uint256 => BaseToken.AccountState) public accountState1;

    BaseToken.TokenState tokenState0;
    BaseToken.TokenState tokenState1;

    event VaultCreated(uint256 vaultId);
    event PositionClosed(
        uint256 vaultId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _penaltyAmount0,
        uint256 _penaltyAmount1
    );

    modifier onlyProductVerifier() {
        require(address(productVerifier) == msg.sender);
        _;
    }

    modifier onlyVaultOwner(uint256 _vaultId) {
        require(extraVaultParams[_vaultId].owner == msg.sender);
        _;
    }

    constructor(
        address _token0,
        address _token1,
        bool _isMarginZero,
        address _positionManager,
        address _factory,
        address _swapRouter
    ) {
        token0 = _token0;
        token1 = _token1;
        isMarginZero = _isMarginZero;
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);

        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({token0: token0, token1: token1, fee: FEE_TIER});

        uniswapPool = IUniswapV3Pool(PoolAddress.computeAddress(_factory, poolKey));

        vaultIdCount = 0;

        ERC20(token0).approve(address(positionManager), type(uint256).max);
        ERC20(token1).approve(address(positionManager), type(uint256).max);
        ERC20(token0).approve(address(_swapRouter), type(uint256).max);
        ERC20(token1).approve(address(_swapRouter), type(uint256).max);

        tokenState0.initialize();
        tokenState1.initialize();
    }

    function addProduct(address _strategyAddress) external onlyOwner {
        strategies[_strategyAddress] = _strategyAddress;
    }

    function setProductVerifier(address _productVerifier) external onlyOwner {
        productVerifier = IProductVerifier(_productVerifier);
    }

    function setPricingModule(address _pricingModule) external onlyOwner {
        pricingModule = IPricingModule(_pricingModule);
    }

    function createRanges(int24[] memory _lowers, int24[] memory _uppers) external returns (bytes32[] memory rangeIds) {
        rangeIds = new bytes32[](_lowers.length);

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        (uint256 vaultId, Vault storage vault) = createOrGetVault(0);

        for (uint128 i = 0; i < _lowers.length; i++) {
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_lowers[i]);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_uppers[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                1e10
            );

            ERC20(token0).transferFrom(msg.sender, address(this), amount0);
            ERC20(token1).transferFrom(msg.sender, address(this), amount1);

            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
                token0,
                token1,
                FEE_TIER,
                _lowers[i],
                _uppers[i],
                amount0,
                amount1,
                0,
                0,
                address(this),
                block.timestamp
            );

            bytes32 rangeId = getRangeKey(_lowers[i], _uppers[i]);
            rangeIds[i] = rangeId;

            {
                (uint256 tokenId, , , ) = positionManager.mint(params);
                ranges[rangeId].tokenId = tokenId;
            }
            ranges[rangeId].lower = _lowers[i];
            ranges[rangeId].upper = _uppers[i];

            vault.isCollateral.push(true);
            vault.lptIndex.push(rangeId);
            vault.lptLiquidity.push(1e10);
            vault.lptFeeGrowth.push(0);
            extraVaultParams[vaultId].fee0Last.push(0);
            extraVaultParams[vaultId].fee1Last.push(0);
        }
    }

    // User API

    /**
     * @notice Opens new position.
     */
    function openPosition(
        uint256 _vaultId,
        uint256 _margin,
        bool _isLiquidationRequired,
        bytes memory _data,
        uint256 _buffer0,
        uint256 _buffer1
    ) external override returns (uint256 vaultId) {
        applyPerpFee(_vaultId);

        Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId);

        vault.margin += _margin;

        extraVaultParams[vaultId].owner = msg.sender;
        extraVaultParams[vaultId].isLiquidationRequired = _isLiquidationRequired;

        if (isMarginZero) {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), _margin + _buffer0);
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), _buffer1);
        } else {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), _buffer0);
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), _margin + _buffer1);
        }

        (uint256 amount0, uint256 amount1) = productVerifier.openPosition(vaultId, _isLiquidationRequired, _data);

        uint256 minCollateral = getMinCollateral(vaultId);
        console.log(2, minCollateral);
        require(vault.margin >= minCollateral, "P2");

        require(!checkLiquidatable(vaultId), "P3");

        if (_buffer0 > amount0) {
            TransferHelper.safeTransfer(token0, msg.sender, _buffer0 - amount0);
        }
        if (_buffer1 > amount1) {
            TransferHelper.safeTransfer(token1, msg.sender, _buffer1 - amount1);
        }
    }

    /**
     * @notice Closes position in the vault.
     */
    function closePositionsInVault(
        uint256 _vaultId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) public override onlyVaultOwner(_vaultId) {
        applyPerpFee(_vaultId);
        _closePositionsInVault(_vaultId, CloseParams(_zeroToOne, _amount, _amountOutMinimum, 0, 0));
    }

    /**
     * @notice Withdraws asset from the vault.
     */
    function withdrawFromVault(uint256 _vaultId) external onlyVaultOwner(_vaultId) {
        Vault storage vault = vaults[_vaultId];

        require(extraVaultParams[_vaultId].isClosed);

        uint256 withdrawAmount0 = vault.collateralAmount0;
        uint256 withdrawAmount1 = vault.collateralAmount1;

        vault.collateralAmount0 = 0;
        vault.collateralAmount1 = 0;

        TransferHelper.safeTransfer(token0, msg.sender, withdrawAmount0);
        TransferHelper.safeTransfer(token1, msg.sender, withdrawAmount1);
    }

    /**
     * Liquidates if margin value is less than min collateral
     */
    function liquidate(
        uint256 _vaultId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) external {
        applyPerpFee(_vaultId);

        // check liquidation
        uint256 currentMargin = getMarginValue(_vaultId);
        uint256 minCollateral = getMinCollateral(_vaultId);

        console2.log(8, currentMargin, minCollateral);
        require(currentMargin < minCollateral, "vault is not danger");

        // calculate reward
        uint256 reward = minCollateral / 100;

        CloseParams memory params = CloseParams(_zeroToOne, _amount, _amountOutMinimum, 0, 0);
        if (isMarginZero) {
            params.penaltyAmount0 = reward;
        } else {
            params.penaltyAmount1 = reward;
        }

        // close position
        _closePositionsInVault(_vaultId, params);

        sendReward(msg.sender, reward);
    }

    /**
     * Liquidates if 75% of collateral value is less than debt value.
     */
    function liquidate3(
        uint256 _vaultId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) external {
        applyPerpFee(_vaultId);

        // check liquidation
        require(extraVaultParams[_vaultId].isLiquidationRequired);

        (uint160 sqrtPrice, ) = callUniswapObserve(1 minutes);

        // calculate value using TWAP price
        uint256 debtValue = getDebtPositionValue(_vaultId, sqrtPrice);

        require((getCollateralPositionValue(_vaultId, sqrtPrice) * 3) / 4 < debtValue);

        // calculate reward
        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, sqrtPrice);
        CloseParams memory params = CloseParams(_zeroToOne, _amount, _amountOutMinimum, amount0 / 100, amount1 / 100);

        // close position
        _closePositionsInVault(_vaultId, params);

        sendReward(msg.sender, params.penaltyAmount0, params.penaltyAmount1);
    }

    function checkLiquidatable(uint256 _vaultId) internal view returns (bool) {
        if (extraVaultParams[_vaultId].isLiquidationRequired) {
            (uint160 sqrtPrice, ) = callUniswapObserve(1 minutes);

            // calculate value using TWAP price
            uint256 debtValue = getDebtPositionValue(_vaultId, sqrtPrice);

            return (getCollateralPositionValue(_vaultId, sqrtPrice) * 3) / 4 < debtValue;
        }

        return false;
    }

    function forceClose(bytes[] memory _data) external onlyOwner {
        for (uint256 i = 0; i < _data.length; i++) {
            (uint256 vaultId, bool _zeroToOne, uint256 _amount, uint256 _amountOutMinimum, uint256 reward) = abi.decode(
                _data[i],
                (uint256, bool, uint256, uint256, uint256)
            );

            applyPerpFee(vaultId);

            _closePositionsInVault(vaultId, CloseParams(_zeroToOne, _amount, _amountOutMinimum, 0, 0));
        }
    }

    // Product API

    /**
     * @notice Deposits tokens.
     * @dev The function can be called from Product contracts.
     */
    function depositTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1,
        bool _withEnteringMarket
    ) external override onlyProductVerifier {
        if (_withEnteringMarket) {
            tokenState0.addCollateral(accountState0[_vaultId], _amount0);
            tokenState1.addCollateral(accountState1[_vaultId], _amount0);
        } else {
            Vault storage vault = vaults[_vaultId];
            vault.collateralAmount0 += _amount0;
            vault.collateralAmount1 += _amount1;
        }
    }

    /**
     * @notice Borrows tokens.
     * @dev The function can be called from Product contracts.
     */
    function borrowTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) external override onlyProductVerifier {
        tokenState0.addDebt(accountState0[_vaultId], _amount0);
        tokenState1.addDebt(accountState1[_vaultId], _amount0);
    }

    function getTokenAmountsToDepositLPT(bytes32 _rangeId, uint128 _liquidity)
        public
        view
        override
        returns (uint256, uint256)
    {
        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(_rangeId);

        return LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, _liquidity);
    }

    function getTokenAmountsToBorrowLPT(
        bytes32 _rangeId,
        uint128 _liquidity,
        uint160 _sqrtPrice
    ) external view override returns (uint256, uint256) {
        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(_rangeId);

        return LiquidityAmounts.getAmountsForLiquidity(_sqrtPrice, sqrtRatioAX96, sqrtRatioBX96, _liquidity);
    }

    /**
     * @notice Deposits Liquidity Provider Token.
     * @dev The function can be called from Product contracts.
     */
    function depositLPT(
        uint256 _vaultId,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity
    ) external override onlyProductVerifier returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = getRangeKey(_lower, _upper);

        (uint256 amount0, uint256 amount1) = getTokenAmountsToDepositLPT(rangeId, _liquidity);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams(ranges[rangeId].tokenId, amount0, amount1, 0, 0, block.timestamp);

        uint128 liquidity;
        (liquidity, requiredAmount0, requiredAmount1) = positionManager.increaseLiquidity(params);

        Vault storage vault = vaults[_vaultId];

        vault.isCollateral.push(true);
        vault.lptIndex.push(rangeId);
        vault.lptLiquidity.push(liquidity);
        vault.lptFeeGrowth.push(ranges[rangeId].cumulativeFee);

        extraVaultParams[_vaultId].fee0Last.push(ranges[rangeId].cumFee0);
        extraVaultParams[_vaultId].fee1Last.push(ranges[rangeId].cumFee1);
    }

    /**
     * @notice Borrows Liquidity Provider Token.
     * @dev The function can be called from Product contracts.
     */
    function borrowLPT(
        uint256 _vaultId,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity
    ) external override onlyProductVerifier returns (uint256, uint256) {
        bytes32 rangeId = getRangeKey(_lower, _upper);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams(ranges[rangeId].tokenId, _liquidity, 0, 0, block.timestamp);

        (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(rangeId, params);

        ranges[rangeId].borrowedLiquidity += _liquidity;

        Vault storage vault = vaults[_vaultId];

        vault.isCollateral.push(false);
        vault.lptIndex.push(rangeId);
        vault.lptLiquidity.push(_liquidity);
        vault.lptFeeGrowth.push(ranges[rangeId].cumulativeFee);

        return (amount0, amount1);
    }

    // Getter Functions

    function getRange(bytes32 _rangeId) external view returns (PerpStatus memory) {
        return ranges[_rangeId];
    }

    function getVaultStatus(uint256 _vaultId)
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        applyPerpFee(_vaultId);

        uint256 debtValue = getDebtPositionValue(_vaultId, sqrtPriceX96);
        uint256 collateralValue = getCollateralPositionValue(_vaultId, sqrtPriceX96);
        uint256 marginValue = getMarginValue(_vaultId);

        return (collateralValue, debtValue, marginValue);
    }

    // Private Functions

    function createOrGetVault(uint256 _vaultId) internal returns (uint256 vaultId, Vault storage) {
        if (_vaultId == 0) {
            vaultId = vaultIdCount;
            vaultIdCount++;

            emit VaultCreated(vaultId);
        } else {
            vaultId = _vaultId;
            require(extraVaultParams[vaultId].owner == msg.sender);
        }

        return (vaultId, vaults[vaultId]);
    }

    function _closePositionsInVault(uint256 _vaultId, CloseParams memory _params) internal {
        Vault storage vault = vaults[_vaultId];

        uint256 tmpVaultAmount0 = tokenState0.getCollateralValue(accountState0[_vaultId]) + vault.collateralAmount0;
        uint256 tmpVaultAmount1 = tokenState1.getCollateralValue(accountState1[_vaultId]) + vault.collateralAmount1;

        if (_params.amount > 0) {
            if (_params.zeroToOne) {
                uint256 requiredA1 = swapExactInput(token0, token1, _params.amount, _params.amountOutMinimum);
                tmpVaultAmount0 -= _params.amount;
                tmpVaultAmount1 += requiredA1;
            } else {
                uint256 requiredA0 = swapExactInput(token1, token0, _params.amount, _params.amountOutMinimum);
                tmpVaultAmount0 += requiredA0;
                tmpVaultAmount1 -= _params.amount;
            }
        }

        (uint256 totalWithdrawAmount0, uint256 totalWithdrawAmount1) = withdrawLPT(_vaultId);

        (uint256 totalRepayAmount0, uint256 totalRepayAmount1) = repayLPT(_vaultId);

        uint256 remainMargin = getMarginValue(_vaultId);

        if (isMarginZero) {
            tmpVaultAmount0 += totalWithdrawAmount0 + remainMargin - totalRepayAmount0 - _params.penaltyAmount0;
            tmpVaultAmount1 += totalWithdrawAmount1 - totalRepayAmount1 - _params.penaltyAmount1;
        } else {
            tmpVaultAmount0 += totalWithdrawAmount0 - totalRepayAmount0 - _params.penaltyAmount0;
            tmpVaultAmount1 += totalWithdrawAmount1 + remainMargin - totalRepayAmount1 - _params.penaltyAmount1;
        }

        vault.collateralAmount0 = tmpVaultAmount0;
        vault.collateralAmount1 = tmpVaultAmount1;

        extraVaultParams[_vaultId].isClosed = true;

        tokenState0.clearCollateral(accountState0[_vaultId]);
        tokenState1.clearCollateral(accountState1[_vaultId]);
        tokenState0.clearDebt(accountState0[_vaultId]);
        tokenState1.clearDebt(accountState1[_vaultId]);

        emit PositionClosed(_vaultId, tmpVaultAmount0, tmpVaultAmount1, _params.penaltyAmount0, _params.penaltyAmount1);
    }

    function withdrawLPT(uint256 _vaultId) internal returns (uint256 totalAmount0, uint256 totalAmount1) {
        Vault storage vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (!vault.isCollateral[i]) {
                continue;
            }
            bytes32 rangeId = vault.lptIndex[i];
            INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams(ranges[rangeId].tokenId, vault.lptLiquidity[i], 0, 0, block.timestamp);

            {
                (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(rangeId, params);
                totalAmount0 += amount0;
                totalAmount1 += amount1;
            }
        }

        {
            (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_vaultId);
            totalAmount0 += fee0;
            totalAmount1 += fee1;
        }

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (!vault.isCollateral[i]) {
                continue;
            }
            bytes32 rangeId = vault.lptIndex[i];

            extraVaultParams[_vaultId].fee0Last[i] = ranges[rangeId].cumFee0;
            extraVaultParams[_vaultId].fee1Last[i] = ranges[rangeId].cumFee1;

            vault.lptLiquidity[i] = 0;
        }
    }

    function repayLPT(uint256 _vaultId) internal returns (uint256 totalAmount0, uint256 totalAmount1) {
        Vault memory vault = vaults[_vaultId];

        totalAmount0 = tokenState0.getDebtValue(accountState0[_vaultId]);
        totalAmount1 = tokenState1.getDebtValue(accountState1[_vaultId]);

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (vault.isCollateral[i]) {
                continue;
            }
            bytes32 rangeId = vault.lptIndex[i];

            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(rangeId);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.lptLiquidity[i]
            );

            ranges[rangeId].borrowedLiquidity -= vault.lptLiquidity[i];

            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams(ranges[rangeId].tokenId, amount0, amount1, 0, 0, block.timestamp);

            (, uint256 actualAmount0, uint256 actualAmount1) = positionManager.increaseLiquidity(params);

            totalAmount0 += actualAmount0;
            totalAmount1 += actualAmount1;

            vault.lptLiquidity[i] = 0;
        }
    }

    function decreaseLiquidityFromUni(
        bytes32 _rangeId,
        INonfungiblePositionManager.DecreaseLiquidityParams memory params
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint128 liquidityAmount = getTotalLiquidityAmount(_rangeId);

        (amount0, amount1) = positionManager.decreaseLiquidity(params);

        collectTokenAmountsFromUni(_rangeId, uint128(amount0), uint128(amount1), liquidityAmount);
    }

    function collectTokenAmountsFromUni(
        bytes32 _rangeId,
        uint128 _amount0,
        uint128 _amount1,
        uint128 _preLiquidity
    ) internal {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            ranges[_rangeId].tokenId,
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        (uint256 a0, uint256 a1) = positionManager.collect(params);

        // Update cumulative trade fee
        ranges[_rangeId].cumFee0 += ((a0 - _amount0) * FixedPoint128.Q128) / _preLiquidity;
        ranges[_rangeId].cumFee1 += ((a1 - _amount1) * FixedPoint128.Q128) / _preLiquidity;
    }

    function sendReward(address _liquidator, uint256 _reward) internal {
        if (isMarginZero) {
            TransferHelper.safeTransfer(token0, _liquidator, _reward);
        } else {
            TransferHelper.safeTransfer(token1, _liquidator, _reward);
        }
    }

    function sendReward(
        address _liquidator,
        uint256 _reward0,
        uint256 _reward1
    ) internal {
        TransferHelper.safeTransfer(token0, _liquidator, _reward0);
        TransferHelper.safeTransfer(token1, _liquidator, _reward1);
    }

    function swapExactInput(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMinimum
    ) public override returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: FEE_TIER,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }

    function swapExactOutput(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut,
        uint256 _amountInMaximum
    ) public override returns (uint256) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: FEE_TIER,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: _amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactOutputSingle(params);
    }

    function getMarginValue(uint256 _vaultId) public view returns (uint256 marginValue) {
        Vault memory vault = vaults[_vaultId];

        marginValue = vault.margin;

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            bytes32 rangeId = vault.lptIndex[i];
            PerpStatus memory perpStatus = ranges[rangeId];

            if (vault.isCollateral[i]) {
                marginValue = marginValue.add(
                    ((perpStatus.cumulativeFeeForLP.sub(vault.lptFeeGrowth[i])) * vault.lptLiquidity[i]) / ONE
                );
            } else {
                marginValue = marginValue.sub(
                    ((perpStatus.cumulativeFee.sub(vault.lptFeeGrowth[i])) * vault.lptLiquidity[i]) / ONE
                );
            }
        }
    }

    function applyPerpFee(uint256 _vaultId) internal {
        Vault memory vault = vaults[_vaultId];

        // calculate fee for perps
        (uint160 sqrtPrice, ) = callUniswapObserve(1 minutes);

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            applyPerpFee(vault.lptIndex[i]);
        }

        updateInterest();
    }

    function updateInterest() internal {
        if (block.timestamp <= lastTouchedTimestamp) {
            return;
        }

        // calculate interest for tokens
        uint256 interest = ((block.timestamp - lastTouchedTimestamp) * pricingModule.calculateInterestRate(getUR())) /
            365 days;

        tokenState0.updateScaler(interest);
        tokenState1.updateScaler(interest);

        lastTouchedTimestamp = block.timestamp;
    }

    function applyPerpFee(bytes32 _rangeId) internal {
        PerpStatus storage perpStatus = ranges[_rangeId];

        if (block.timestamp <= perpStatus.lastTouchedTimestamp) {
            return;
        }

        if (perpStatus.borrowedLiquidity > 0) {
            uint256 premium = ((block.timestamp - perpStatus.lastTouchedTimestamp) *
                pricingModule.calculateDailyPremium(uniswapPool, perpStatus.lower, perpStatus.upper)) / 1 days;
            perpStatus.cumulativeFee += premium;
            perpStatus.cumulativeFeeForLP +=
                (premium * perpStatus.borrowedLiquidity) /
                getTotalLiquidityAmount(_rangeId);
        }

        pricingModule.takeSnapshotForRange(uniswapPool, perpStatus.lower, perpStatus.upper);

        perpStatus.lastTouchedTimestamp = block.timestamp;
    }

    function getMinCollateral(uint256 _vaultId) internal view returns (uint256 minCollateral) {
        Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (vault.isCollateral[i]) {
                continue;
            }
            minCollateral += getMinCollateral(vault.lptIndex[i], vault.lptLiquidity[i]);
        }
    }

    function getMinCollateral(bytes32 _rangeId, uint128 _liquidity) internal view returns (uint256) {
        return
            (_liquidity *
                pricingModule.calculateMinCollateral(uniswapPool, ranges[_rangeId].lower, ranges[_rangeId].upper)) /
            ONE;
    }

    function getPerpUR(bytes32 _rangeId) internal view returns (uint256) {
        uint128 liquidityAmount = getTotalLiquidityAmount(_rangeId);

        return (ranges[_rangeId].borrowedLiquidity * ONE) / liquidityAmount;
    }

    function getUR() internal view returns (uint256) {
        if (tokenState0.totalDeposited == 0) {
            return ONE;
        }
        return (tokenState0.totalBorrowed * ONE) / tokenState0.totalDeposited;
    }

    /**
     * Gets current price of underlying token by margin token.
     */
    function getPrice() external view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        return decodeSqrtPriceX96(sqrtPriceX96);
    }

    function geSqrtPrice() external view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = uniswapPool.slot0();
    }

    /**
     * Gets Time Weighted Average Price of underlying token by margin token.
     */
    function getTWAP() external view returns (uint256) {
        (uint256 sqrtPrice, ) = callUniswapObserve(1 minutes);

        return decodeSqrtPriceX96(sqrtPrice);
    }

    function getSqrtPriceRange(bytes32 _rangeId)
        internal
        view
        returns (uint160 lowerSqrtPrice, uint160 upperSqrtPrice)
    {
        lowerSqrtPrice = TickMath.getSqrtRatioAtTick(ranges[_rangeId].lower);
        upperSqrtPrice = TickMath.getSqrtRatioAtTick(ranges[_rangeId].upper);
    }

    function getTotalLiquidityAmount(bytes32 _rangeId) internal view returns (uint128) {
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(ranges[_rangeId].tokenId);

        return liquidity;
    }

    /**
     * returns collateral value scaled by margin token's decimal
     */
    function getCollateralPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256) {
        uint256 price = decodeSqrtPriceX96(_sqrtPrice);

        (uint256 amount0, uint256 amount1) = getCollateralPositionAmounts(_vaultId, _sqrtPrice);

        if (isMarginZero) {
            return (amount1 * price) / 1e18 + amount0;
        } else {
            return (amount0 * price) / 1e18 + amount1;
        }
    }

    /**
     * returns debt value scaled by margin token's decimal
     */
    function getDebtPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256) {
        uint256 price = decodeSqrtPriceX96(_sqrtPrice);

        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, _sqrtPrice);

        if (isMarginZero) {
            return (amount1 * price) / 1e18 + amount0;
        } else {
            return (amount0 * price) / 1e18 + amount1;
        }
    }

    function getCollateralPositionAmounts(uint256 _vaultId, uint160 _sqrtPrice)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Vault memory vault = vaults[_vaultId];

        // (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (!vault.isCollateral[i]) {
                continue;
            }
            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(vault.lptIndex[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.lptLiquidity[i]
            );

            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_vaultId);
        totalAmount0 += fee0;
        totalAmount1 += fee1;

        totalAmount0 += tokenState0.getCollateralValue(accountState0[_vaultId]);
        totalAmount1 += tokenState1.getCollateralValue(accountState1[_vaultId]);
        totalAmount0 += vault.collateralAmount0;
        totalAmount1 += vault.collateralAmount1;
    }

    function getEarnedTradeFee(uint256 _vaultId) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (!vault.isCollateral[i]) {
                continue;
            }
            bytes32 rangeId = vault.lptIndex[i];
            totalAmount0 =
                ((ranges[rangeId].cumFee0 - extraVaultParams[_vaultId].fee0Last[i]) * vault.lptLiquidity[i]) /
                FixedPoint128.Q128;
            totalAmount1 =
                ((ranges[rangeId].cumFee1 - extraVaultParams[_vaultId].fee1Last[i]) * vault.lptLiquidity[i]) /
                FixedPoint128.Q128;
        }
    }

    function getDebtPositionAmounts(uint256 _vaultId, uint160 _sqrtPrice)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Vault memory vault = vaults[_vaultId];

        // (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (vault.isCollateral[i]) {
                continue;
            }
            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(vault.lptIndex[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.lptLiquidity[i]
            );

            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        totalAmount0 += tokenState0.getDebtValue(accountState0[_vaultId]);
        totalAmount1 += tokenState1.getDebtValue(accountState1[_vaultId]);
    }

    function getPosition(uint256 _vaultId) external view override returns (PositionVerifier.Position memory position) {
        Vault memory vault = vaults[_vaultId];

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](vault.lptIndex.length);

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            bytes32 rangeId = vault.lptIndex[i];
            PerpStatus memory range = ranges[rangeId];
            lpts[i] = PositionVerifier.LPT(vault.isCollateral[i], vault.lptLiquidity[i], range.lower, range.upper);
        }

        position = PositionVerifier.Position(
            tokenState0.getCollateralValue(accountState0[_vaultId]) + vault.collateralAmount0,
            tokenState1.getCollateralValue(accountState1[_vaultId]) + vault.collateralAmount1,
            tokenState0.getDebtValue(accountState0[_vaultId]),
            tokenState1.getDebtValue(accountState1[_vaultId]),
            lpts
        );
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int24) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function callUniswapObserve(uint256 ago) private view returns (uint160, uint256) {
        uint32[] memory secondsAgos = new uint32[](2);

        secondsAgos[0] = uint32(ago);
        secondsAgos[1] = 0;

        (bool success, bytes memory data) = address(uniswapPool).staticcall(
            abi.encodeWithSelector(IUniswapV3PoolOracle.observe.selector, secondsAgos)
        );

        if (!success) {
            if (keccak256(data) != keccak256(abi.encodeWithSignature("Error(string)", "OLD"))) revertBytes(data);

            (, , uint16 index, uint16 cardinality, , , ) = uniswapPool.slot0();

            (uint32 oldestAvailableAge, , , bool initialized) = uniswapPool.observations((index + 1) % cardinality);

            if (!initialized) (oldestAvailableAge, , , ) = uniswapPool.observations(0);

            ago = block.timestamp - oldestAvailableAge;
            secondsAgos[0] = uint32(ago);

            (success, data) = address(uniswapPool).staticcall(
                abi.encodeWithSelector(IUniswapV3PoolOracle.observe.selector, secondsAgos)
            );
            if (!success) revertBytes(data);
        }

        int56[] memory tickCumulatives = abi.decode(data, (int56[]));

        int24 tick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int256(ago)));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        return (sqrtPriceX96, ago);
    }

    function revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }

        revert("e/empty-error");
    }

    function decodeSqrtPriceX96(uint256 sqrtPriceX96) private view returns (uint256 price) {
        uint256 scaler = 1; //10**ERC20(token0).decimals();

        if (isMarginZero) {
            price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**(96 * 2)) / (1e18 * scaler));
            if (price == 0) return 1e36;
            price = 1e36 / price;
        } else {
            price = (FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**96)) * scaler) / uint256(2**96);
        }

        if (price > 1e36) price = 1e36;
        else if (price == 0) price = 1;
    }

    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }
}
