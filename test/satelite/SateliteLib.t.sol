// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "../../src/satelite/SateliteLib.sol";

contract SateliteLibTest is Test {
    /**************************
     *     Test: getProfit    *
     **************************/

    function testGetProfitCall() public {
        assertEq(SateliteLib.getProfit(1200 * 1e6, 1000 * 1e6, 1e8, false), 200 * 1e6);
    }

    function testGetProfitPut() public {
        assertEq(SateliteLib.getProfit(800 * 1e6, 1000 * 1e6, 1e8, true), 200 * 1e6);
    }

    /**************************
     *  Test: getTradePrice   *
     **************************/

    function testGetTradePrice0() public {
        assertEq(
            SateliteLib.getTradePrice(true, TickMath.getSqrtRatioAtTick(202000), TickMath.getSqrtRatioAtTick(203000)),
            1606854063
        );
    }

    function testGetTradePrice1() public {
        assertEq(
            SateliteLib.getTradePrice(
                false,
                TickMath.getSqrtRatioAtTick(-203000),
                TickMath.getSqrtRatioAtTick(-202000)
            ),
            1606854063
        );
    }

    /**************************
     * Test: updateEntryPrice *
     **************************/

    function testUpdateEntryPriceOpen() public {
        (int256 entryPrice, int256 profitValue) = SateliteLib.updateEntryPrice(1000, 1e18, 2000, 1e18);

        assertEq(entryPrice, 1500);
        assertEq(profitValue, 0);
    }

    function testUpdateEntryPriceClose() public {
        (int256 entryPrice, int256 profitValue) = SateliteLib.updateEntryPrice(1000, 1e18, 2000, -1e17);

        assertEq(entryPrice, 1000);
        assertEq(profitValue, 100);
    }

    function testUpdateEntryPriceCloseAll() public {
        (int256 entryPrice, int256 profitValue) = SateliteLib.updateEntryPrice(1000, 1e18, 2000, -1e18);

        assertEq(entryPrice, 0);
        assertEq(profitValue, 1000);
    }
}
