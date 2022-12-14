// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "./Setup.t.sol";
import "../../src/libraries/PositionUpdater.sol";
import "../utils/PositionUpdaterHelper.sol";

contract PositionUpdaterUpdateMarginTest is TestPositionUpdater {
    function setUp() public override {
        TestPositionUpdater.setUp();
    }

    /**************************
     *  Test: updateMargin    *
     **************************/

    function getTestDataOfUpdateMargin(
        int256 requiredAmount0,
        int256 requiredAmount1,
        uint8 marginMode0,
        uint8 marginMode1,
        int256 deltaMarginAmount0,
        int256 deltaMarginAmount1
    ) internal view returns (DataType.TokenAmounts memory, DataType.TradeOption memory) {
        return (
            DataType.TokenAmounts(requiredAmount0, requiredAmount1),
            DataType.TradeOption(
                false,
                false,
                false,
                context.isMarginZero,
                marginMode0,
                marginMode1,
                deltaMarginAmount0,
                deltaMarginAmount1,
                EMPTY_METADATA
            )
        );
    }

    // margin is added or removed if margin mode is MARGIN_USE
    function testUpdateMargin(uint256 _requiredAmount0, uint256 _requiredAmount1) public {
        int256 requiredAmount0 = -int256(bound(_requiredAmount0, 0, 1e10));
        int256 requiredAmount1 = -int256(bound(_requiredAmount1, 0, 1e10));

        (
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TradeOption memory tradeOption
        ) = getTestDataOfUpdateMargin(
                requiredAmount0,
                requiredAmount1,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                0,
                0
            );

        (requiredAmounts.amount0, requiredAmounts.amount1) = PositionUpdater.updateMargin(
            vault1,
            tradeOption,
            requiredAmounts
        );

        assertEq(vault1.marginAmount0, -requiredAmount0);
        assertEq(vault1.marginAmount1, -requiredAmount1);
        assertEq(requiredAmounts.amount0, 0);
        assertEq(requiredAmounts.amount1, 0);
    }

    // deposit margin
    function testUpdateMarginUseDeposit(uint256 _requiredAmount0, uint256 _requiredAmount1) public {
        int256 requiredAmount0 = -int256(bound(_requiredAmount0, 0, 1e10));
        int256 requiredAmount1 = -int256(bound(_requiredAmount1, 0, 1e10));

        (
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TradeOption memory tradeOption
        ) = getTestDataOfUpdateMargin(
                requiredAmount0,
                requiredAmount1,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                100,
                100
            );

        (requiredAmounts.amount0, requiredAmounts.amount1) = PositionUpdater.updateMargin(
            vault1,
            tradeOption,
            requiredAmounts
        );

        assertEq(vault1.marginAmount0, -requiredAmount0 + 100);
        assertEq(vault1.marginAmount1, -requiredAmount1 + 100);
        assertEq(requiredAmounts.amount0, 100);
        assertEq(requiredAmounts.amount1, 100);
    }

    // withdraw margin
    function testUpdateMarginUseWithdraw(uint256 _requiredAmount0, uint256 _requiredAmount1) public {
        int256 requiredAmount0 = -int256(bound(_requiredAmount0, 100, 1e10));
        int256 requiredAmount1 = -int256(bound(_requiredAmount1, 100, 1e10));

        (
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TradeOption memory tradeOption
        ) = getTestDataOfUpdateMargin(
                requiredAmount0,
                requiredAmount1,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                -100,
                -100
            );

        (requiredAmounts.amount0, requiredAmounts.amount1) = PositionUpdater.updateMargin(
            vault1,
            tradeOption,
            requiredAmounts
        );

        assertEq(vault1.marginAmount0, -requiredAmount0 - 100);
        assertEq(vault1.marginAmount1, -requiredAmount1 - 100);
        assertEq(requiredAmounts.amount0, -100);
        assertEq(requiredAmounts.amount1, -100);
    }

    // withdraw full margin
    function testUpdateMarginUseFullWithdraw(uint256 _requiredAmount0, uint256 _requiredAmount1) public {
        int256 requiredAmount0 = -int256(bound(_requiredAmount0, 0, 1e6));
        int256 requiredAmount1 = -int256(bound(_requiredAmount1, 0, 1e6));

        (
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TradeOption memory tradeOption
        ) = getTestDataOfUpdateMargin(
                requiredAmount0,
                requiredAmount1,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                -1e6,
                -1e6
            );

        (requiredAmounts.amount0, requiredAmounts.amount1) = PositionUpdater.updateMargin(
            vault1,
            tradeOption,
            requiredAmounts
        );

        assertEq(vault1.marginAmount0, 0);
        assertEq(vault1.marginAmount1, 0);
        assertEq(requiredAmounts.amount0, requiredAmount0);
        assertEq(requiredAmounts.amount1, requiredAmount1);
    }

    // margin can be negative if the call is liquidationCall
    function testUpdateMarginUseWithdrawLiquidationCall(uint256 _requiredAmount0, uint256 _requiredAmount1) public {
        int256 requiredAmount0 = -int256(bound(_requiredAmount0, 0, 1e10));
        int256 requiredAmount1 = -int256(bound(_requiredAmount1, 0, 1e10));

        DataType.TokenAmounts memory requiredAmounts = DataType.TokenAmounts(requiredAmount0, requiredAmount1);

        (requiredAmounts.amount0, requiredAmounts.amount1) = PositionUpdater.updateMargin(
            vault1,
            DataType.TradeOption(
                true,
                false,
                false,
                context.isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                -100,
                -100,
                EMPTY_METADATA
            ),
            requiredAmounts
        );

        assertEq(vault1.marginAmount0, -requiredAmount0 - 100);
        assertEq(vault1.marginAmount1, -requiredAmount1 - 100);
        assertEq(requiredAmounts.amount0, -100);
        assertEq(requiredAmounts.amount1, -100);
    }

    // margin amount is never updated if margin mode is MARGIN_STAY
    function testUpdateMarginStay(uint256 _requiredAmount0, uint256 _requiredAmount1) public {
        int256 requiredAmount0 = -int256(bound(_requiredAmount0, 0, 1e10));
        int256 requiredAmount1 = -int256(bound(_requiredAmount1, 0, 1e10));

        (
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TradeOption memory tradeOption
        ) = getTestDataOfUpdateMargin(
                requiredAmount0,
                requiredAmount1,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0
            );

        (requiredAmounts.amount0, requiredAmounts.amount1) = PositionUpdater.updateMargin(
            vault1,
            tradeOption,
            requiredAmounts
        );

        assertEq(vault1.marginAmount0, 0);
        assertEq(vault1.marginAmount1, 0);
        assertEq(requiredAmounts.amount0, requiredAmount0);
        assertEq(requiredAmounts.amount1, requiredAmount1);
    }
}
