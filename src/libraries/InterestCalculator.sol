// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";

import "./DataType.sol";


library InterestCalculator {
    using SafeMath for uint256;

    uint256 internal constant ONE = 1e18;

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
        mapping(bytes32 => TickSnapshot) snapshots;
        uint256 dailyFeeAmount;
    }


    struct IRMParams {
        uint256 baseRate;
        uint256 kinkRate;
        uint256 slope1;
        uint256 slope2;
    }

    function applyDailyPremium(
        DPMParams storage _params,
        DataType.Context memory _context,
        DataType.PerpStatus storage _perpState
    ) internal {
        if (block.timestamp <= _perpState.lastTouchedTimestamp) {
            return;
        }

        if (_perpState.borrowedLiquidity > 0) {
            uint256 premium = ((block.timestamp - _perpState.lastTouchedTimestamp) *
                calculateDailyPremium(_params, IUniswapV3Pool(_context.uniswapPool), _perpState.lowerTick, _perpState.upperTick)) / 1 days;
            _perpState.premiumGrowthForBorrower = _perpState.premiumGrowthForBorrower.add(premium);
            _perpState.premiumGrowthForLender =
                _perpState.premiumGrowthForLender.add(PredyMath.mulDiv(premium, _perpState.borrowedLiquidity,
                getTotalLiquidityAmount(INonfungiblePositionManager(_context.positionManager), _perpState.tokenId)));
        }

        takeSnapshotForRange(_params, IUniswapV3Pool(_context.uniswapPool), _perpState.lowerTick, _perpState.upperTick);

        _perpState.lastTouchedTimestamp = block.timestamp;
    }

    function getTotalLiquidityAmount(INonfungiblePositionManager _positionManager, uint256 _tokenId) internal view returns (uint256) {
        (, , , , , , , uint128 liquidity, , , , ) = _positionManager.positions(_tokenId);

        return liquidity;
    }


    function applyInterest(
        DataType.Context storage _context
    ) internal pure {
    }


    function calculateDailyPremium(
        DPMParams storage _params,
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
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
                _params.dailyFeeAmount,
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

    function calculateInterestRate(uint256 _utilizationRatio) internal view returns (uint256) {
        return 0;
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