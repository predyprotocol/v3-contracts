//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

import "./libraries/Sqrt.sol";
import "forge-std/console2.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/Tick.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "./Constants.sol";

contract PricingModule is Constants, Ownable {
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

    mapping(bytes32 => TickSnapshot) snapshots;

    uint256 dailyFeeAmount;
    uint256 minCollateralPerLiquidity;

    uint256 baseRate;
    uint256 kinkRate;
    uint256 slope1;
    uint256 slope2;

    constructor() {}

    function updateDaylyFeeAmount(uint256 _dailyFeeAmount) external onlyOwner {
        dailyFeeAmount = _dailyFeeAmount;
    }

    function updateMinCollateralPerLiquidity(uint256 _minCollateralPerLiquidity) external onlyOwner {
        minCollateralPerLiquidity = _minCollateralPerLiquidity;
    }

    function updateIRMParams(
        uint256 _base,
        uint256 _kink,
        uint256 _slope1,
        uint256 _slope2
    ) external onlyOwner {
        baseRate = _base;
        kinkRate = _kink;
        slope1 = _slope1;
        slope2 = _slope2;
    }

    /**
     * Calculates daily premium for range per liquidity
     */
    function calculateDailyPremium(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) public view returns (uint256) {
        {
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
                    snapshots[key],
                    feeGrowthInside0X128,
                    feeGrowthInside1X128,
                    feeGrowthGlobal0X128,
                    feeGrowthGlobal1X128
                );
        }
    }

    function takeSnapshotForRange(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) external {
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

        snapshots[key] = TickSnapshot(
            feeGrowthInside0X128,
            feeGrowthInside1X128,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );
    }

    function calculateRatio(
        TickSnapshot memory snapshot,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256) {
        uint256 a = (ONE * (feeGrowthInside0X128 - snapshot.lastFeeGrowthInside0X128)) /
            (feeGrowthGlobal0X128 - snapshot.lastFeeGrowthGlobal0X128);
        uint256 b = (ONE * (feeGrowthInside1X128 - snapshot.lastFeeGrowthInside1X128)) /
            (feeGrowthGlobal1X128 - snapshot.lastFeeGrowthGlobal1X128);

        return (dailyFeeAmount * (a + b)) / (2 * ONE);
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
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
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

    /**
     * Calculates min. collateral per liquidity
     */
    function calculateMinCollateral(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) external view returns (uint256) {
        // TODO
        return minCollateralPerLiquidity;
    }

    /**
     * Calculates daily interest rate for range per liquidity
     * scaled by 1e18;
     */
    function calculateInterestRate(uint256 _utilizationRatio) external view returns (uint256) {
        uint256 ir = baseRate;

        if (_utilizationRatio <= kinkRate) {
            ir += (_utilizationRatio * slope1) / ONE;
        } else {
            ir += (kinkRate * slope1) / ONE;
            ir += (slope2 * (_utilizationRatio - kinkRate)) / ONE;
        }

        return ir;
    }
}
