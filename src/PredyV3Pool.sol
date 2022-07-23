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
import "./base/BaseStrategy.sol";
import "./interfaces/IPredyV3Pool.sol";
import "./interfaces/IPricingModule.sol";

interface IUniswapV3PoolOracle {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function liquidity() external view returns (uint128);

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory liquidityCumulatives);

    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 liquidityCumulative,
            bool initialized
        );

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}

/**
 * |---|---|
 */
contract PredyV3Pool is IPredyV3Pool {
    struct Board {
        uint256 expiration;
        int24[] lowers;
        int24[] uppers;
        uint256[] tokenIds;
        uint256 lastTouchedTimestamp;
    }

    struct PerpStatus {
        uint128 borrowedLiquidity;
        uint128 instantBorrowedLiquidity;
        uint256 cumulativeFee;
        uint256 instantCumulativeFee;
        uint256 cumulativeFeeForLP;
        uint256 cumFee0;
        uint256 cumFee1;
    }

    struct Vault {
        uint256 margin;
        uint256 collateralAmount0;
        uint256 collateralAmount1;
        uint256 debtAmount0;
        uint256 debtAmount1;
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

    uint256 volatility;

    uint256 totalDeposited0;
    uint256 totalBorrowed0;
    uint256 totalDeposited1;
    uint256 totalBorrowed1;
    uint256 cumInterest0;
    uint256 cumInterest1;

    event VaultCreated(uint256 vaultId);

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

        ERC20(token0).approve(address(positionManager), 1e24);
        ERC20(token1).approve(address(positionManager), 1e24);
        ERC20(token0).approve(address(_swapRouter), 1e24);
        ERC20(token1).approve(address(_swapRouter), 1e24);
    }

    function addStrategy(address _strategyAddress) external {
        strategies[_strategyAddress] = _strategyAddress;
    }

    function setPricingModule(address _pricingModule) external {
        pricingModule = IPricingModule(_pricingModule);
    }

    function updateVolatility(uint256 _volatility) external {
        volatility = _volatility;
    }

    function createBoard(
        uint256 _expiration,
        int24[] memory _lowers,
        int24[] memory _uppers
    ) external {
        uint256[] memory tokenIds = new uint256[](_lowers.length);

        uint128 liquidity = 1e10;

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        (uint256 vaultId, Vault storage vault) = createVault();

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

    function openStrategy(
        address _strategyId,
        uint256 _boardId,
        uint256 _margin,
        bytes memory _data,
        uint256 _buffer0,
        uint256 _buffer1
    ) external override returns (uint256 vaultId) {
        Vault storage vault;
        (vaultId, vault) = createVault();

        // check board
        require(_boardId < boardIdCount, "P1");

        applyPerpFee(_boardId);

        vault.margin += _margin;
        extraVaultParams[vaultId].owner = msg.sender;
        
        extraVaultParams[vaultId].isLiquidationRequired = BaseStrategy(strategies[_strategyId]).isLiquidationRequired();

        if (isMarginZero) {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), _margin + _buffer0);
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), _buffer1);
        } else {
            TransferHelper.safeTransferFrom(token0, msg.sender, address(this), _buffer0);
            TransferHelper.safeTransferFrom(token1, msg.sender, address(this), _margin + _buffer1);
        }

        (uint256 amount0, uint256 amount1) = BaseStrategy(strategies[_strategyId]).openPosition(
            vaultId,
            _boardId,
            _data
        );

        uint256 minCollateral = getMinCollateral(vaultId, _boardId);
        require(vault.margin >= minCollateral, "P2");

        if (_buffer0 > amount0) {
            TransferHelper.safeTransfer(token0, msg.sender, _buffer0 - amount0);
        }
        if (_buffer1 > amount1) {
            TransferHelper.safeTransfer(token1, msg.sender, _buffer1 - amount1);
        }
    }

    function closePositionsInVault(
        uint256 _vaultId,
        uint256 _boardId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) public override onlyVaultOwner(_vaultId) {
        _closePositionsInVault(_vaultId, _boardId, _zeroToOne, _amount, _amountOutMinimum);
    }

    function withdrawFromVault(
        uint256 _vaultId
    ) external onlyVaultOwner(_vaultId) {
        Vault storage vault = vaults[_vaultId];

        require(extraVaultParams[_vaultId].isClosed);

        uint256 withdrawAmount0 = vault.collateralAmount0;
        uint256 withdrawAmount1 = vault.collateralAmount1;

        vault.collateralAmount0 = 0;
        vault.collateralAmount1 = 0;

        TransferHelper.safeTransfer(
            token0,
            msg.sender,
            withdrawAmount0
        );
        TransferHelper.safeTransfer(
            token1,
            msg.sender,
            withdrawAmount1
        );
    }

    function depositTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) external override onlyStrategy {
        Vault storage vault = vaults[_vaultId];

        vault.collateralAmount0 += _amount0;
        vault.collateralAmount1 += _amount1;

        totalDeposited0 += _amount0;
        totalDeposited1 += _amount1;
    }

    function borrowTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) external override onlyStrategy {
        Vault storage vault = vaults[_vaultId];

        require(totalDeposited0 > totalBorrowed0 + _amount0);
        require(totalDeposited1 > totalBorrowed1 + _amount1);

        vault.debtAmount0 += _amount0;
        vault.debtAmount1 += _amount1;

        totalBorrowed0 += _amount0;
        totalBorrowed1 += _amount1;
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
        bool _isCall
    ) external view override returns (uint256, uint256) {
        Board memory board = boards[_boardId];

        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, _index);

        return
            LiquidityAmounts.getAmountsForLiquidity(
                _isCall ? sqrtRatioAX96 : sqrtRatioBX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                _liquidity
            );
    }

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

        if (_isInstant != InstantDebtType.NONE) {
            perpStatuses[_boardId][_index].instantBorrowedLiquidity += _liquidity;
        } else {
            perpStatuses[_boardId][_index].borrowedLiquidity += _liquidity;
        }

        Vault storage vault = vaults[_vaultId];

        vault.debtIndex.push(_index);
        vault.debtLiquidity.push(_liquidity);

        if (_isInstant != InstantDebtType.NONE) {
            vault.debtFeeGrowth.push(perpStatuses[_boardId][_index].instantCumulativeFee);
        } else {
            vault.debtFeeGrowth.push(perpStatuses[_boardId][_index].cumulativeFee);
        }

        extraVaultParams[_vaultId].debtInstant.push(_isInstant);

        return (amount0, amount1);
    }

    function createVault() internal returns (uint256 vaultId, Vault storage) {
        vaultId = vaultIdCount;
        vaultIdCount++;

        emit VaultCreated(vaultId);

        return (vaultId, vaults[vaultId]);
    }

    function _closePositionsInVault(
        uint256 _vaultId,
        uint256 _boardId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) internal {
        Vault storage vault = vaults[_vaultId];

        applyPerpFee(_boardId);

        if (_amount > 0) {
            if (_zeroToOne) {
                uint256 requiredA1 = swapExactInput(token0, token1, _amount, _amountOutMinimum);
                vault.collateralAmount0 -= _amount;
                vault.collateralAmount1 += requiredA1;
            } else {
                uint256 requiredA0 = swapExactInput(token1, token0, _amount, _amountOutMinimum);
                vault.collateralAmount0 += requiredA0;
                vault.collateralAmount1 -= _amount;
            }
        }

        (uint256 totalWithdrawAmount0, uint256 totalWithdrawAmount1) = withdraw(_vaultId, _boardId);

        (uint256 totalRepayAmount0, uint256 totalRepayAmount1) = repayDebtLpt(_vaultId, _boardId);

        uint256 remainMargin = getMarginValue(_vaultId, _boardId);

        if (isMarginZero) {
            vault.collateralAmount0 += totalWithdrawAmount0 + remainMargin - totalRepayAmount0;
            vault.collateralAmount1 += totalWithdrawAmount1 - totalRepayAmount1;
        } else {
            vault.collateralAmount0 += totalWithdrawAmount0 - totalRepayAmount0;
            vault.collateralAmount1 += totalWithdrawAmount1 + remainMargin - totalRepayAmount1;
        }

        extraVaultParams[_vaultId].isClosed = true;
    }

    function withdraw(uint256 _vaultId, uint256 _boardId)
        internal
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Board memory board = boards[_boardId];
        Vault storage vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            uint128 index = vault.collateralIndex[i];
            INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams(board.tokenIds[index], vault.collateralLiquidity[i], 0, 0, block.timestamp);

            (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(_boardId, index, params);

            totalAmount0 += amount0;
            totalAmount1 += amount1;

            totalAmount0 +=
                ((perpStatuses[_boardId][index].cumFee0 - extraVaultParams[_vaultId].fee0Last[i]) *
                    vault.collateralLiquidity[i]) /
                FixedPoint128.Q128;
            totalAmount1 +=
                ((perpStatuses[_boardId][index].cumFee1 - extraVaultParams[_vaultId].fee1Last[i]) *
                    vault.collateralLiquidity[i]) /
                FixedPoint128.Q128;

            extraVaultParams[_vaultId].fee0Last[i] = perpStatuses[_boardId][index].cumFee0;
            extraVaultParams[_vaultId].fee1Last[i] = perpStatuses[_boardId][index].cumFee1;

            vault.collateralLiquidity[i] = 0;
        }
    }

    function repayDebtLpt(uint256 _vaultId, uint256 _boardId)
        internal
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Board storage board = boards[_boardId];
        Vault memory vault = vaults[_vaultId];

        totalAmount0 = vault.debtAmount0;
        totalAmount1 = vault.debtAmount1;

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

        vault.debtAmount0 = 0;
        vault.debtAmount1 = 0;
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
        applyPerpFee(_boardId);

        uint256 currentMargin = getMarginValue(_vaultId, _boardId);

        // TODO: calculate min collateral
        uint256 minCollateral = getMinCollateral(_vaultId, _boardId);
        require(currentMargin < minCollateral, "vault is not danger");

        uint256 reward = minCollateral / 100;

        decreaseReward(_vaultId, reward);

        _closePositionsInVault(_vaultId, _boardId, _zeroToOne, _amount, _amountOutMinimum);

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

        applyPerpFee(_boardId);

        require(extraVaultParams[_vaultId].debtInstant[_debtIndex] != InstantDebtType.NONE);

        // check ITM
        (uint256 sqrtPrice, ) = callUniswapObserve(1 minutes);

        if (extraVaultParams[_vaultId].debtInstant[_debtIndex] == InstantDebtType.LONG) {
            uint256 lowerPrice = TickMath.getSqrtRatioAtTick(board.lowers[vault.debtIndex[_debtIndex]]);
            require(sqrtPrice < lowerPrice);
        }

        if (extraVaultParams[_vaultId].debtInstant[_debtIndex] == InstantDebtType.SHORT) {
            uint256 upperPrice = TickMath.getSqrtRatioAtTick(board.uppers[vault.debtIndex[_debtIndex]]);
            require(sqrtPrice < upperPrice);
        }

        uint256 reward = getDebtPositionValue(_vaultId, _boardId, decodeSqrtPriceX96(sqrtPrice)) / 100;

        decreaseReward(_vaultId, reward);

        _closePositionsInVault(_vaultId, _boardId, _zeroToOne, _amount, _amountOutMinimum);

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
        applyPerpFee(_boardId);

        require(extraVaultParams[_vaultId].isLiquidationRequired);

        (uint256 sqrtPrice, ) = callUniswapObserve(1 minutes);
        uint256 price = decodeSqrtPriceX96(sqrtPrice);

        // calculate value using TWAP price
        uint256 debtValue = getDebtPositionValue(_vaultId, _boardId, price);

        require(
            getCollateralPositionValue(_vaultId, _boardId, price) * 3 / 4 < debtValue
        );

        uint256 reward = debtValue / 100;
        decreaseReward(_vaultId, reward);

        _closePositionsInVault(_vaultId, _boardId, _zeroToOne, _amount, _amountOutMinimum);

        sendReward(msg.sender, reward);
    }

    function decreaseReward(uint256 _vaultId, uint256 _reward) internal {
        vaults[_vaultId].margin -=_reward;
    }

    function sendReward(address _liquidator, uint256 _reward) internal {
        if(isMarginZero) {
            TransferHelper.safeTransfer(
                token0,
                _liquidator,
                _reward
            );
        } else {
            TransferHelper.safeTransfer(
                token1,
                _liquidator,
                _reward
            );        
        }
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
                1e16;
        }
        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            PerpStatus memory perpStatus = perpStatuses[_boardId][vault.debtIndex[i]];

            if (extraVaultParams[_vaultId].debtInstant[i] != InstantDebtType.NONE) {
                marginValue -=
                    ((perpStatus.instantCumulativeFee - vault.debtFeeGrowth[i]) * vault.debtLiquidity[i]) /
                    1e16;
            } else {
                marginValue -= ((perpStatus.cumulativeFee - vault.debtFeeGrowth[i]) * vault.debtLiquidity[i]) / 1e16;
            }
        }
    }

    function applyPerpFee(uint256 _boardId) internal {
        Board storage board = boards[_boardId];

        if (block.timestamp <= board.lastTouchedTimestamp) {
            return;
        }

        // calculate fee for perps

        // TODO: change TWAP time
        (uint256 sqrtPrice, ) = callUniswapObserve(1 minutes);

        for (uint256 i = 0; i < board.lowers.length; i++) {
            applyPerpFee(_boardId, i, sqrtPrice, board.lastTouchedTimestamp);
        }

        // calculate interest for tokens
        {
            uint256 a = ((block.timestamp - board.lastTouchedTimestamp) *
                pricingModule.calculateInstantRate(sqrtPrice, getUR())) / 1 days;
            cumInterest0 += a;
            cumInterest1 += a;
        }

        board.lastTouchedTimestamp = block.timestamp;
    }

    function applyPerpFee(
        uint256 _boardId,
        uint256 _index,
        uint256 _sqrtPrice,
        uint256 _lastTouchedTimestamp
    ) internal {
        PerpStatus storage perpStatus = perpStatuses[_boardId][_index];

        (uint256 lowerSqrtPrice, uint256 upperSqrtPrice) = getSqrtPriceRange(boards[_boardId], _index);

        if (perpStatus.borrowedLiquidity > 0) {
            uint256 feeAmount = ((block.timestamp - _lastTouchedTimestamp) *
                pricingModule.calculatePerpFee(
                    _sqrtPrice,
                    lowerSqrtPrice,
                    upperSqrtPrice,
                    volatility,
                    getPerpUR(_boardId, _index)
                )) / 1 days;
            perpStatus.cumulativeFee += feeAmount;
            perpStatus.cumulativeFeeForLP += (feeAmount * perpStatus.borrowedLiquidity) / getTotalLiquidityAmount(_boardId, _index);
        }

        if (perpStatus.instantBorrowedLiquidity > 0) {
            uint256 feeAmount = ((block.timestamp - _lastTouchedTimestamp) *
                pricingModule.calculateInstantRate(_sqrtPrice, getInstantUR(_boardId, _index))) / 1 days;
            perpStatus.instantCumulativeFee += feeAmount;
            perpStatus.cumulativeFeeForLP += (feeAmount * perpStatus.instantBorrowedLiquidity) / getTotalLiquidityAmount(_boardId, _index);
        }
    }

    function getMinCollateral(
        uint256 _vaultId,
        uint256 _boardId
    ) internal view returns(uint256 minCollateral){
        Vault memory vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            minCollateral += getMinCollateral(_boardId, vault.debtIndex[i], vault.debtLiquidity[i]);
        }
    }

    function getMinCollateral(
        uint256 _boardId,
        uint256 _index,
        uint128 _liquidity
    ) internal view returns(uint256){
        (uint256 lowerSqrtPrice, uint256 upperSqrtPrice) = getSqrtPriceRange(boards[_boardId], _index);

        return _liquidity * pricingModule.calculateMinCollateral(
            lowerSqrtPrice,
            upperSqrtPrice
        ) / 1e16;
    }

    function getPerpUR(uint256 _boardId, uint256 _index) internal view returns (uint256) {
        PerpStatus memory perpStatus = perpStatuses[_boardId][_index];

        uint128 liquidityAmount = getTotalLiquidityAmount(_boardId, _index);

        return (perpStatus.borrowedLiquidity * 1e10) / liquidityAmount;
    }

    function getInstantUR(uint256 _boardId, uint256 _index) internal view returns (uint256) {
        PerpStatus memory perpStatus = perpStatuses[_boardId][_index];

        uint128 liquidityAmount = getTotalLiquidityAmount(_boardId, _index);

        return (perpStatus.instantBorrowedLiquidity * 1e10) / liquidityAmount;
    }

    function getUR() internal view returns (uint256) {
        if(totalDeposited0 == 0) {
            return 1e10;
        }
        return (totalBorrowed0 * 1e10) / totalDeposited0;
    }

    function getPrice() external view returns (uint256, int24) {
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = uniswapPool.slot0();

        return (decodeSqrtPriceX96(sqrtPriceX96), tick);
    }

    function getSqrtPriceRange(Board memory board, uint256 _index) internal pure returns (uint160 lowerSqrtPrice, uint160 upperSqrtPrice) {
        lowerSqrtPrice = TickMath.getSqrtRatioAtTick(board.lowers[_index]);
        upperSqrtPrice = TickMath.getSqrtRatioAtTick(board.uppers[_index]);
    }

    function getObservations(uint256 _i) external view returns (uint32, bool) {
        (uint32 oldestAvailableAge, , , bool initialized) = uniswapPool.observations(_i);

        return (oldestAvailableAge, initialized);
    }

    function getTotalLiquidityAmount(uint256 _boardId, uint256 _index) internal view returns (uint128) {
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(boards[_boardId].tokenIds[_index]);

        return liquidity;
    }

    /**
     * returns collateral value scaled by token1's decimal
     */
    function getCollateralPositionValue(
        uint256 _vaultId,
        uint256 _boardId,
        uint256 _price
    ) internal view returns (uint256) {
        (uint256 amount0, uint256 amount1) = getCollateralPositionAmounts(_vaultId, _boardId);

        return amount0 * _price / 1e18 + amount1;
    }

    /**
     * returns debt value scaled by token1's decimal
     */
    function getDebtPositionValue(
        uint256 _vaultId,
        uint256 _boardId,
        uint256 _price
    ) internal view returns (uint256) {
        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, _boardId);

        return amount0 * _price / 1e18 + amount1;
    }

    function getCollateralPositionAmounts(uint256 _vaultId, uint256 _boardId)
        public
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Vault memory vault = vaults[_vaultId];
        Board memory board = boards[_boardId];

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.collateralIndex.length; i++) {
            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, vault.collateralIndex[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.collateralLiquidity[i]
            );

            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        totalAmount0 += vault.collateralAmount0;
        totalAmount1 += vault.collateralAmount1;
    }

    function getDebtPositionAmounts(uint256 _vaultId, uint256 _boardId)
        public
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        Vault memory vault = vaults[_vaultId];
        Board memory board = boards[_boardId];

        (uint160 sqrtPriceX96, , , , , , ) = uniswapPool.slot0();

        for (uint256 i = 0; i < vault.debtIndex.length; i++) {
            (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = getSqrtPriceRange(board, vault.debtIndex[i]);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                vault.debtLiquidity[i]
            );

            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        totalAmount0 += vault.debtAmount0;
        totalAmount1 += vault.debtAmount1;
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int24) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function callUniswapObserve(uint256 ago) private view returns (uint256, uint256) {
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
        uint256 scaler = 10**ERC20(token0).decimals();
        //if (uint160(token0) < uint160(token1)) {
        price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**96)) * scaler / uint256(2**96);
        //} else {
        //    price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**(96 * 2)) / (1e18 * scaler));
        //    if (price == 0) return 1e36;
        //    price = 1e36 / price;
        //}

        if (price > 1e36) price = 1e36;
        else if (price == 0) price = 1;
    }
}
