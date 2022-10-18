// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/LPTMath.sol";

contract LPTMathTest is Test {
    function testDecodeSqrtPriceX96IsMarginZero() public {
        assertEq(LPTMath.decodeSqrtPriceX96(true, TickMath.getSqrtRatioAtTick(-74320)), 1688555020577491795738);
    }

    function testDecodeSqrtPriceX96IsMarginOne() public {
        assertEq(LPTMath.decodeSqrtPriceX96(false, TickMath.getSqrtRatioAtTick(74320)), 1688555020577489349584);
    }
}
