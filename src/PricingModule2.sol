//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

import "./libraries/Sqrt.sol";
import "forge-std/console2.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-core/contracts/libraries/Tick.sol";

contract PricingModule2 {
    uint256 constant ONE = 1e12;
    uint256 constant PI_E8 = 3.1415926535 * 1e12;

    struct TickSnapshot {
        uint256 lastFeeGrowthInside0X128;
        uint256 lastFeeGrowthInside1X128;
    }

    struct TickInfo {
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    mapping(bytes32 => TickSnapshot) snapshots;

    uint256 lastFeeGrowthGlobal0X128;
    uint256 lastFeeGrowthGlobal1X128;

    uint256 dailyFeeAmount;

    constructor() {}

    function updateDaylyFeeAmount(uint256 _dailyFeeAmount) external {
        dailyFeeAmount = _dailyFeeAmount;
    }

    /**
     * Calculates daily premium for range per liquidity
     */
    function calculatePerpFee(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) public view returns (uint256) {

        {
            uint256 feeGrowthGlobal0X128 = uniPool.feeGrowthGlobal0X128();
            uint256 feeGrowthGlobal1X128 = uniPool.feeGrowthGlobal1X128();

            (, int24 tickCurrent, , , , , ) = uniPool.slot0();

            (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
                getFeeGrowthOutside(uniPool, _lowerTick), getFeeGrowthOutside(uniPool, _upperTick), _lowerTick, _upperTick, tickCurrent, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
            
            bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

            return calculateRatio(
                snapshots[
                    key
                ],
                feeGrowthInside0X128,
                feeGrowthInside1X128,
                feeGrowthGlobal0X128,
                feeGrowthGlobal1X128
            );
        }
    }

    /**
     * Calculates daily interest rate for range per liquidity
     */
    function calculateInstantRate(uint256 _price, uint256 _utilizationRatio) external pure returns (uint256) {
        // TODO
        return 500;
    }

    function takeSnapshot(
        IUniswapV3Pool uniPool
    ) external {
        uint256 feeGrowthGlobal0X128 = uniPool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = uniPool.feeGrowthGlobal1X128();

        lastFeeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        lastFeeGrowthGlobal1X128 = feeGrowthGlobal1X128;
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
            getFeeGrowthOutside(uniPool, _lowerTick), getFeeGrowthOutside(uniPool, _upperTick), _lowerTick, _upperTick, tickCurrent, feeGrowthGlobal0X128, feeGrowthGlobal1X128);

        bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

        snapshots[key] = TickSnapshot(feeGrowthInside0X128, feeGrowthInside1X128);
    }

    function calculateRatio(
        TickSnapshot memory snapshot,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256) {
        uint256 a = 1e8 * (feeGrowthInside0X128 - snapshot.lastFeeGrowthInside0X128) / (feeGrowthGlobal0X128 - lastFeeGrowthGlobal0X128);
        uint256 b = 1e8 * (feeGrowthInside1X128 - snapshot.lastFeeGrowthInside1X128) / (feeGrowthGlobal1X128 - lastFeeGrowthGlobal1X128);

        return dailyFeeAmount * (a + b) / (2 * 1e8);
    }

    function getFeeGrowthOutside(
        IUniswapV3Pool uniPool,
        int24 _tickId
    ) internal view returns (TickInfo memory) {
        (, , uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128, , , , bool initialized) = uniPool.ticks(_tickId);

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
        console2.log(uint256(tickLower), uint256(tickUpper), uint256(tickCurrent));
        console2.log(lower.feeGrowthOutside0X128, lower.feeGrowthOutside1X128);
        console2.log(upper.feeGrowthOutside0X128, upper.feeGrowthOutside1X128);
        console2.log(feeGrowthGlobal0X128, feeGrowthGlobal1X128);

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
    ) external view returns (uint256 minCollateral) {
        // TODO
        return 500;
    }
}
