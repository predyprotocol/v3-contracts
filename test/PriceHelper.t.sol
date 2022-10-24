// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
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

    function testShow() public {
        uint256 sqrtPrice1 = PriceHelper.encodeSqrtPriceX96(false, 1 * 1e2);
        uint256 sqrtPrice2 = PriceHelper.encodeSqrtPriceX96(false, 10000000 * 1e6);
        uint256 sqrtPrice3 = PriceHelper.encodeSqrtPriceX96(true, 1 * 1e2);
        uint256 sqrtPrice4 = PriceHelper.encodeSqrtPriceX96(true, 10000000 * 1e6);

        console.log(sqrtPrice1);
        console.log(sqrtPrice2);
        console.log(sqrtPrice3);
        console.log(sqrtPrice4);
    }
}
