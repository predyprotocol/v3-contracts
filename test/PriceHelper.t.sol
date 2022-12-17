// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/DataType.sol";
import "../src/libraries/PriceHelper.sol";
import "./mocks/MockPriceFeed.sol";

contract PriceHelperTest is Test {
    MockPriceFeed private priceFeed;

    DataType.Context private context;

    function setUp() public {
        priceFeed = new MockPriceFeed();

        BaseToken.TokenState memory tokenState = BaseToken.TokenState(0, 0, 0, 0, 1e18, 1e18, 0, 0);

        context = DataType.Context(
            address(0),
            address(0),
            0,
            address(0),
            address(0),
            address(priceFeed),
            false,
            0,
            tokenState,
            tokenState,
            0,
            0
        );

        priceFeed.setLatestRoundData(0, 160000000000);
    }

    function testGetSqrtIndexPriceMarginZero() public {
        context.isMarginZero = true;

        assertEq(uint256(PriceHelper.getSqrtIndexPrice(context)), 1980704062856608439838598758400000);
    }

    function testGetSqrtIndexPriceMarginOne() public {
        assertEq(uint256(PriceHelper.getSqrtIndexPrice(context)), 3169126500570573503741758);
    }

    function testDecodeSqrtPriceX96IsMarginZero() public {
        assertEq(PriceHelper.decodeSqrtPriceX96(true, 1980704062856608439838598758400000), 160000000000);
    }

    function testDecodeSqrtPriceX96IsMarginOne() public {
        assertEq(PriceHelper.decodeSqrtPriceX96(false, 3169126500570573503741758), 159999999999);
    }

    function testEncodeSqrtPriceX96IsMarginZero() public {
        assertEq(
            PriceHelper.encodeSqrtPriceX96(true, 1600 * 1e6 * PriceHelper.PRICE_SCALER),
            1980704062856608439838598758400000
        );
    }

    function testEncodeSqrtPriceX96IsMarginOne() public {
        assertEq(
            PriceHelper.encodeSqrtPriceX96(false, 1600 * 1e6 * PriceHelper.PRICE_SCALER),
            3169126500570573503741758
        );
    }

    function testFuzzIsMarginZero(uint256 _price) public {
        uint256 price = bound(_price, PriceHelper.PRICE_SCALER, 1e18);

        uint256 sqrtPrice = PriceHelper.encodeSqrtPriceX96(true, price);
        uint256 price2 = PriceHelper.decodeSqrtPriceX96(true, sqrtPrice);

        assertGe(price, price2 - 10);
        assertLe(price, price2 + 10);
    }

    function testFuzzIsMarginOne(uint256 _price) public {
        uint256 price = bound(_price, PriceHelper.PRICE_SCALER, 1e18);

        uint256 sqrtPrice = PriceHelper.encodeSqrtPriceX96(false, price);
        uint256 price2 = PriceHelper.decodeSqrtPriceX96(false, sqrtPrice);

        assertGe(price, price2 - 10);
        assertLe(price, price2 + 10);
    }
}
