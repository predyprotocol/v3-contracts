// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import "./DataType.sol";
import "./BaseToken.sol";
import "./LPTMath.sol";
import "./LPTStateLib.sol";

library InterestCalculator {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using BaseToken for BaseToken.TokenState;

    uint256 internal constant ONE = 1e18;

    uint256 internal constant Q96 = 0x1000000000000000000000000;

    struct TickSnapshot {
        uint256 lastFeeGrowthInside0X128;
        uint256 lastFeeGrowthInside1X128;
        uint256 lastFeeGrowthGlobal0X128;
        uint256 lastFeeGrowthGlobal1X128;
    }

    struct TickInfo {
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    struct DPMParams {
        IRMParams premiumParams;
        IRMParams irmParams;
        mapping(bytes32 => TickSnapshot) snapshots;
    }

    struct IRMParams {
        uint256 baseRate;
        uint256 kinkRate;
        uint256 slope1;
        uint256 slope2;
    }

    function applyPremiumForVault(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        DataType.PositionUpdate[] memory _positionUpdates,
        DPMParams storage _dpmParams,
        uint160 _sqrtPrice
    ) external {
        // calculate fee for ranges thath the vault has.
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault memory subVault = _subVaults[_vault.subVaults[i]];

            for (uint256 j = 0; j < subVault.lpts.length; j++) {
                InterestCalculator.applyDailyPremium(
                    _dpmParams,
                    _context,
                    _ranges[subVault.lpts[j].rangeId],
                    _sqrtPrice
                );
            }
        }

        // calculate fee for ranges thath positionUpdates have.
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdates[i].lowerTick, _positionUpdates[i].upperTick);

            // if range is not initialized, skip calculation.
            if (_ranges[rangeId].tokenId == 0) {
                continue;
            }

            InterestCalculator.applyDailyPremium(_dpmParams, _context, _ranges[rangeId], _sqrtPrice);
        }
    }

    function applyDailyPremium(
        DPMParams storage _params,
        DataType.Context memory _context,
        DataType.PerpStatus storage _perpState,
        uint160 _sqrtPrice
    ) internal {
        if (block.timestamp <= _perpState.lastTouchedTimestamp) {
            return;
        }

        if (_perpState.borrowedLiquidity > 0) {
            uint256 premium = ((block.timestamp - _perpState.lastTouchedTimestamp) *
                calculateYearlyPremium(_params, _context, _perpState, _sqrtPrice)) / 365 days;

            _perpState.premiumGrowthForBorrower = _perpState.premiumGrowthForBorrower.add(premium);
            _perpState.premiumGrowthForLender = _perpState.premiumGrowthForLender.add(
                PredyMath.mulDiv(
                    premium,
                    _perpState.borrowedLiquidity,
                    LPTStateLib.getTotalLiquidityAmount(_context, _perpState)
                )
            );
        }

        takeSnapshotForRange(_params, IUniswapV3Pool(_context.uniswapPool), _perpState.lowerTick, _perpState.upperTick);

        _perpState.lastTouchedTimestamp = block.timestamp;
    }

    function calculateYearlyPremium(
        DPMParams storage _params,
        DataType.Context memory _context,
        DataType.PerpStatus storage _perpState,
        uint160 _sqrtPrice
    ) internal view returns (uint256) {
        if (_perpState.borrowedLiquidity > 0) {
            uint256 perpUr = LPTStateLib.getPerpUR(_context, _perpState);

            uint256 dailyPremium = calculateStableValueFromTotalPremiumValue(
                calculatePremium(
                    _params,
                    IUniswapV3Pool(_context.uniswapPool),
                    _perpState.lowerTick,
                    _perpState.upperTick,
                    perpUr
                ),
                LPTStateLib.getAvailableLiquidityAmount(_context, _perpState)
            );

            uint256 dailyInterest = calculateStableValueFromRatio(
                _context.isMarginZero,
                calculateInterestRate(_params.irmParams, perpUr),
                _sqrtPrice,
                _perpState.lowerTick,
                _perpState.upperTick
            );

            return dailyPremium + dailyInterest;
        }

        return 0;
    }

    function applyInterest(
        DataType.Context storage _context,
        IRMParams memory _irmParams,
        uint256 lastTouchedTimestamp
    ) external returns (uint256) {
        if (block.timestamp <= lastTouchedTimestamp) {
            return lastTouchedTimestamp;
        }

        // calculate interest for tokens
        uint256 interest0 = ((block.timestamp - lastTouchedTimestamp) *
            calculateInterestRate(_irmParams, BaseToken.getUtilizationRatio(_context.tokenState0))) / 365 days;

        uint256 interest1 = ((block.timestamp - lastTouchedTimestamp) *
            calculateInterestRate(_irmParams, BaseToken.getUtilizationRatio(_context.tokenState0))) / 365 days;

        _context.tokenState0.updateScaler(interest0);
        _context.tokenState1.updateScaler(interest1);

        return block.timestamp;
    }

    function calculateStableValueFromTotalPremiumValue(uint256 _premiumInUsd, uint256 _totalLiquidity)
        internal
        pure
        returns (uint256 value)
    {
        return (_premiumInUsd * 1e18) / _totalLiquidity;
    }

    function calculateStableValueFromRatio(
        bool _isMarginZero,
        uint256 _ratio,
        uint160 _sqrtPrice,
        int24 _lowerTick,
        int24 _upperTick
    ) internal pure returns (uint256 value) {
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtPrice,
            TickMath.getSqrtRatioAtTick(_lowerTick),
            TickMath.getSqrtRatioAtTick(_upperTick),
            1e18
        );

        uint256 price = LPTMath.decodeSqrtPriceX96(_isMarginZero, _sqrtPrice);

        if (_isMarginZero) {
            value = PredyMath.mulDiv(amount1, price, 1e18) + amount0;
        } else {
            value = PredyMath.mulDiv(amount0, price, 1e18) + amount1;
        }

        // value (usd/liquidity)
        value = (value * _ratio) / 1e18;
    }

    function calculatePremium(
        DPMParams storage _params,
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _utilizationRatio
    ) internal view returns (uint256) {
        uint256 feeGrowthGlobal0X128 = uniPool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = uniPool.feeGrowthGlobal1X128();

        (, int24 tickCurrent, , , , , ) = uniPool.slot0();

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
            getFeeGrowthOutside(uniPool, _lowerTick),
            getFeeGrowthOutside(uniPool, _upperTick),
            _lowerTick,
            _upperTick,
            tickCurrent,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );

        bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

        return
            calculateRatio(
                calculateInterestRate(_params.premiumParams, _utilizationRatio),
                _params.snapshots[key],
                feeGrowthInside0X128,
                feeGrowthInside1X128,
                feeGrowthGlobal0X128,
                feeGrowthGlobal1X128
            );
    }

    function calculateRatio(
        uint256 _dailyFeeAmount,
        TickSnapshot memory snapshot,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal pure returns (uint256) {
        uint256 a;
        uint256 b;

        if (feeGrowthGlobal0X128 > snapshot.lastFeeGrowthGlobal0X128) {
            a =
                (ONE * (feeGrowthInside0X128 - snapshot.lastFeeGrowthInside0X128)) /
                (feeGrowthGlobal0X128 - snapshot.lastFeeGrowthGlobal0X128);
        }

        if (feeGrowthGlobal1X128 > snapshot.lastFeeGrowthGlobal1X128) {
            b =
                (ONE * (feeGrowthInside1X128 - snapshot.lastFeeGrowthInside1X128)) /
                (feeGrowthGlobal1X128 - snapshot.lastFeeGrowthGlobal1X128);
        }

        return (_dailyFeeAmount * (a + b)) / (2 * ONE);
    }

    function calculateInterestRate(IRMParams memory _irmParams, uint256 _utilizationRatio)
        internal
        pure
        returns (uint256)
    {
        uint256 ir = _irmParams.baseRate;

        if (_utilizationRatio <= _irmParams.kinkRate) {
            ir += (_utilizationRatio * _irmParams.slope1) / ONE;
        } else {
            ir += (_irmParams.kinkRate * _irmParams.slope1) / ONE;
            ir += (_irmParams.slope2 * (_utilizationRatio - _irmParams.kinkRate)) / ONE;
        }

        return ir;
    }

    function takeSnapshotForRange(
        DPMParams storage _params,
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) internal {
        uint256 feeGrowthGlobal0X128 = uniPool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = uniPool.feeGrowthGlobal1X128();

        (, int24 tickCurrent, , , , , ) = uniPool.slot0();

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
            getFeeGrowthOutside(uniPool, _lowerTick),
            getFeeGrowthOutside(uniPool, _upperTick),
            _lowerTick,
            _upperTick,
            tickCurrent,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );

        bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

        _params.snapshots[key].lastFeeGrowthInside0X128 = feeGrowthInside0X128;
        _params.snapshots[key].lastFeeGrowthInside1X128 = feeGrowthInside1X128;
        _params.snapshots[key].lastFeeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        _params.snapshots[key].lastFeeGrowthGlobal1X128 = feeGrowthGlobal1X128;
    }

    function getFeeGrowthOutside(IUniswapV3Pool uniPool, int24 _tickId) internal view returns (TickInfo memory) {
        (, , uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128, , , , bool initialized) = uniPool.ticks(
            _tickId
        );

        require(initialized, "initialized");

        return TickInfo(feeGrowthOutside0X128, feeGrowthOutside1X128);
    }

    function getFeeGrowthInside(
        TickInfo memory lower,
        TickInfo memory upper,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal pure returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        // calculate fee growth below
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;

        if (tickCurrent >= tickLower) {
            // 1808790600867964665724044468235309
            feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
        }

        // calculate fee growth above
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            //  1808790600867964665724044468235309
            feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
}
