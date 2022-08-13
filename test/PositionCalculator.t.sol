// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PositionCalculator.sol";
import "../src/libraries/LPTMath.sol";

contract PositionCalculatorTest is Test {
    function testCalculateRequiredCollateralOfLongToken0(uint160 _sqrtPrice) public {
        vm.assume(2802745766959374473415602 < _sqrtPrice);

        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        DataType.Position memory position = DataType.Position(1e18, 0, 0, 1000 * 1e6, lpts);

        assertLt(PositionCalculator.calculateRequiredCollateral(position, _sqrtPrice, false), 0);
    }

    function testCalculateRequiredCollateralOfBorrowLPT0(uint160 _sqrtPrice) public {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202550),
            1e18,
            0
        );

        lpts[0] = DataType.LPT(false, liquidity, -202560, -202550);

        DataType.Position memory position = DataType.Position(1e18, 50 * 1e6, 0, 0, lpts);

        assertLt(PositionCalculator.calculateRequiredCollateral(position, _sqrtPrice, false), 0);
    }

    function testCalculateRequiredCollateralOfBorrowLPT1(uint160 _sqrtPrice) public {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202550),
            1e18,
            0
        );

        lpts[0] = DataType.LPT(false, liquidity, -202560, -202550);

        DataType.Position memory position = DataType.Position(0, 1700 * 1e6, 0, 0, lpts);

        assertLt(PositionCalculator.calculateRequiredCollateral(position, _sqrtPrice, false), 0);
    }
}
