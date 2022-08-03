// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "../src/libraries/LPTMath.sol";

contract LPTMathTest is Test {
    function testDecodeSqrtPrice() public {
        assertEq(LPTMath.decodeSqrtPriceX96(false, TickMath.getSqrtRatioAtTick(-202560)), 1597242283);
        assertEq(LPTMath.decodeSqrtPriceX96(true, TickMath.getSqrtRatioAtTick(202560)), 1597242283);
    }
}