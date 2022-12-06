// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./Setup.t.sol";
import "../../src/Controller.sol";
import "../../src/mocks/MockERC20.sol";

contract ControllerPauseTest is TestController {
    DataType.TradeOption internal tradeOption;
    DataType.OpenPositionOption internal openPositionOption;

    function setUp() public override {
        TestController.setUp();

        tradeOption = createTradeOption();
        openPositionOption = createOpenPositionParams();
    }

    // Helper Functions
    function createEmptyPositionUpdate() internal returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](0);
    }

    function createEmptyPosition() internal returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        position = DataType.Position(0, 0, 1e18, 0, 0, lpts);
    }

    function createTradeOption() internal returns (DataType.TradeOption memory tradeOption) {
        bool isMarginZero = getIsMarginZero();

        return
            DataType.TradeOption(
                false,
                false,
                false,
                isMarginZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            );
    }

    function createOpenPositionParams() internal returns (DataType.OpenPositionOption memory) {
        return DataType.OpenPositionOption(0, 0, 100, block.timestamp);
    }

    /*************************
     *      Test: pause      *
     *************************/

    function testCannotPauseBecauseCallerIsNotOperator() public {
        vm.stopPrank();

        vm.prank(OTHER_ACCOUNT);
        vm.expectRevert(bytes("P3"));
        controller.pause();
    }

    function testPause() public {
        controller.pause();

        assertTrue(controller.isSystemPaused());

        DataType.PositionUpdate[] memory positionUpdates = createEmptyPositionUpdate();

        vm.expectRevert(bytes("P5"));
        controller.updatePosition(0, positionUpdates, tradeOption, openPositionOption);

        DataType.Position memory position = createEmptyPosition();

        vm.expectRevert(bytes("P5"));
        controller.openPosition(0, position, tradeOption, openPositionOption);
    }

    /*************************
     *     Test: unpause     *
     *************************/

    function testCannotUnPause() public {
        vm.expectRevert(bytes("P6"));
        controller.unPause();
    }

    function testCannotUnPauseBecauseCallerIsNotOperator() public {
        controller.pause();

        vm.stopPrank();

        vm.prank(OTHER_ACCOUNT);
        vm.expectRevert(bytes("P3"));
        controller.unPause();
    }

    function testUnPause() public {
        controller.pause();

        vm.expectRevert(bytes("P5"));
        controller.pause();

        controller.unPause();
    }
}
