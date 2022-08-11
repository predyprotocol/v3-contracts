//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";

import "./interfaces/IController.sol";
import "./interfaces/IPricingModule.sol";
import "./interfaces/IProductVerifier.sol";
import {BaseToken} from "./libraries/BaseToken.sol";
import "./libraries/DataType.sol";
import "./libraries/VaultLib.sol";
import "./libraries/PredyMath.sol";
import "./libraries/PositionUpdator.sol";
import "./libraries/InterestCalculator.sol";
import "./Constants.sol";
import "./LPTMathModule.sol";


contract Controller is IController, Ownable, Constants {
    using BaseToken for BaseToken.TokenState;
    using SafeMath for uint256;
    using SafeMath for uint128;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using VaultLib for DataType.Vault;

    struct CloseParams {
        bool zeroToOne;
        uint256 amount;
        uint256 amountOutMinimum;
        uint256 penaltyAmount0;
        uint256 penaltyAmount1;
    }

    LPTMathModule private lptMathModule;

    uint256 public lastTouchedTimestamp;

    mapping(bytes32 => DataType.PerpStatus) private ranges;

    uint256 public vaultIdCount;

    mapping(uint256 => DataType.Vault) public vaults;

    DataType.Context public context;
    InterestCalculator.DPMParams private dpmParams;

    event VaultCreated(uint256 vaultId);
    event PositionClosed(
        uint256 vaultId,
        int256 _amount0,
        int256 _amount1,
        uint256 _penaltyAmount0,
        uint256 _penaltyAmount1
    );

    modifier onlyVaultOwner(uint256 _vaultId) {
        require(vaults[_vaultId].owner == msg.sender);
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
        context.feeTier = FEE_TIER;
        context.token0 = _token0;
        context.token1 = _token1;
        context.isMarginZero = _isMarginZero;
        context.positionManager = _positionManager;
        context.swapRouter = _swapRouter;

        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({token0: context.token0, token1: context.token1, fee: FEE_TIER});

        context.uniswapPool = PoolAddress.computeAddress(_factory, poolKey);

        vaultIdCount = 1;

        ERC20(context.token0).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token1).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token0).approve(address(_swapRouter), type(uint256).max);
        ERC20(context.token1).approve(address(_swapRouter), type(uint256).max);

        context.tokenState0.initialize();
        context.tokenState1.initialize();

        lastTouchedTimestamp = block.timestamp;
    }

    // User API

    /**
     * @notice Opens new position.
     */
    function openPosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _buffer0,
        uint256 _buffer1
    ) external override returns (uint256 vaultId) {
        applyPerpFee(_vaultId);

        DataType.Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId);

        TransferHelper.safeTransferFrom(context.token0, msg.sender, address(this), _buffer0);
        TransferHelper.safeTransferFrom(context.token1, msg.sender, address(this), _buffer1);

        // update position
        (int256 amount0, int256 amount1) = PositionUpdator.updatePosition(
            vault,
            context,
            ranges,
            _positionUpdates
        );


        require(!checkLiquidatable(vaultId), "P3");

        require(int256(_buffer0) >= amount0);
        require(int256(_buffer1) >= amount1);

        if (int256(_buffer0) > amount0) {
            TransferHelper.safeTransfer(context.token0, msg.sender, uint256(int256(_buffer0) - amount0));
        }
        if (int256(_buffer1) > amount1) {
            TransferHelper.safeTransfer(context.token1, msg.sender, uint256(int256(_buffer1) - amount1));
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
        DataType.Vault storage vault = vaults[_vaultId];

        require(vaults[_vaultId].isClosed);

        uint256 withdrawAmount0 = context.tokenState0.getCollateralValue(vault.balance0);
        uint256 withdrawAmount1 = context.tokenState1.getCollateralValue(vault.balance1);

        context.tokenState0.clearCollateral(vault.balance0);
        context.tokenState1.clearCollateral(vault.balance1);

        TransferHelper.safeTransfer(context.token0, msg.sender, withdrawAmount0);
        TransferHelper.safeTransfer(context.token1, msg.sender, withdrawAmount1);
    }

    /**
     * Liquidates if 75% of collateral value is less than debt value.
     */
    function liquidate(
        uint256 _vaultId,
        bool _zeroToOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) external {
        applyPerpFee(_vaultId);

        // check liquidation
        require(checkLiquidatable(_vaultId));

        (uint160 sqrtPrice, ) = lptMathModule.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), 1 minutes);

        // calculate reward
        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, sqrtPrice);
        CloseParams memory params = CloseParams(_zeroToOne, _amount, _amountOutMinimum, amount0 / 100, amount1 / 100);

        // close position
        _closePositionsInVault(_vaultId, params);

        sendReward(msg.sender, params.penaltyAmount0, params.penaltyAmount1);
    }

    function checkLiquidatable(uint256 _vaultId) internal view returns (bool) {
        (uint160 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), 1 minutes);

        // calculate value using TWAP price
        int256 requiredCollateral = PositionCalculator.calculateRequiredCollateral(getPosition(_vaultId), sqrtPrice, context.isMarginZero);

        return requiredCollateral > 0;
    }

    function forceClose(bytes[] memory _data) external onlyOwner {
        for (uint256 i = 0; i < _data.length; i++) {
            (uint256 vaultId, bool _zeroToOne, uint256 _amount, uint256 _amountOutMinimum) = abi.decode(
                _data[i],
                (uint256, bool, uint256, uint256)
            );

            applyPerpFee(vaultId);

            _closePositionsInVault(vaultId, CloseParams(_zeroToOne, _amount, _amountOutMinimum, 0, 0));
        }
    }

    // Product API

    /*
    function depositTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1,
        bool _withEnteringMarket
    ) external override onlyProductVerifier {
        context.tokenState0.addCollateral(vaults[_vaultId].balance0, _amount0, _withEnteringMarket);
        context.tokenState1.addCollateral(vaults[_vaultId].balance1, _amount1, _withEnteringMarket);
    }

    function borrowTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) external override onlyProductVerifier {
        context.tokenState0.addDebt(vaults[_vaultId].balance0, _amount0);
        context.tokenState1.addDebt(vaults[_vaultId].balance1, _amount1);
    }

    function getTokenAmountsToBorrowLPT(
        bytes32 _rangeId,
        uint128 _liquidity,
        uint160 _sqrtPrice
    ) external view override returns (uint256, uint256) {
        return lptMathModule.getAmountsForLiquidity(
            _sqrtPrice, 
            ranges[_rangeId].lowerTick,
            ranges[_rangeId].upperTick,
            _liquidity
        );
    }

    function depositLPT(
        uint256 _vaultId,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity,
        uint256 amount0Max,
        uint256 amount1Max
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
                .IncreaseLiquidityParams(ranges[rangeId].tokenId, amount0, amount1, amount0Max, amount1Max, block.timestamp);

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
                amount0Max,
                amount1Max,
                address(this),
                block.timestamp
            );

            (ranges[rangeId].tokenId, liquidity, requiredAmount0, requiredAmount1) = positionManager.mint(params);
            ranges[rangeId].lowerTick = _lower;
            ranges[rangeId].upperTick = _upper;
            ranges[rangeId].lastTouchedTimestamp = block.timestamp;
        }

        DataType.Vault storage vault = vaults[_vaultId];

        vault.depositLPT(ranges, rangeId, liquidity);
    }

    function borrowLPT(
        uint256 _vaultId,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override onlyProductVerifier returns (uint256, uint256) {
        bytes32 rangeId = getRangeKey(_lower, _upper);

        (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(ranges[rangeId].tokenId, _liquidity, rangeId, amount0Min, amount1Min);

        ranges[rangeId].borrowedLiquidity += _liquidity;

        DataType.Vault storage vault = vaults[_vaultId];

        vault.borrowLPT(ranges, rangeId, _liquidity);

        return (amount0, amount1);
    }
    */

    // Getter Functions

    function getRange(bytes32 _rangeId) external view returns (DataType.PerpStatus memory) {
        return ranges[_rangeId];
    }

    function getVaultStatus(uint256 _vaultId)
        external
        returns (
            uint256,
            uint256
        )
    {
        uint160 sqrtPriceX96 = getSqrtPrice();

        applyPerpFee(_vaultId);

        (uint256 collateralValue, uint256 debtValue) = getPositionValue(_vaultId, sqrtPriceX96);

        return (collateralValue, debtValue);
    }

    // Private Functions

    function createOrGetVault(uint256 _vaultId) internal returns (uint256 vaultId, DataType.Vault storage) {
        if (_vaultId == 0) {
            vaultId = vaultIdCount;
            vaultIdCount++;
            vaults[vaultId].owner = msg.sender;
            
            emit VaultCreated(vaultId);
        } else {
            vaultId = _vaultId;
            require(vaults[vaultId].owner == msg.sender, "P4");
        }

        return (vaultId, vaults[vaultId]);
    }

    function _closePositionsInVault(uint256 _vaultId, CloseParams memory _params) internal {
        DataType.Vault storage vault = vaults[_vaultId];

        int256 tmpVaultAmount0 = int256(context.tokenState0.getCollateralValue(vault.balance0));
        int256 tmpVaultAmount1 = int256(context.tokenState1.getCollateralValue(vault.balance1));

        if (_params.amount > 0) {
            if (_params.zeroToOne) {
                uint256 requiredA1 = swapExactInput(context.token0, context.token1, _params.amount, _params.amountOutMinimum);
                tmpVaultAmount0 = tmpVaultAmount0.sub(_params.amount.toInt256());
                tmpVaultAmount1 = tmpVaultAmount1.add(requiredA1.toInt256());
            } else {
                uint256 requiredA0 = swapExactInput(context.token1, context.token0, _params.amount, _params.amountOutMinimum);
                tmpVaultAmount0 = tmpVaultAmount0.add(requiredA0.toInt256());
                tmpVaultAmount1 = tmpVaultAmount1.sub(_params.amount.toInt256());
            }
        }

        (int256 totalWithdrawAmount0, int256 totalWithdrawAmount1) = withdrawLPT(_vaultId);

        (int256 totalRepayAmount0, int256 totalRepayAmount1) = repayLPT(_vaultId);

        tmpVaultAmount0 = tmpVaultAmount0.add(totalWithdrawAmount0.sub(totalRepayAmount0).sub(_params.penaltyAmount0.toInt256()));
        tmpVaultAmount1 = tmpVaultAmount1.add(totalWithdrawAmount1.sub(totalRepayAmount1).sub(_params.penaltyAmount1.toInt256()));

        context.tokenState0.addCollateral(vault.balance0, tmpVaultAmount0.toUint256(), false);
        context.tokenState1.addCollateral(vault.balance1, tmpVaultAmount1.toUint256(), false);
        
        vaults[_vaultId].isClosed = true;

        context.tokenState0.clearDebt(vault.balance0);
        context.tokenState1.clearDebt(vault.balance1);
        context.tokenState0.clearCollateral(vault.balance0);
        context.tokenState1.clearCollateral(vault.balance1);

        emit PositionClosed(_vaultId, tmpVaultAmount0, tmpVaultAmount1, _params.penaltyAmount0, _params.penaltyAmount1);
    }

    function withdrawLPT(uint256 _vaultId) internal returns (int256 totalAmount0, int256 totalAmount1) {
        DataType.Vault storage vault = vaults[_vaultId];

        for (uint256 i = 0; i < vault.lpts.length; i++) {
            if (!vault.lpts[i].isCollateral) {
                continue;
            }
            bytes32 rangeId = vault.lpts[i].rangeId;
            (uint256 amount0, uint256 amount1) = decreaseLiquidityFromUni(ranges[rangeId].tokenId, vault.lpts[i].liquidityAmount, rangeId, 0, 0);
            totalAmount0 += int256(amount0);
            totalAmount1 += int256(amount1);
        }

        {
            (uint256 fee0, uint256 fee1) = vault.getEarnedTradeFee(ranges);
            totalAmount0 += int256(fee0);
            totalAmount1 += int256(fee1);
        }

        if(context.isMarginZero) {
            totalAmount0 = totalAmount0.add(vault.getEarnedDailyPremium(ranges).toInt256());
        }else {
            totalAmount1 = totalAmount1.add(vault.getEarnedDailyPremium(ranges).toInt256());
        }

        for (uint256 i = 0; i < vault.lpts.length; i++) {
            if (!vault.lpts[i].isCollateral) {
                continue;
            }
            bytes32 rangeId = vault.lpts[i].rangeId;

            vault.lpts[i].fee0Last = ranges[rangeId].fee0Growth;
            vault.lpts[i].fee1Last = ranges[rangeId].fee1Growth;

            vault.lpts[i].liquidityAmount = 0;
        }
    }

    function repayLPT(uint256 _vaultId) internal returns (int256 totalAmount0, int256 totalAmount1) {
        DataType.Vault storage vault = vaults[_vaultId];

        totalAmount0 = int256(context.tokenState0.getDebtValue(vault.balance0));
        totalAmount1 = int256(context.tokenState1.getDebtValue(vault.balance1));

        uint160 sqrtPriceX96 = getSqrtPrice();

        for (uint256 i = 0; i < vault.lpts.length; i++) {
            if (vault.lpts[i].isCollateral) {
                continue;
            }
            bytes32 rangeId = vault.lpts[i].rangeId;

            (uint256 amount0, uint256 amount1) = lptMathModule.getAmountsForLiquidity(
                sqrtPriceX96,
                ranges[rangeId].lowerTick,
                ranges[rangeId].upperTick,
                vault.lpts[i].liquidityAmount
            );

            ranges[rangeId].borrowedLiquidity = ranges[rangeId].borrowedLiquidity.sub(vault.lpts[i].liquidityAmount).toUint128();

            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams(ranges[rangeId].tokenId, amount0, amount1, 0, 0, block.timestamp);

            (, uint256 actualAmount0, uint256 actualAmount1) = INonfungiblePositionManager(context.positionManager).increaseLiquidity(params);

            totalAmount0 += int256(actualAmount0);
            totalAmount1 += int256(actualAmount1);

            vault.lpts[i].liquidityAmount = 0;
        }

        if(context.isMarginZero) {
            totalAmount0 = totalAmount0.sub(vault.getPaidDailyPremium(ranges).toInt256());
        }else {
            totalAmount1 = totalAmount1.sub(vault.getPaidDailyPremium(ranges).toInt256());
        }

    }

    function decreaseLiquidityFromUni(
        uint256 _tokenId,
        uint128 _liquidity,
        bytes32 _rangeId,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint256 liquidityAmount = getTotalLiquidityAmount(_rangeId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams(_tokenId, _liquidity, _amount0Min, _amount1Min, block.timestamp);

        (amount0, amount1) = INonfungiblePositionManager(context.positionManager).decreaseLiquidity(params);

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

        (uint256 a0, uint256 a1) = INonfungiblePositionManager(context.positionManager).collect(params);

        // Update cumulative trade fee
        ranges[_rangeId].fee0Growth += ((a0 - _amount0) * FixedPoint128.Q128) / _preLiquidity;
        ranges[_rangeId].fee1Growth += ((a1 - _amount1) * FixedPoint128.Q128) / _preLiquidity;
    }

    function sendReward(address _liquidator, uint256 _reward) internal {
        TransferHelper.safeTransfer(context.isMarginZero ? context.token0 : context.token1, _liquidator, _reward);
    }

    function sendReward(
        address _liquidator,
        uint256 _reward0,
        uint256 _reward1
    ) internal {
        TransferHelper.safeTransfer(context.token0, _liquidator, _reward0);
        TransferHelper.safeTransfer(context.token1, _liquidator, _reward1);
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

        return ISwapRouter(context.swapRouter).exactInputSingle(params);
    }

    function swapExactOutput(
        bool _zeroForOne,
        uint256 _amountOut,
        uint256 _amountInMaximum
    ) internal returns (uint256) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _zeroForOne ? context.token0 : context.token1,
            tokenOut: _zeroForOne ? context.token1 : context.token0,
            fee: FEE_TIER,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: _amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        return ISwapRouter(context.swapRouter).exactOutputSingle(params);
    }

    function applyPerpFee(uint256 _vaultId) internal {
        DataType.Vault memory vault = vaults[_vaultId];

        // calculate fee for perps
        for (uint256 i = 0; i < vault.lpts.length; i++) {
            InterestCalculator.applyDailyPremium(dpmParams, context, ranges[vault.lpts[i].rangeId]);
        }

        // updateInterest();
        lastTouchedTimestamp = InterestCalculator.applyInterest(context, lastTouchedTimestamp);
    }

    function getPerpUR(bytes32 _rangeId) internal view returns (uint256) {
        return PredyMath.mulDiv(ranges[_rangeId].borrowedLiquidity, ONE, getTotalLiquidityAmount(_rangeId));
    }

    function getUR() internal view returns (uint256) {
        if (context.tokenState0.totalDeposited == 0) {
            return ONE;
        }
        return PredyMath.mulDiv(context.tokenState0.totalBorrowed, ONE, context.tokenState0.totalDeposited);
    }

    /**
     * Gets current price of underlying token by margin token.
     */
    function getPrice() external view returns (uint256) {
        return lptMathModule.decodeSqrtPriceX96(context.isMarginZero, getSqrtPrice());
    }

    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(context.uniswapPool).slot0();
    }

    /**
     * Gets Time Weighted Average Price of underlying token by margin token.
     */
    function getTWAP() external view returns (uint256) {
        (uint256 sqrtPrice, ) = lptMathModule.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), 1 minutes);

        return lptMathModule.decodeSqrtPriceX96(context.isMarginZero, sqrtPrice);

    }

    function getTotalLiquidityAmount(bytes32 _rangeId) internal view returns (uint256) {
        (, , , , , , , uint128 liquidity, , , , ) = INonfungiblePositionManager(context.positionManager).positions(ranges[_rangeId].tokenId);

        return liquidity;
    }

    /**
     * returns collateral and debt value scaled by margin token's decimal
     */
    function getPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256, uint256) {
        return (getCollateralPositionValue(_vaultId, _sqrtPrice), getDebtPositionValue(_vaultId, _sqrtPrice));
    }

    function getCollateralPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256) {
        DataType.Vault memory vault = vaults[_vaultId];

        (uint256 collateralAmount0, uint256 collateralAmount1) =  getCollateralPositionAmounts(_vaultId, _sqrtPrice);
        uint256 earnedPremium = vault.getEarnedDailyPremium(ranges);        

        uint256 price = lptMathModule.decodeSqrtPriceX96(context.isMarginZero, _sqrtPrice);

        if (context.isMarginZero) {
            return (PredyMath.mulDiv(collateralAmount1, price, ONE) + collateralAmount0 + earnedPremium);
        } else {
            return (PredyMath.mulDiv(collateralAmount0, price, ONE) + collateralAmount1 + earnedPremium);
        }
    }

    function getDebtPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256) {
        DataType.Vault memory vault = vaults[_vaultId];

        (uint256 debtAmount0, uint256 debtAmount1) = getDebtPositionAmounts(_vaultId, _sqrtPrice);
        uint256 paidPremium = vault.getPaidDailyPremium(ranges);        

        uint256 price = lptMathModule.decodeSqrtPriceX96(context.isMarginZero, _sqrtPrice);

        if (context.isMarginZero) {
            return (PredyMath.mulDiv(debtAmount1, price, ONE) + debtAmount0 - paidPremium);
        } else {
            return (PredyMath.mulDiv(debtAmount0, price, ONE) + debtAmount1 - paidPremium);
        }
    }


    function getCollateralPositionAmounts(uint256 _vaultId, uint160 _sqrtPrice)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getCollateralPositionAmounts(ranges, context.tokenState0, context.tokenState1, _sqrtPrice);
    }

    function getDebtPositionAmounts(uint256 _vaultId, uint160 _sqrtPrice)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getDebtPositionAmounts(ranges, context.tokenState0, context.tokenState1, _sqrtPrice);
    }

    function getPosition(uint256 _vaultId) public view returns (PositionCalculator.Position memory position) {
        DataType.Vault memory vault = vaults[_vaultId];

        PositionCalculator.LPT[] memory lpts = new PositionCalculator.LPT[](vault.lpts.length);

        for (uint256 i = 0; i < vault.lpts.length; i++) {
            bytes32 rangeId = vault.lpts[i].rangeId;
            DataType.PerpStatus memory range = ranges[rangeId];
            lpts[i] = PositionCalculator.LPT(vault.lpts[i].isCollateral, vault.lpts[i].liquidityAmount, range.lowerTick, range.upperTick);
        }

        position = PositionCalculator.Position(
            context.tokenState0.getCollateralValue(vault.balance0),
            context.tokenState1.getCollateralValue(vault.balance1),
            context.tokenState0.getDebtValue(vault.balance0),
            context.tokenState1.getDebtValue(vault.balance1),
            lpts
        );
    }

    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }
}
