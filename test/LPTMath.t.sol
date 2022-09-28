// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/LPTMath.sol";

contract LPTMathTest is Test {
    // int24 MIN
    // int24 MAX
    int24 private lower = -220000;
    int24 private upper = -210000;

    // confirm constraint below
    //
    // L = getLiquidityForAmount(getAmountForLiquidity(l))
    // L <= l
    //
    // L = getLiquidityForAmount(getAmountForLiquidityRoundUp(l))
    // L >= l
    //

    function testGetAmountForLiquidity(uint160 _sqrtPrice, uint128 _l) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, 1e18, 1e40));
        vm.assume(0 < _l && _l < type(uint128).max / 2);

        (uint256 a0, uint256 a1) = LPTMath.getAmountsForLiquidity(sqrtPrice, lower, upper, _l);
        uint256 _l2 = LPTMath.getLiquidityForAmounts(sqrtPrice, lower, upper, a0, a1);

        assertLe(_l2, _l);
    }

    function testGetAmountForLiquidityRoundUp(uint160 _sqrtPrice, uint128 _l) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, 1e18, 1e40));
        vm.assume(0 < _l && _l < type(uint128).max / 2);

        (uint256 a0, uint256 a1) = LPTMath.getAmountsForLiquidityRoundUp(sqrtPrice, lower, upper, _l);
        uint256 _l2 = LPTMath.getLiquidityForAmounts(sqrtPrice, lower, upper, a0, a1);

        assertGe(_l2, _l);
    }

    function testGetAmount0ForLiquidity(
        uint160 _sqrtPrice,
        uint160 _sqrtPrice2,
        uint128 _l
    ) public {
        // 340248342086729790484326174814286782778, 340248342086729790484326174814286782778, 3217
        vm.assume(1e18 <= _sqrtPrice);
        vm.assume(_sqrtPrice < _sqrtPrice2 && _sqrtPrice2 < 1e40);
        vm.assume(0 < _l && _l < type(uint128).max / 2);

        uint256 a0 = LiquidityAmounts.getAmount0ForLiquidity(_sqrtPrice, _sqrtPrice2, _l);
        uint256 ar0 = LPTMath.getAmount0ForLiquidityRoundUp(_sqrtPrice, _sqrtPrice2, _l);
        uint256 _l1 = LiquidityAmounts.getLiquidityForAmount0(_sqrtPrice, _sqrtPrice2, a0);
        uint256 _l2 = LiquidityAmounts.getLiquidityForAmount0(_sqrtPrice, _sqrtPrice2, ar0);

        assertGe(_l, _l1);
        assertGe(_l2, _l);
    }

    function testGetAmount1ForLiquidity(
        uint160 _sqrtPrice,
        uint160 _sqrtPrice2,
        uint128 _l
    ) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, 1e18, 1e40 - 1));
        uint160 sqrtPrice2 = uint160(bound(_sqrtPrice2, sqrtPrice + 1, 1e40));
        vm.assume(0 < _l && _l < type(uint128).max / 2);

        uint256 a0 = LiquidityAmounts.getAmount1ForLiquidity(sqrtPrice, sqrtPrice2, _l);
        uint256 ar0 = LPTMath.getAmount1ForLiquidityRoundUp(sqrtPrice, sqrtPrice2, _l);
        uint256 _l1 = LiquidityAmounts.getLiquidityForAmount1(sqrtPrice, sqrtPrice2, a0);
        uint256 _l2 = LiquidityAmounts.getLiquidityForAmount1(sqrtPrice, sqrtPrice2, ar0);

        assertGe(_l, _l1);
        assertGe(_l2, _l);
    }

    function testDecodeSqrtPriceX96IsMarginZero() public {
        assertEq(LPTMath.decodeSqrtPriceX96(true, TickMath.getSqrtRatioAtTick(-74320)), 1688555020577491795738);
    }

    function testDecodeSqrtPriceX96IsMarginOne() public {
        assertEq(LPTMath.decodeSqrtPriceX96(false, TickMath.getSqrtRatioAtTick(74320)), 1688555020577489349584);
    }
}
