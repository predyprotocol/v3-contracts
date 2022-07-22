// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../src/PricingModule.sol";


contract PricingModuleTest is Test {
    PricingModule pricingModule;

    function setUp() public {
        pricingModule = new PricingModule();
    }

    function testCalculateInstantRate(uint256 _price, uint256 _utilizationRatio) public view returns(uint256) {
        return pricingModule.calculateInstantRate(_price, _utilizationRatio);
    }

    function testInterestRateIs500() public {
        uint256 interestRate = pricingModule.calculateInstantRate(0, 0);
        assertEq(interestRate, 500);
    }
}
