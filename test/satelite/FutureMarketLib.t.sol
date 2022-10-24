// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "../../src/satelite/FutureMarketLib.sol";

contract FutureMarketLibTest is Test {
    /**************************
     * Test: updateEntryPrice *
     **************************/

    function testUpdateEntryPriceOpen() public {
        (int256 entryPrice, int256 profitValue) = FutureMarketLib.updateEntryPrice(1000, 1e18, 2000, 1e18);

        assertEq(entryPrice, 1500);
        assertEq(profitValue, 0);
    }

    function testUpdateEntryPriceClose() public {
        (int256 entryPrice, int256 profitValue) = FutureMarketLib.updateEntryPrice(1000, 1e18, 2000, -1e17);

        assertEq(entryPrice, 1000);
        assertEq(profitValue, 100);
    }

    function testUpdateEntryPriceCloseAll() public {
        (int256 entryPrice, int256 profitValue) = FutureMarketLib.updateEntryPrice(1000, 1e18, 2000, -1e18);

        assertEq(entryPrice, 0);
        assertEq(profitValue, 1000);
    }

    /********************************
     * Test: calculateMinCollateral *
     ********************************/

    function testCalculateMinCollateral1(uint256 _positionAmount) public {
        int256 positionAmount = int256(bound(_positionAmount, 0, 100 * 1e18)) - 50 * 1e18;

        uint256 minCollateral = FutureMarketLib.calculateMinCollateral(
            FutureMarketLib.FutureVault(1, address(0), positionAmount, 0, 0, 0),
            1000 * 1e6
        );

        assertLe(minCollateral, (100 * 1e6 * PredyMath.abs(positionAmount)) / 1e18);
    }

    function testCalculateMinCollateral2(uint256 _positionAmount) public {
        uint256 positionAmount = bound(_positionAmount, 60 * 1e18, 1000 * 1e18);

        uint256 minCollateral = FutureMarketLib.calculateMinCollateral(
            FutureMarketLib.FutureVault(1, address(0), int256(positionAmount), 0, 0, 0),
            1000 * 1e6
        );

        assertGe(minCollateral, (100 * 1e6 * positionAmount) / 1e18);
    }
}
