//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";
import "v3-periphery/libraries/TransferHelper.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "v3-core/contracts/libraries/FixedPoint128.sol";
import "v3-periphery/interfaces/ISwapRouter.sol";
import "./base/BaseProduct.sol";
import "./interfaces/IPredyV3Pool.sol";
import "./interfaces/IPricingModule.sol";
import "./vendors/IUniswapV3PoolOracle.sol";
import "forge-std/console2.sol";
import "./libraries/BaseToken.sol";
import "./Constants.sol";

contract PredyV3Pool is IPredyV3Pool, Ownable, Constants {
    using BaseToken for BaseToken.TokenState;

    struct Board {
        uint256 expiration;
        int24[] lowers;
        int24[] uppers;
        uint256[] tokenIds;
        uint256 lastTouchedTimestamp;
    }

    struct PerpStatus {
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
        uint128[] collateralIndex;
        uint128[] collateralLiquidity;
        uint256[] collateralFeeGrowth;
        uint128[] debtIndex;
        uint128[] debtLiquidity;
        uint256[] debtFeeGrowth;
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
    bool isMarginZero;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public uniswapPool;
    ISwapRouter public immutable swapRouter;
    uint24 private constant FEE_TIER = 500;

    mapping(address => address) public strategies;

    IPricingModule public pricingModule;

    uint256 boardIdCount;

    mapping(uint256 => Board) boards;
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

    modifier onlyStrategy() {
        require(strategies[msg.sender] == msg.sender);
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

        boardIdCount = 0;
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

    function setPricingModule(address _pricingModule) external onlyOwner {
        pricingModule = IPricingModule(_pricingModule);
    }
    
    function createBoard(
        uint256 _expiration,
        int24[] memory _lowers,
        int24[] memory _uppers
    ) external {
        uint256[] memory tokenIds = new uint256[](_lowers.length);

        uint128 liquidity = 1e10;

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        (uint256 vaultId, Vault storage vault) = createOrGetVault(0);

        for (uint128 i = 0; i < _lowers.length; i++) {
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_lowers[i]);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_uppers[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity
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
            (uint256 tokenId, , , ) = positionManager.mint(params);
            tokenIds[i] = tokenId;

            vault.collateralIndex.push(i);
            vault.collateralLiquidity.push(liquidity);
            vault.collateralFeeGrowth.push(0);
            extraVaultParams[vaultId].fee0Last.push(0);
            extraVaultParams[vaultId].fee1Last.push(0);
        }

        boards[boardIdCount] = Board(_expiration, _lowers, _uppers, tokenIds, block.timestamp);
        boardIdCount++;
    }

    // User API

    /**
     * @notice Opens new position.
     */
    function openPosition(
        address _strategyId,
        uint256 _boardId,
        uint256 _vaultId,
        uint256 _margin,
        bytes memory _data,
        uint256 _buffer0,
        uint256 _buffer1
    ) external override returns (uint256 vaultId) {
        Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId);

        // check board
        require(_boardId < boardIdCount, "P1");

        vault.margin += _margin;

        extraVaultParams[vaultId].owner = msg.sender;
        extraVaultParams[vaultId].isLiquidationRequired =
            BaseProduct(strategies[_strategyId]).isLiquidationRequired() ||
            extraVaultParams[vaultId].isLiquidationRequired;

        if (isMarginZero) {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), _margin + _buffer0);
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), _buffer1);
        } else {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), _buffer0);
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), _margin + _buffer1);
        }

        (uint256 amount0, uint256 amount1) = BaseProduct(strategies[_strategyId]).openPosition(
            vaultId,
            _boardId,
            _data
        );

        // applyPerpFee(_boardId, vaultId);

        uint256 minCollateral = getMinCollateral(vaultId, _boardId);
        console2.log(_margin, minCollateral);
        require(vault.margin >= minCollateral, "P2");

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
        uint256 _boardId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) public override onlyVaultOwner(_vaultId) {
        applyPerpFee(_boardId, _vaultId);
        _closePositionsInVault(_vaultId, _boardId, CloseParams(_zeroToOne, _amount, _amountOutMinimum, 0, 0));
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
        uint256 _boardId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) external {
        applyPerpFee(_boardId, _vaultId);

        // check liquidation
        uint256 currentMargin = getMarginValue(_vaultId, _boardId);
        uint256 minCollateral = getMinCollateral(_vaultId, _boardId);
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
        _closePositionsInVault(_vaultId, _boardId, params);

        sendReward(msg.sender, reward);
    }

    /**
     * Liquidates if perp option becomes ITM
     */
    function liquidate2(
        uint256 _vaultId,
        uint256 _boardId,
        uint256 _debtIndex,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) external {
        Board memory board = boards[_boardId];
        Vault memory vault = vaults[_vaultId];

        applyPerpFee(_boardId, _vaultId);

        // check liquidation
        require(extraVaultParams[_vaultId].debtInstant[_debtIndex] != InstantDebtType.NONE);

        // check ITM
        (uint160 sqrtPrice, ) = callUniswapObserve(1 minutes);

        if (extraVaultParams[_vaultId].debtInstant[_debtIndex] == InstantDebtType.LONG) {
            uint256 lowerPrice = TickMath.getSqrtRatioAtTick(board.lowers[vault.debtIndex[_debtIndex]]);
            require(sqrtPrice < lowerPrice);
        }

        if (extraVaultParams[_vaultId].debtInstant[_debtIndex] == InstantDebtType.SHORT) {
            uint256 upperPrice = TickMath.getSqrtRatioAtTick(board.uppers[vault.debtIndex[_debtIndex]]);
            require(sqrtPrice < upperPrice);
        }

        // calculate reward
        uint256 reward = getDebtPositionValue(_vaultId, _boardId, sqrtPrice) / 100;

        CloseParams memory params = CloseParams(_zeroToOne, _amount, _amountOutMinimum, 0, 0);
        if (isMarginZero) {
            params.penaltyAmount0 = reward;
        } else {
            params.penaltyAmount1 = reward;
        }

        // close position
        _closePositionsInVault(_vaultId, _boardId, params);

        sendReward(msg.sender, reward);
    }

    /**
     * Liquidates if 75% of collateral value is less than debt value.
     */
    function liquidate3(
        uint256 _vaultId,
        uint256 _boardId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) external {
        applyPerpFee(_boardId, _vaultId);

        // check liquidation
        require(extraVaultParams[_vaultId].isLiquidationRequired);

        (uint160 sqrtPrice, ) = callUniswapObserve(1 minutes);

        // calculate value using TWAP price
        uint256 debtValue = getDebtPositionValue(_vaultId, _boardId, sqrtPrice);

        require((getCollateralPositionValue(_vaultId, _boardId, sqrtPrice) * 3) / 4 < debtValue);

        // calculate reward
        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, _boardId, sqrtPrice);
        CloseParams memory params = CloseParams(_zeroToOne, _amount, _amountOutMinimum, amount0 / 100, amount1 / 100);

        // close position
        _closePositionsInVault(_vaultId, _boardId, params);

        sendReward(msg.sender, params.penaltyAmount0, params.penaltyAmount1);
    }

    function forceClose(uint256 _boardId, bytes[] memory _data) external onlyOwner {
        applyPerpFee(_boardId);

        for (uint256 i = 0; i < _data.length; i++) {
            (uint256 vaultId, bool _zeroToOne, uint256 _amount, uint256 _amountOutMinimum, uint256 reward) = abi.decode(
                _data[i],
                (uint256, bool, uint256, uint256, uint256)
            );

            _closePositionsInVault(vaultId, _boardId, CloseParams(_zeroToOne, _amount, _amountOutMinimum, 0, 0));
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
    ) external override onlyStrategy {
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
    ) external override onlyStrategy {
        tokenState0.addDebt(accountState0[_vaultId], _amount0);
        tokenState1.addDebt(accountState1[_vaultId], _amount0);
    }

    function getTokenAmountsToDepositLPT(
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity
    ) external view override returns (uint256, uint256) {
        Board memory board = boards[_boardId];

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, _index);

        return LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, _liquidity);
    }

    function getTokenAmountsToBorrowLPT(
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity,
        uint160 _sqrtPrice
    ) external view override returns (uint256, uint256) {
        Board memory board = boards[_boardId];

        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, _index);

        return LiquidityAmounts.getAmountsForLiquidity(_sqrtPrice, sqrtRatioAX96, sqrtRatioBX96, _liquidity);
    }

    /**
     * @notice Deposits Liquidity Provider Token.
     * @dev The function can be called from Product contracts.
     */
    function depositLPT(
        uint256 _vaultId,
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity,
        uint256 _amount0,
        uint256 _amount1
    ) external override onlyStrategy returns (uint256, uint256) {
        Board memory board = boards[_boardId];

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams(board.tokenIds[_index], _amount0, _amount1, 0, 0, block.timestamp);

        positionManager.increaseLiquidity(params);

        Vault storage vault = vaults[_vaultId];

        vault.collateralIndex.push(_index);
        vault.collateralLiquidity.push(_liquidity);
        vault.collateralFeeGrowth.push(perpStatuses[_boardId][_index].cumulativeFee);

        extraVaultParams[_vaultId].fee0Last.push(perpStatuses[_boardId][_index].cumFee0);
        extraVaultParams[_vaultId].fee1Last.push(perpStatuses[_boardId][_index].cumFee1);

        return (_amount0, _amount1);
    }

    /**
     * @notice Borrows Liquidity Provider Token.
     * @dev The function can be called from Product contracts.
     */
    function borrowLPT(
        uint256 _vaultId,
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity,
        InstantDebtType _isInstant
    ) external override onlyStrategy returns (uint256, uint256) {
        Board memory board = boards[_boardId];

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams(board.tokenIds[_index], _liquidity, 0, 0, block.timestamp);

        (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(_boardId, _index, params);

        perpStatuses[_boardId][_index].borrowedLiquidity += _liquidity;

        Vault storage vault = vaults[_vaultId];

        vault.debtIndex.push(_index);
        vault.debtLiquidity.push(_liquidity);
        vault.debtFeeGrowth.push(perpStatuses[_boardId][_index].cumulativeFee);

        extraVaultParams[_vaultId].debtInstant.push(_isInstant);

        return (amount0, amount1);
    }

    // Getter Functions

    function getVaultStatus(uint256 _vaultId, uint256 _boardId)
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        applyPerpFee(_boardId, _vaultId);

        uint256 debtValue = getDebtPositionValue(_vaultId, _boardId, sqrtPriceX96);
        uint256 collateralValue = getCollateralPositionValue(_vaultId, _boardId, sqrtPriceX96);
        uint256 marginValue = getMarginValue(_vaultId, _boardId);

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

    function _closePositionsInVault(
        uint256 _vaultId,
        uint256 _boardId,
        CloseParams memory _params
    ) internal {
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

        (uint256 totalWithdrawAmount0, uint256 totalWithdrawAmount1) = withdrawLPT(_vaultId, _boardId);

        (uint256 totalRepayAmount0, uint256 totalRepayAmount1) = repayLPT(_vaultId, _boardId);

        uint256 remainMargin = getMarginValue(_vaultId, _boardId);

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

    function withdrawLPT(uint256 _vaultId, uint256 _boardId)
        internal
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Board memory board = boards[_boardId];
        Vault storage vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            uint128 index = vault.collateralIndex[i];
            INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams(board.tokenIds[index], vault.collateralLiquidity[i], 0, 0, block.timestamp);

            {
                (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(_boardId, index, params);
                totalAmount0 += amount0;
                totalAmount1 += amount1;
            }
        }

        {
            (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_vaultId, _boardId);
            totalAmount0 += fee0;
            totalAmount1 += fee1;
        }

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            uint128 index = vault.collateralIndex[i];

            extraVaultParams[_vaultId].fee0Last[i] = perpStatuses[_boardId][index].cumFee0;
            extraVaultParams[_vaultId].fee1Last[i] = perpStatuses[_boardId][index].cumFee1;

            vault.collateralLiquidity[i] = 0;
        }
    }

    function repayLPT(uint256 _vaultId, uint256 _boardId)
        internal
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Board storage board = boards[_boardId];
        Vault memory vault = vaults[_vaultId];

        totalAmount0 = tokenState0.getDebtValue(accountState0[_vaultId]);
        totalAmount1 = tokenState1.getDebtValue(accountState1[_vaultId]);

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, vault.debtIndex[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.debtLiquidity[i]
            );

            perpStatuses[_boardId][vault.debtIndex[i]].borrowedLiquidity -= vault.debtLiquidity[i];

            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams(board.tokenIds[vault.debtIndex[i]], amount0, amount1, 0, 0, block.timestamp);

            (, uint256 actualAmount0, uint256 actualAmount1) = positionManager.increaseLiquidity(params);

            totalAmount0 += actualAmount0;
            totalAmount1 += actualAmount1;

            vault.debtLiquidity[i] = 0;
        }
    }

    function decreaseLiquidityFromUni(
        uint256 _boardId,
        uint128 _index,
        INonfungiblePositionManager.DecreaseLiquidityParams memory params
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint128 liquidityAmount = getTotalLiquidityAmount(_boardId, _index);

        (amount0, amount1) = positionManager.decreaseLiquidity(params);

        collectTokenAmountsFromUni(_boardId, _index, uint128(amount0), uint128(amount1), liquidityAmount);
    }

    function collectTokenAmountsFromUni(
        uint256 _boardId,
        uint128 _index,
        uint128 _amount0,
        uint128 _amount1,
        uint128 _preLiquidity
    ) internal {
        Board memory board = boards[_boardId];

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            board.tokenIds[_index],
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        (uint256 a0, uint256 a1) = positionManager.collect(params);

        // Update cumulative trade fee
        perpStatuses[_boardId][_index].cumFee0 += ((a0 - _amount0) * FixedPoint128.Q128) / _preLiquidity;
        perpStatuses[_boardId][_index].cumFee1 += ((a1 - _amount1) * FixedPoint128.Q128) / _preLiquidity;
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

    function getMarginValue(uint256 _vaultId, uint256 _boardId) public view returns (uint256 marginValue) {
        Vault memory vault = vaults[_vaultId];

        marginValue = vault.margin;

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            PerpStatus memory perpStatus = perpStatuses[_boardId][vault.collateralIndex[i]];

            marginValue +=
                ((perpStatus.cumulativeFeeForLP - vault.collateralFeeGrowth[i]) * vault.collateralLiquidity[i]) /
                ONE;
        }

        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            PerpStatus memory perpStatus = perpStatuses[_boardId][vault.debtIndex[i]];

            marginValue -= ((perpStatus.cumulativeFee - vault.debtFeeGrowth[i]) * vault.debtLiquidity[i]) / ONE;
        }
    }

    function applyPerpFee(uint256 _boardId) internal {
        Board memory board = boards[_boardId];

        // calculate fee for perps
        (uint160 sqrtPrice, ) = callUniswapObserve(1 minutes);

        for (uint256 i = 0; i < board.lowers.length; i++) {
            applyPerpFee(_boardId, i, sqrtPrice);
        }

        updateInterest(_boardId, sqrtPrice);
    }

    function applyPerpFee(uint256 _boardId, uint256 _vaultId) internal {
        Board storage board = boards[_boardId];
        Vault memory vault = vaults[_vaultId];

        // calculate fee for perps
        (uint160 sqrtPrice, ) = callUniswapObserve(1 minutes);

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            applyPerpFee(_boardId, vault.collateralIndex[i], sqrtPrice);
        }

        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            applyPerpFee(_boardId, vault.debtIndex[i], sqrtPrice);
        }

        updateInterest(_boardId, sqrtPrice);
    }

    function updateInterest(uint256 _boardId, uint256 _sqrtPrice) internal {
        Board storage board = boards[_boardId];

        if (block.timestamp <= board.lastTouchedTimestamp) {
            return;
        }

        // calculate interest for tokens
        uint256 interest = ((block.timestamp - board.lastTouchedTimestamp) *
            pricingModule.calculateInterestRate(getUR())) / 365 days;

        tokenState0.updateScaler(interest);
        tokenState1.updateScaler(interest);

        board.lastTouchedTimestamp = block.timestamp;
    }

    function applyPerpFee(
        uint256 _boardId,
        uint256 _index,
        uint256 _sqrtPrice
    ) internal {
        PerpStatus storage perpStatus = perpStatuses[_boardId][_index];

        if (block.timestamp <= perpStatus.lastTouchedTimestamp) {
            return;
        }

        if (perpStatus.borrowedLiquidity > 0) {
            uint256 premium = ((block.timestamp - perpStatus.lastTouchedTimestamp) *
                pricingModule.calculateDailyPremium(
                    uniswapPool,
                    boards[_boardId].lowers[_index],
                    boards[_boardId].uppers[_index]
                )) / 1 days;
            perpStatus.cumulativeFee += premium;
            perpStatus.cumulativeFeeForLP +=
                (premium * perpStatus.borrowedLiquidity) /
                getTotalLiquidityAmount(_boardId, _index);
        }

        pricingModule.takeSnapshotForRange(
            uniswapPool,
            boards[_boardId].lowers[_index],
            boards[_boardId].uppers[_index]
        );

        perpStatus.lastTouchedTimestamp = block.timestamp;
    }

    function getMinCollateral(uint256 _vaultId, uint256 _boardId) internal view returns (uint256 minCollateral) {
        Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            minCollateral += getMinCollateral(_boardId, vault.debtIndex[i], vault.debtLiquidity[i]);
        }
    }

    function getMinCollateral(
        uint256 _boardId,
        uint256 _index,
        uint128 _liquidity
    ) internal view returns (uint256) {
        return
            (_liquidity *
                pricingModule.calculateMinCollateral(
                    uniswapPool,
                    boards[_boardId].lowers[_index],
                    boards[_boardId].uppers[_index]
                )) / ONE;
    }

    function getPerpUR(uint256 _boardId, uint256 _index) internal view returns (uint256) {
        PerpStatus memory perpStatus = perpStatuses[_boardId][_index];

        uint128 liquidityAmount = getTotalLiquidityAmount(_boardId, _index);

        return (perpStatus.borrowedLiquidity * ONE) / liquidityAmount;
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

    /**
     * Gets Time Weighted Average Price of underlying token by margin token.
     */
    function getTWAP() external view returns (uint256) {
        (uint256 sqrtPrice, ) = callUniswapObserve(1 minutes);

        return decodeSqrtPriceX96(sqrtPrice);
    }

    function getSqrtPriceRange(Board memory board, uint256 _index)
        internal
        pure
        returns (uint160 lowerSqrtPrice, uint160 upperSqrtPrice)
    {
        lowerSqrtPrice = TickMath.getSqrtRatioAtTick(board.lowers[_index]);
        upperSqrtPrice = TickMath.getSqrtRatioAtTick(board.uppers[_index]);
    }

    /**
     * option size -> liquidity
     */
    function getLiquidityForOptionAmount(
        uint256 _boardId,
        uint256 _index,
        uint256 _amount
    ) public view returns (uint128) {
        (uint160 lowerSqrtPrice, uint160 upperSqrtPrice) = getSqrtPriceRange(boards[_boardId], _index);

        if (isMarginZero) {
            // amount / (sqrt(upper) - sqrt(lower))
            return LiquidityAmounts.getLiquidityForAmount1(lowerSqrtPrice, upperSqrtPrice, _amount);
        } else {
            // amount * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
            return LiquidityAmounts.getLiquidityForAmount0(lowerSqrtPrice, upperSqrtPrice, _amount);
        }
    }

    function getTotalLiquidityAmount(uint256 _boardId, uint256 _index) internal view returns (uint128) {
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(boards[_boardId].tokenIds[_index]);

        return liquidity;
    }

    /**
     * returns collateral value scaled by margin token's decimal
     */
    function getCollateralPositionValue(
        uint256 _vaultId,
        uint256 _boardId,
        uint160 _sqrtPrice
    ) internal view returns (uint256) {
        uint256 price = decodeSqrtPriceX96(_sqrtPrice);

        (uint256 amount0, uint256 amount1) = getCollateralPositionAmounts(_vaultId, _boardId, _sqrtPrice);

        if (isMarginZero) {
            return (amount1 * price) / 1e18 + amount0;
        } else {
            return (amount0 * price) / 1e18 + amount1;
        }
    }

    /**
     * returns debt value scaled by margin token's decimal
     */
    function getDebtPositionValue(
        uint256 _vaultId,
        uint256 _boardId,
        uint160 _sqrtPrice
    ) internal view returns (uint256) {
        uint256 price = decodeSqrtPriceX96(_sqrtPrice);

        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, _boardId, _sqrtPrice);

        if (isMarginZero) {
            return (amount1 * price) / 1e18 + amount0;
        } else {
            return (amount0 * price) / 1e18 + amount1;
        }
    }

    function getCollateralPositionAmounts(
        uint256 _vaultId,
        uint256 _boardId,
        uint160 _sqrtPrice
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        Vault memory vault = vaults[_vaultId];
        Board memory board = boards[_boardId];

        // (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, vault.collateralIndex[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.collateralLiquidity[i]
            );

            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_vaultId, _boardId);
        totalAmount0 += fee0;
        totalAmount1 += fee1;

        totalAmount0 += tokenState0.getCollateralValue(accountState0[_vaultId]);
        totalAmount1 += tokenState1.getCollateralValue(accountState1[_vaultId]);
        totalAmount0 += vault.collateralAmount0;
        totalAmount1 += vault.collateralAmount1;
    }

    function getEarnedTradeFee(uint256 _vaultId, uint256 _boardId)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            uint256 index = vault.collateralIndex[i];
            totalAmount0 =
                ((perpStatuses[_boardId][index].cumFee0 - extraVaultParams[_vaultId].fee0Last[i]) *
                    vault.collateralLiquidity[i]) /
                FixedPoint128.Q128;
            totalAmount1 =
                ((perpStatuses[_boardId][index].cumFee1 - extraVaultParams[_vaultId].fee1Last[i]) *
                    vault.collateralLiquidity[i]) /
                FixedPoint128.Q128;
        }
    }

    function getDebtPositionAmounts(
        uint256 _vaultId,
        uint256 _boardId,
        uint160 _sqrtPrice
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        Vault memory vault = vaults[_vaultId];
        Board memory board = boards[_boardId];

        // (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, vault.debtIndex[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.debtLiquidity[i]
            );

            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        totalAmount0 += tokenState0.getDebtValue(accountState0[_vaultId]);
        totalAmount1 += tokenState1.getDebtValue(accountState1[_vaultId]);
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
}
