// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PositionCalculator.sol";

contract PositionCalculatorTest is Test {
    function testGetRequiredTokenAmounts() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        DataType.Position memory srcPosition = DataType.Position(1e18, 0, 0, 1e6, lpts);
        DataType.Position memory destPosition = DataType.Position(1e18, 0, 0, 1e6, lpts);

        (int256 amount0, int256 amount1) = PositionCalculator.getRequiredTokenAmounts(srcPosition, destPosition, TickMath.getSqrtRatioAtTick(int24(0)));

        assertEq(amount0, amount1);
    }


    function testCalculateRequiredCollateral(int256 tick) public {
        vm.assume(tick >= -887220 && tick <= 887220);

        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        DataType.Position memory position = DataType.Position(1e18, 0, 0, 1e6, lpts);

        assertLt(PositionCalculator.calculateRequiredCollateral(position, TickMath.getSqrtRatioAtTick(int24(tick)), false), 0);
    }

    function testCalculateRequiredCollateral2(int256 tick) public {
        vm.assume(tick >= -887220 && tick <= 887220);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        (uint128 liquidity) = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202550),
            1e18,
            0
        );

        lpts[0] = DataType.LPT(
            false,
            liquidity,
            -202560,
            -202550
        );

        DataType.Position memory position = DataType.Position(1e18, 0, 0, 0, lpts);

        assertLt(PositionCalculator.calculateRequiredCollateral(position, TickMath.getSqrtRatioAtTick(int24(tick)), false), 0);
    }

    function testCalculateRequiredCollateral3() public {
        int24 tick = -202560;

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        (uint128 liquidity) = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202550),
            1e18,
            0
        );

        lpts[0] = DataType.LPT(
            false,
            liquidity,
            -202560,
            -202550
        );

        DataType.Position memory position = DataType.Position(1e18, 1e6, 0, 0, lpts);

        assertLt(PositionCalculator.calculateRequiredCollateral(position, TickMath.getSqrtRatioAtTick(tick), false), 0);
    }
}
