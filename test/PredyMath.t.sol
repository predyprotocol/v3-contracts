// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import "forge-std/Test.sol";
import "../src/libraries/PredyMath.sol";

contract PredyMathTest is Test {
    function testMulDiv(
        uint256 a,
        uint256 b,
        uint256 c
    ) public {
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 0, type(uint128).max);
        c = bound(c, 1, type(uint256).max);
        uint256 r = PredyMath.mulDiv(a, b, c);

        assertEq(r, (a * b) / c);
    }

    function testCannotMulDivByDivByZero(uint256 a, uint256 b) public {
        vm.expectRevert();
        PredyMath.mulDiv(a, b, 0);
    }

    function testSubRewardReturnReward() public {
        (int256 a, uint256 b) = PredyMath.subReward(100, 10);

        assertEq(a, 90);
        assertEq(b, 10);
    }

    function testSubRewardReturnCorrectedReward() public {
        (int256 a, uint256 b) = PredyMath.subReward(100, 110);

        assertEq(a, 0);
        assertEq(b, 100);
    }

    function testSubRewardMarginIsZero() public {
        (int256 a, uint256 b) = PredyMath.subReward(0, 10);

        assertEq(a, 0);
        assertEq(b, 0);
    }

    function testSubRewardMarginIsNegative(uint256 _rewardAmount) public {
        uint256 rewardAmount = bound(_rewardAmount, 0, 1e20);

        (int256 a, uint256 b) = PredyMath.subReward(-10, rewardAmount);

        assertEq(a, -10);
        assertEq(b, 0);
    }
}
