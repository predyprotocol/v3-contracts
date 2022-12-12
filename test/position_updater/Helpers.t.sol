// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "./Setup.t.sol";
import "../../src/libraries/PositionUpdater.sol";
import "../utils/PositionUpdaterHelper.sol";

contract PositionUpdaterHelpersTest is TestPositionUpdater {
    function setUp() public override {
        TestPositionUpdater.setUp();
    }

    /**************************
     * Test: recomputeAmounts *
     **************************/

    function testRecomputeAmountsWithEmpty() public {
        DataType.SubVaultTokenAmounts[] memory amounts = new DataType.SubVaultTokenAmounts[](1);
        amounts[0] = DataType.SubVaultTokenAmounts(0, 0, 0);
        DataType.TokenAmounts memory swapAmount = DataType.TokenAmounts(0, 0);

        (
            DataType.TokenAmounts memory totalAmount,
            DataType.SubVaultTokenAmounts[] memory resultAmounts
        ) = PositionUpdater.recomputeAmounts(context, amounts, swapAmount, true);

        assertEq(totalAmount.amount0, 0);
        assertEq(totalAmount.amount1, 0);
        assertEq(resultAmounts[0].amount0, 0);
        assertEq(resultAmounts[0].amount1, 0);
    }

    // deposit 100 USDC and borrow 2 ETH
    // swap 2 ETH for 300 USDC
    // get 200 USDC
    function testRecomputeAmounts1() public {
        DataType.SubVaultTokenAmounts[] memory amounts = new DataType.SubVaultTokenAmounts[](1);
        amounts[0] = DataType.SubVaultTokenAmounts(0, -2, 100);

        (
            DataType.TokenAmounts memory totalAmount,
            DataType.SubVaultTokenAmounts[] memory resultAmounts
        ) = PositionUpdater.recomputeAmounts(context, amounts, DataType.TokenAmounts(2, -300), false);

        assertEq(totalAmount.amount0, 0);
        assertEq(totalAmount.amount1, -200);
        assertEq(resultAmounts[0].amount0, 0);
        assertEq(resultAmounts[0].amount1, -200);
    }

    // swap 4 ETH for 300 USDC
    // deposit 100 USDC and borrow 2 ETH
    // swap 600 USDC for 2 ETH
    // required 400 USDC
    function testRecomputeAmounts2() public {
        DataType.SubVaultTokenAmounts[] memory amounts = new DataType.SubVaultTokenAmounts[](1);
        amounts[0] = DataType.SubVaultTokenAmounts(0, -2, 100);

        (
            DataType.TokenAmounts memory totalAmount,
            DataType.SubVaultTokenAmounts[] memory resultAmounts
        ) = PositionUpdater.recomputeAmounts(context, amounts, DataType.TokenAmounts(2, 300), false);

        assertEq(totalAmount.amount0, 0);
        assertEq(totalAmount.amount1, 400);
        assertEq(resultAmounts[0].amount0, 0);
        assertEq(resultAmounts[0].amount1, 400);
    }

    // swap 8 ETH for 100 USDC
    // deposit 100 USDC and borrow 2 ETH
    // deposit 100 USDC and borrow 5 ETH
    // swap 800 USDC for 1 ETH
    // required 900 USDC
    function testRecomputeAmounts3() public {
        DataType.SubVaultTokenAmounts[] memory amounts = new DataType.SubVaultTokenAmounts[](2);
        amounts[0] = DataType.SubVaultTokenAmounts(0, -2, 100);
        amounts[1] = DataType.SubVaultTokenAmounts(0, -5, 100);

        (
            DataType.TokenAmounts memory totalAmount,
            DataType.SubVaultTokenAmounts[] memory resultAmounts
        ) = PositionUpdater.recomputeAmounts(context, amounts, DataType.TokenAmounts(7, 700), false);

        assertEq(totalAmount.amount0, 0);
        assertEq(totalAmount.amount1, 900);
        assertEq(resultAmounts[0].amount0, 0);
        assertEq(resultAmounts[0].amount1, 300);
        assertEq(resultAmounts[1].amount0, 0);
        assertEq(resultAmounts[1].amount1, 600);
    }

    // borrow 100 USDC and deposit 1 ETH
    // borrow 200 USDC and deposit 1 ETH
    // swap 400 USDC for 2 ETH
    // required 100 USDC
    function testRecomputeAmounts4() public {
        DataType.SubVaultTokenAmounts[] memory amounts = new DataType.SubVaultTokenAmounts[](2);
        amounts[0] = DataType.SubVaultTokenAmounts(0, 1, -100);
        amounts[1] = DataType.SubVaultTokenAmounts(0, 1, -200);

        (
            DataType.TokenAmounts memory totalAmount,
            DataType.SubVaultTokenAmounts[] memory resultAmounts
        ) = PositionUpdater.recomputeAmounts(context, amounts, DataType.TokenAmounts(-2, 400), false);

        assertEq(totalAmount.amount0, 0);
        assertEq(totalAmount.amount1, 100);
        assertEq(resultAmounts[0].amount0, 0);
        assertEq(resultAmounts[0].amount1, 100);
        assertEq(resultAmounts[1].amount0, 0);
        assertEq(resultAmounts[1].amount1, 0);
    }

    /**************************
     *   Test: roundMargin    *
     **************************/

    function testRoundMargin() public {
        assertEq(PositionUpdater.roundMargin(0, 1e2), 0);

        assertEq(PositionUpdater.roundMargin(1, 1e2), 100);
        assertEq(PositionUpdater.roundMargin(99, 1e2), 100);
        assertEq(PositionUpdater.roundMargin(100, 1e2), 100);
        assertEq(PositionUpdater.roundMargin(101, 1e2), 200);

        assertEq(PositionUpdater.roundMargin(-1, 1e2), 0);
        assertEq(PositionUpdater.roundMargin(-99, 1e2), 0);
        assertEq(PositionUpdater.roundMargin(-100, 1e2), -100);
        assertEq(PositionUpdater.roundMargin(-101, 1e2), -100);
    }
}
