// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "../../src/satelite/OptionMarketLib.sol";

contract OptionMarketLibTest is Test {
    /**************************
     *     Test: getProfit    *
     **************************/

    function testGetProfitCall() public {
        assertEq(OptionMarketLib.getProfit(1200 * 1e6, 1000 * 1e6, 1e8, false), 200 * 1e6);
    }

    function testGetProfitPut() public {
        assertEq(OptionMarketLib.getProfit(800 * 1e6, 1000 * 1e6, 1e8, true), 200 * 1e6);
    }
}
