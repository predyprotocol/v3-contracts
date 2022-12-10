// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "./Setup.t.sol";
import "../../src/libraries/PositionUpdater.sol";
import "../utils/PositionUpdaterHelper.sol";

contract PositionUpdaterSwapAnywayTest is TestPositionUpdater {
    function setUp() public override {
        TestPositionUpdater.setUp();
    }

    /**************************
     *   Test: swapAnyway     *
     **************************/

    function testSwapAnywayETHRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 < 0);
        vm.assume(requiredAmount1 > 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero,
            500
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_OUT));
        assertEq(positionUpdate.zeroForOne, true);
        assertEq(positionUpdate.param0, uint256(requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }

    function testSwapAnywayUSDCRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 > 0);
        vm.assume(requiredAmount1 < 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero,
            500
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_IN));
        assertEq(positionUpdate.zeroForOne, false);
        assertEq(positionUpdate.param0, uint256(-requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }

    function testSwapAnywayNoRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 < 0);
        vm.assume(requiredAmount1 < 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero,
            500
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_IN));
        assertEq(positionUpdate.zeroForOne, false);
        assertEq(positionUpdate.param0, uint256(-requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }

    function testSwapAnywayBothRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 > 0);
        vm.assume(requiredAmount1 > 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero,
            500
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_OUT));
        assertEq(positionUpdate.zeroForOne, true);
        assertEq(positionUpdate.param0, uint256(requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }
}
