// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PriceHelper.sol";

contract PriceHelperTest is Test {
    function testDecodeSqrtPriceX96IsMarginZero() public {
        assertEq(PriceHelper.decodeSqrtPriceX96(true, TickMath.getSqrtRatioAtTick(-74320)), 1688555020577491795738);
    }

    function testDecodeSqrtPriceX96IsMarginOne() public {
        assertEq(PriceHelper.decodeSqrtPriceX96(false, TickMath.getSqrtRatioAtTick(74320)), 1688555020577489349584);
    }

    function testFuzzIsMarginZero(uint256 _price) public {
        uint256 price = bound(_price, 1, 1e16);

        uint256 sqrtPrice = PriceHelper.encodeSqrtPriceX96(true, price);
        uint256 price2 = PriceHelper.decodeSqrtPriceX96(true, sqrtPrice);

        assertEq(price, price2);
    }

    function testFuzzIsMarginOne(uint256 _price) public {
        uint256 price = bound(_price, 10, 1e16);

        uint256 sqrtPrice = PriceHelper.encodeSqrtPriceX96(false, price);
        uint256 price2 = PriceHelper.decodeSqrtPriceX96(false, sqrtPrice);

        assertEq(price, price2 + 1);
    }
}
