//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import "./interfaces/IPredyV3Pool.sol";
import "./interfaces/IPricingModule.sol";
import "./interfaces/IProductVerifier.sol";
import {BaseToken} from "./libraries/BaseToken.sol";
import "./libraries/VaultLib.sol";
import "./Constants.sol";
import "./LPTMathModule.sol";


contract PredyV3Pool is IPredyV3Pool, Ownable, Constants {
    using BaseToken for BaseToken.TokenState;
    using SafeMath for uint256;
    using VaultLib for VaultLib.Vault;

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

    address private token0;
    address private token1;
    bool public override isMarginZero;

    INonfungiblePositionManager private positionManager;
    IUniswapV3Pool private uniswapPool;
    ISwapRouter private immutable swapRouter;

    IProductVerifier public productVerifier;
    IPricingModule public pricingModule;
    LPTMathModule private lptMathModule;

    uint256 private lastTouchedTimestamp;

    mapping(bytes32 => VaultLib.PerpStatus) private ranges;

    uint256 public vaultIdCount;

    mapping(uint256 => VaultLib.Vault) private vaults;
    mapping(uint256 => ExtraVaultParam) private extraVaultParams;
    mapping(uint256 => BaseToken.AccountState) private accountState0;
    mapping(uint256 => BaseToken.AccountState) private accountState1;

    BaseToken.TokenState private tokenState0;
    BaseToken.TokenState private tokenState1;

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

    function setLPTMathModule(address _lptMathModule) external onlyOwner {
        lptMathModule = LPTMathModule(_lptMathModule);
    }

    function setProductVerifier(address _productVerifier) external onlyOwner {
        productVerifier = IProductVerifier(_productVerifier);
    }

    function setPricingModule(address _pricingModule) external onlyOwner {
        pricingModule = IPricingModule(_pricingModule);
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

        VaultLib.Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId);

        // vault.margin += _margin;
        vault.setMargin(_margin);

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
        VaultLib.Vault storage vault = vaults[_vaultId];

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
        require(checkLiquidatable(_vaultId));

        (uint160 sqrtPrice, ) = lptMathModule.callUniswapObserve(uniswapPool, 1 minutes);

        // calculate reward
        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, sqrtPrice);
        CloseParams memory params = CloseParams(_zeroToOne, _amount, _amountOutMinimum, amount0 / 100, amount1 / 100);

        // close position
        _closePositionsInVault(_vaultId, params);

        sendReward(msg.sender, params.penaltyAmount0, params.penaltyAmount1);
    }

    function checkLiquidatable(uint256 _vaultId) internal view returns (bool) {
        if (extraVaultParams[_vaultId].isLiquidationRequired) {
            (uint160 sqrtPrice, ) = lptMathModule.callUniswapObserve(uniswapPool, 1 minutes);

            // calculate value using TWAP price
            (uint256 collateralValue, uint256 debtValue) = getPositionValue(_vaultId, sqrtPrice);

            return (collateralValue * 3) / 4 < debtValue;
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
            VaultLib.Vault storage vault = vaults[_vaultId];
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

    function getTokenAmountsToBorrowLPT(
        bytes32 _rangeId,
        uint128 _liquidity,
        uint160 _sqrtPrice
    ) external view override returns (uint256, uint256) {
        return lptMathModule.getAmountsForLiquidity(
            _sqrtPrice, 
            ranges[_rangeId].lower,
            ranges[_rangeId].upper,
            _liquidity
        );
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

        (uint256 amount0, uint256 amount1) = lptMathModule.getAmountsForLiquidity(
            getSqrtPrice(), 
            _lower,
            _upper,
            _liquidity
        );

        uint128 liquidity;
        if(ranges[rangeId].tokenId > 0) {
            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams(ranges[rangeId].tokenId, amount0, amount1, 0, 0, block.timestamp);

            (liquidity, requiredAmount0, requiredAmount1) = positionManager.increaseLiquidity(params);

        } else {
            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
                token0,
                token1,
                FEE_TIER,
                _lower,
                _upper,
                amount0,
                amount1,
                0,
                0,
                address(this),
                block.timestamp
            );

            (ranges[rangeId].tokenId, liquidity, requiredAmount0, requiredAmount1) = positionManager.mint(params);
            ranges[rangeId].lower = _lower;
            ranges[rangeId].upper = _upper;
        }

        VaultLib.Vault storage vault = vaults[_vaultId];

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

        (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(ranges[rangeId].tokenId, _liquidity, rangeId);

        ranges[rangeId].borrowedLiquidity += _liquidity;

        VaultLib.Vault storage vault = vaults[_vaultId];

        vault.isCollateral.push(false);
        vault.lptIndex.push(rangeId);
        vault.lptLiquidity.push(_liquidity);
        vault.lptFeeGrowth.push(ranges[rangeId].cumulativeFee);

        return (amount0, amount1);
    }

    // Getter Functions

    function getRange(bytes32 _rangeId) external view returns (VaultLib.PerpStatus memory) {
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
        uint160 sqrtPriceX96 = getSqrtPrice();

        applyPerpFee(_vaultId);

        (uint256 collateralValue, uint256 debtValue) = getPositionValue(_vaultId, sqrtPriceX96);
        uint256 marginValue = getMarginValue(_vaultId);

        return (collateralValue, debtValue, marginValue);
    }

    // Private Functions

    function createOrGetVault(uint256 _vaultId) internal returns (uint256 vaultId, VaultLib.Vault storage) {
        if (_vaultId == 0) {
            vaultId = vaultIdCount;
            vaultIdCount++;
            extraVaultParams[vaultId].owner = msg.sender;
            
            emit VaultCreated(vaultId);
        } else {
            vaultId = _vaultId;
            require(extraVaultParams[vaultId].owner == msg.sender);
        }

        return (vaultId, vaults[vaultId]);
    }

    function _closePositionsInVault(uint256 _vaultId, CloseParams memory _params) internal {
        VaultLib.Vault storage vault = vaults[_vaultId];

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
        VaultLib.Vault storage vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (!vault.isCollateral[i]) {
                continue;
            }
            bytes32 rangeId = vault.lptIndex[i];

            {
                (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(ranges[rangeId].tokenId, vault.lptLiquidity[i], rangeId);
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
        VaultLib.Vault memory vault = vaults[_vaultId];

        totalAmount0 = tokenState0.getDebtValue(accountState0[_vaultId]);
        totalAmount1 = tokenState1.getDebtValue(accountState1[_vaultId]);

        uint160 sqrtPriceX96 = getSqrtPrice();

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (vault.isCollateral[i]) {
                continue;
            }
            bytes32 rangeId = vault.lptIndex[i];

            (uint256 amount0, uint256 amount1) = lptMathModule.getAmountsForLiquidity(
                sqrtPriceX96,
                ranges[rangeId].lower,
                ranges[rangeId].upper,
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
        uint256 _tokenId,
        uint128 _liquidity,
        bytes32 _rangeId
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint256 liquidityAmount = getTotalLiquidityAmount(_rangeId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams(_tokenId, _liquidity, 0, 0, block.timestamp);

        (amount0, amount1) = positionManager.decreaseLiquidity(params);

        collectTokenAmountsFromUni(_rangeId, amount0, amount1, liquidityAmount);
    }

    function collectTokenAmountsFromUni(
        bytes32 _rangeId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _preLiquidity
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
        TransferHelper.safeTransfer(isMarginZero ? token0 : token1, _liquidator, _reward);
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
    ) internal returns (uint256) {
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
        bool _zeroForOne,
        uint256 _amountOut,
        uint256 _amountInMaximum
    ) external override onlyProductVerifier returns (uint256) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _zeroForOne?token0:token1,
            tokenOut: _zeroForOne?token1:token0,
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
        return vaults[_vaultId].getMarginValue(ranges, _vaultId);
    }

    function applyPerpFee(uint256 _vaultId) internal {
        VaultLib.Vault memory vault = vaults[_vaultId];

        // calculate fee for perps
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
        VaultLib.PerpStatus storage perpStatus = ranges[_rangeId];

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
        VaultLib.Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (vault.isCollateral[i]) {
                continue;
            }
            minCollateral += getMinCollateral(vault.lptIndex[i], vault.lptLiquidity[i]);
        }
    }

    function getMinCollateral(bytes32 _rangeId, uint256 _liquidity) internal view returns (uint256) {
        return
            (_liquidity *
                pricingModule.calculateMinCollateral(uniswapPool, ranges[_rangeId].lower, ranges[_rangeId].upper)) /
            ONE;
    }
    
    function getPerpUR(bytes32 _rangeId) internal view returns (uint256) {
        return (ranges[_rangeId].borrowedLiquidity * ONE) / getTotalLiquidityAmount(_rangeId);
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
        return lptMathModule.decodeSqrtPriceX96(isMarginZero, getSqrtPrice());
    }

    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = uniswapPool.slot0();
    }

    /**
     * Gets Time Weighted Average Price of underlying token by margin token.
     */
    function getTWAP() external view returns (uint256) {
        (uint256 sqrtPrice, ) = lptMathModule.callUniswapObserve(uniswapPool, 1 minutes);

        return lptMathModule.decodeSqrtPriceX96(isMarginZero, sqrtPrice);

    }

    function getTotalLiquidityAmount(bytes32 _rangeId) internal view returns (uint256) {
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(ranges[_rangeId].tokenId);

        return liquidity;
    }

    /**
     * returns collateral and debt value scaled by margin token's decimal
     */
    function getPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256, uint256) {
        uint256 price = lptMathModule.decodeSqrtPriceX96(isMarginZero, _sqrtPrice);

        (uint256 collateralAmount0, uint256 collateralAmount1) = getCollateralPositionAmounts(_vaultId, _sqrtPrice);
        (uint256 debtAmount0, uint256 debtAmount1) = getDebtPositionAmounts(_vaultId, _sqrtPrice);

        if (isMarginZero) {
            return ((collateralAmount1 * price) / 1e18 + collateralAmount0, (debtAmount1 * price) / 1e18 + debtAmount0);
        } else {
            return ((collateralAmount0 * price) / 1e18 + collateralAmount1, (debtAmount0 * price) / 1e18 + debtAmount1);
        }
    }

    function getCollateralPositionAmounts(uint256 _vaultId, uint160 _sqrtPrice)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        VaultLib.Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (!vault.isCollateral[i]) {
                continue;
            }

            (uint256 amount0, uint256 amount1) = lptMathModule.getAmountsForLiquidity(
                _sqrtPrice,
                ranges[vault.lptIndex[i]].lower,
                ranges[vault.lptIndex[i]].upper,
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
        VaultLib.Vault memory vault = vaults[_vaultId];

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
        VaultLib.Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            if (vault.isCollateral[i]) {
                continue;
            }

            (uint256 amount0, uint256 amount1) = lptMathModule.getAmountsForLiquidity(
                _sqrtPrice,
                ranges[vault.lptIndex[i]].lower,
                ranges[vault.lptIndex[i]].upper,
                vault.lptLiquidity[i]
            );

            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        totalAmount0 += tokenState0.getDebtValue(accountState0[_vaultId]);
        totalAmount1 += tokenState1.getDebtValue(accountState1[_vaultId]);
    }

    function getPosition(uint256 _vaultId) external view override returns (PositionVerifier.Position memory position) {
        VaultLib.Vault memory vault = vaults[_vaultId];

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](vault.lptIndex.length);

        for (uint256 i = 0; i < vault.lptIndex.length; i++) {
            bytes32 rangeId = vault.lptIndex[i];
            VaultLib.PerpStatus memory range = ranges[rangeId];
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

    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }
}
