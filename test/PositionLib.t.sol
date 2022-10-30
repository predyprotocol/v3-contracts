// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PositionLib.sol";

contract PositionLibTest is Test {
    uint128 private liquidity = 1e12;
    int24 private lower = 202500;
    int24 private upper = 202700;
    int24 private lower2 = 202700;
    int24 private upper2 = 203000;

    function getPosition1() internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, lower, upper);
        position = DataType.Position(0, 0, 0, 0, 0, lpts);
    }

    function getPosition2() internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, lower, upper);
        position = DataType.Position(0, 1e18, 0, 0, 0, lpts);
    }

    function getPosition3() internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, lower, upper);
        position = DataType.Position(0, 1e18, 0, 0, 1e10, lpts);
    }

    function getPosition4() internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](2);
        lpts[0] = DataType.LPT(true, liquidity, lower, upper);
        lpts[1] = DataType.LPT(true, liquidity, lower2, upper2);
        position = DataType.Position(0, 0, 0, 0, 0, lpts);
    }

    function testGetRequiredTokenAmounts() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        DataType.Position memory srcPosition = DataType.Position(0, 1e18, 0, 0, 1e6, lpts);
        DataType.Position memory destPosition = DataType.Position(0, 1e18, 0, 0, 1e6, lpts);

        (int256 amount0, int256 amount1) = PositionLib.getRequiredTokenAmounts(
            srcPosition,
            destPosition,
            TickMath.getSqrtRatioAtTick(int24(0))
        );

        assertEq(amount0, amount1);
    }

    function testCalculateLengthOfPositionUpdates1() public {
        DataType.Position memory position = getPosition1();

        assertEq(PositionLib.calculateLengthOfPositionUpdates(position), 1);
    }

    function testCalculateLengthOfPositionUpdates2() public {
        DataType.Position memory position = getPosition2();

        assertEq(PositionLib.calculateLengthOfPositionUpdates(position), 2);
    }

    function testCalculateLengthOfPositionUpdates3() public {
        DataType.Position memory position = getPosition3();

        assertEq(PositionLib.calculateLengthOfPositionUpdates(position), 3);
    }

    function testCalculatePositionUpdatesToOpen1() public {
        DataType.Position memory position = getPosition1();

        (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex) = PositionLib
            .calculatePositionUpdatesToOpen(position);

        assertEq(positionUpdates.length, 2);

        // empty for swap
        assertEq(swapIndex, 0);

        // Deposit LPT
        assertEq(uint256(positionUpdates[1].liquidity), uint256(liquidity));
    }

    function testCalculatePositionUpdatesToOpen2() public {
        DataType.Position memory position = getPosition2();

        (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex) = PositionLib
            .calculatePositionUpdatesToOpen(position);

        assertEq(positionUpdates.length, 3);

        // Deposit Token
        assertEq(positionUpdates[0].param0, 1e18);

        // empty for swap
        assertEq(swapIndex, 1);

        // Deposit LPT
        assertEq(uint256(positionUpdates[2].liquidity), uint256(liquidity));
    }

    function testCalculatePositionUpdatesToOpen4() public {
        DataType.Position memory position = getPosition4();

        (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex) = PositionLib
            .calculatePositionUpdatesToOpen(position);

        assertEq(positionUpdates.length, 3);

        // empty for swap
        assertEq(swapIndex, 0);

        // Deposit LPT
        assertEq(uint256(positionUpdates[1].liquidity), uint256(liquidity));

        // Deposit LPT
        assertEq(uint256(positionUpdates[2].liquidity), uint256(liquidity));
    }

    function testCalculatePositionUpdatesToClose1() public {
        DataType.Position[] memory positions = new DataType.Position[](1);
        positions[0] = getPosition1();

        (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex) = PositionLib
            .calculatePositionUpdatesToClose(positions, 1e4);

        assertEq(positionUpdates.length, 2);

        // Withdraw LPT
        assertEq(uint256(positionUpdates[0].positionUpdateType), uint256(DataType.PositionUpdateType.WITHDRAW_LPT));
        assertEq(uint256(positionUpdates[0].liquidity), uint256(liquidity));

        // empty for swap
        assertEq(swapIndex, 1);
    }

    function testCalculatePositionUpdatesToClose2() public {
        DataType.Position[] memory positions = new DataType.Position[](3);
        positions[0] = getPosition3();
        positions[1] = getPosition3();

        (DataType.PositionUpdate[] memory positionUpdates, ) = PositionLib.calculatePositionUpdatesToClose(
            positions,
            1e4
        );

        assertEq(uint256(positionUpdates[0].positionUpdateType), uint256(DataType.PositionUpdateType.WITHDRAW_LPT));
        assertEq(uint256(positionUpdates[1].positionUpdateType), uint256(DataType.PositionUpdateType.WITHDRAW_LPT));
        assertEq(uint256(positionUpdates[2].positionUpdateType), uint256(DataType.PositionUpdateType.NOOP));
        assertEq(uint256(positionUpdates[3].positionUpdateType), uint256(DataType.PositionUpdateType.WITHDRAW_TOKEN));
        assertEq(uint256(positionUpdates[4].positionUpdateType), uint256(DataType.PositionUpdateType.WITHDRAW_TOKEN));
        assertEq(uint256(positionUpdates[5].positionUpdateType), uint256(DataType.PositionUpdateType.REPAY_TOKEN));
        assertEq(uint256(positionUpdates[6].positionUpdateType), uint256(DataType.PositionUpdateType.REPAY_TOKEN));
        assertEq(positionUpdates.length, 7);
    }
}
