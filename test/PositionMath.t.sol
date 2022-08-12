// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PositionMath.sol";

contract PositionMathTest is Test {
    uint128 private liquidity = 1e12;
    int24 private lower = 202500;
    int24 private upper = 202700;

    function getPosition1() internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, lower, upper);
        position = DataType.Position(0, 0, 0, 0, lpts);
    }

    function getPosition2() internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, lower, upper);
        position = DataType.Position(1e18, 0, 0, 0, lpts);
    }

    function getPosition3() internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, lower, upper);
        position = DataType.Position(1e18, 0, 0, 1e10, lpts);
    }

    function testCalculateLengthOfPositionUpdates1() public {
        DataType.Position memory position = getPosition1();

        assertEq(PositionMath.calculateLengthOfPositionUpdates(position), 1);
    }

    function testCalculateLengthOfPositionUpdates2() public {
        DataType.Position memory position = getPosition2();

        assertEq(PositionMath.calculateLengthOfPositionUpdates(position), 2);
    }

    function testCalculateLengthOfPositionUpdates3() public {
        DataType.Position memory position = getPosition3();

        assertEq(PositionMath.calculateLengthOfPositionUpdates(position), 3);
    }

    function testCalculatePositionUpdatesToOpen1() public {
        DataType.Position memory position = getPosition1();

        (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex) = PositionMath
            .calculatePositionUpdatesToOpen(position);

        assertEq(positionUpdates.length, 2);

        assertEq(swapIndex, 1);
    }

    function testCalculatePositionUpdatesToOpen2() public {
        DataType.Position memory position = getPosition2();

        (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex) = PositionMath
            .calculatePositionUpdatesToOpen(position);

        assertEq(positionUpdates.length, 3);

        assertEq(swapIndex, 2);
    }
}
