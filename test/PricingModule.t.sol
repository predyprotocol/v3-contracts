// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../src/PricingModule.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import 'v3-core/contracts/libraries/FullMath.sol';


contract PricingModuleTest is Test {
    PricingModule pricingModule;

    function setUp() public {
        pricingModule = new PricingModule();

        console.log(11, decodeSqrtPriceX96(false, 0, TickMath.getSqrtRatioAtTick(202562)));
        console.log(11, decodeSqrtPriceX96(true, 0, TickMath.getSqrtRatioAtTick(-202562)));
    }

    function decodeSqrtPriceX96(bool _isTokenAToken0, uint256 _decimalsOfToken0, uint256 sqrtPriceX96) internal pure returns (uint256 price) {
        uint256 scaler = 10**_decimalsOfToken0;

        if (_isTokenAToken0) {
            price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**96)) * scaler / uint256(2**96);
        } else {
            price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**(96 * 2)) / (1e18 * scaler));
            if (price == 0) return 1e36;
            price = 1e36 / price;
        }

        if (price > 1e36) price = 1e36;
        else if (price == 0) price = 1;
    }

    /*
    function testPrices(
    ) public {
        uint256 sqrtPrice1 = TickMath.getSqrtRatioAtTick(202562);
        uint256 sqrtPrice2 = TickMath.getSqrtRatioAtTick(-202562);

        assertEq(decodeSqrtPriceX96(false, 12, sqrtPrice1), decodeSqrtPriceX96(true, 12, sqrtPrice2));
    }
    */

    function testCalculatePerpFee(
        uint256 _volatility
    ) public {
        vm.assume(_volatility >= 5 * 1e11);
        vm.assume(_volatility <= 2 * 1e12);

        uint160 lowerSqrtPrice = TickMath.getSqrtRatioAtTick(202560);
        uint160 upperSqrtPrice = TickMath.getSqrtRatioAtTick(202570);
        uint256 price = decodeSqrtPriceX96(false, 0, TickMath.getSqrtRatioAtTick(202565));
        
        uint256 a = pricingModule.calculatePerpFee(false, price * 1e6, lowerSqrtPrice, upperSqrtPrice, _volatility);

        // assertLt(a, 10 * 1e12);
        assertEq(a, 500);
    }

    function testCalculateMinCollateral() public {
        uint160 lowerSqrtPrice = TickMath.getSqrtRatioAtTick(202760);
        uint160 upperSqrtPrice = TickMath.getSqrtRatioAtTick(202770);
        
        uint256 a = pricingModule.calculateMinCollateral(false, 2002335799292703061291668062173864, 2003337167445953701273470060329132);
        // uint256 a = pricingModule.calculateMinCollateral(false, lowerSqrtPrice, upperSqrtPrice);

        //assertGt(a, 0);
        assertEq(a, 500);
    }

    function testVolIs0(
        uint256 _volatility
    ) public {
        vm.expectRevert(bytes("PM0"));

        pricingModule.calculatePerpFee(false, 0, 0, 0, 0);
    }

    function testCalculateInstantRate(uint256 _price, uint256 _utilizationRatio) public view returns(uint256) {
        return pricingModule.calculateInstantRate(_price, _utilizationRatio);
    }

    function testInterestRateIs500() public {
        uint256 interestRate = pricingModule.calculateInstantRate(0, 0);
        assertEq(interestRate, 500);
    }
}
