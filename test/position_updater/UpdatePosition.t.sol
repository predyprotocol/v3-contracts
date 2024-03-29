// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import "./Setup.t.sol";
import "../../src/libraries/PositionUpdater.sol";
import "../utils/PositionUpdaterHelper.sol";

contract PositionUpdaterUpdatePositionTest is TestPositionUpdater {
    function setUp() public override {
        TestPositionUpdater.setUp();
    }

    /**************************
     *  Test: updatePosition  *
     **************************/

    function testUpdatePosition() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);
        PositionUpdater.updatePosition(vault1, subVaults, context, ranges, positionUpdates, tradeOption);
    }

    function testUpdatePositionDepositToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            0,
            false,
            0,
            0,
            0,
            1e6,
            1e18
        );

        PositionUpdater.updatePosition(vault1, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getAssetValue(context.tokenState0, subVaults[vault1.subVaults[0]].balance0), 1e6);
        assertEq(BaseToken.getAssetValue(context.tokenState1, subVaults[vault1.subVaults[0]].balance1), 1e18);
    }

    function testUpdatePositionDepositTokenWithCompound() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            0,
            true,
            0,
            0,
            0,
            1e6,
            1e18
        );

        PositionUpdater.updatePosition(vault1, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getAssetValue(context.tokenState0, subVaults[vault1.subVaults[0]].balance0), 1e6);
        assertEq(BaseToken.getAssetValue(context.tokenState1, subVaults[vault1.subVaults[0]].balance1), 1e18);
    }

    function testUpdatePositionWithdrawToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            vault2.subVaults[0],
            false,
            0,
            0,
            0,
            2 * 1e6,
            2 * 1e18
        );

        PositionUpdater.updatePosition(vault2, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(vault2.subVaults.length, 0);
    }

    function testUpdatePositionWithdrawTokenWithCompound() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            vault4.subVaults[0],
            false,
            0,
            0,
            0,
            2 * 1e6,
            2 * 1e18
        );

        PositionUpdater.updatePosition(vault4, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(vault4.subVaults.length, 0);
    }

    function testUpdatePositionBorrowToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_TOKEN,
            0,
            false,
            0,
            0,
            0,
            0,
            1e18
        );

        PositionUpdater.updatePosition(vault1, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getDebtValue(context.tokenState0, subVaults[vault1.subVaults[0]].balance0), 0);
        assertEq(BaseToken.getDebtValue(context.tokenState1, subVaults[vault1.subVaults[0]].balance1), 1e18);
    }

    function testUpdatePositionBorrowTokenWithCompound() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_TOKEN,
            0,
            true,
            0,
            0,
            0,
            0,
            1e18
        );

        PositionUpdater.updatePosition(vault1, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getDebtValue(context.tokenState0, subVaults[vault1.subVaults[0]].balance0), 0);
        assertEq(BaseToken.getDebtValue(context.tokenState1, subVaults[vault1.subVaults[0]].balance1), 1e18);
    }

    function testUpdatePositionBorrowTokenWithMargin() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_TOKEN,
            0,
            false,
            0,
            0,
            0,
            0,
            1e18
        );

        PositionUpdater.updatePosition(
            vault1,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                context.isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                1e8,
                0,
                EMPTY_METADATA
            )
        );

        assertEq(BaseToken.getDebtValue(context.tokenState0, subVaults[vault1.subVaults[0]].balance0), 0);
        assertEq(BaseToken.getDebtValue(context.tokenState1, subVaults[vault1.subVaults[0]].balance1), 1e18);
        assertEq(vault1.marginAmount0, int256(1e8));
    }

    function testUpdatePositionRepayToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_TOKEN,
            vault3.subVaults[0],
            false,
            0,
            0,
            0,
            1e6,
            0
        );

        PositionUpdater.updatePosition(vault3, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(vault3.subVaults.length, 0);
    }

    function testUpdatePositionRepayTokenWithCompound() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_TOKEN,
            vault5.subVaults[0],
            false,
            0,
            0,
            0,
            1e6 * 2,
            1e18 * 2
        );

        PositionUpdater.updatePosition(vault5, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(vault5.subVaults.length, 0);
    }

    function testUpdatePositionRepayTokenWithMargin() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](2);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            vault3.subVaults[0],
            false,
            0,
            0,
            0,
            1e6,
            0
        );

        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_TOKEN,
            vault3.subVaults[0],
            false,
            0,
            0,
            0,
            1e6,
            0
        );

        // test interest rate
        BaseToken.updateScaler(context.tokenState0, 1e16);
        BaseToken.updateScaler(context.tokenState1, 1e16);

        PositionUpdater.updatePosition(
            vault3,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(
                false,
                true,
                false,
                context.isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            )
        );

        assertEq(vault3.subVaults.length, 0);
        // margin must be less than 1e8 because vault paid interest.
        assertLt(vault3.marginAmount0, int256(1e8));
    }

    function testUpdatePositionDepositLPT() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            0,
            false,
            1000000000000,
            202560,
            202570,
            0,
            0
        );

        PositionUpdater.updatePosition(vault1, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(vault1.subVaults.length, 1);
        assertEq(subVaults[vault1.subVaults[0]].lpts.length, 1);
    }

    function testUpdatePositionMarginNotChanged() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        PositionUpdater.updatePosition(
            vault1,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(
                false,
                true,
                false,
                context.isMarginZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            )
        );

        assertEq(vault1.marginAmount0, int256(0));
        assertEq(vault1.marginAmount1, int256(0));
    }

    function testUpdatePositionDepositMargin(uint256 _marginAmount0, uint256 _marginAmount1) public {
        vm.assume(_marginAmount0 <= Constants.MAX_MARGIN_AMOUNT);
        vm.assume(_marginAmount1 <= Constants.MAX_MARGIN_AMOUNT);

        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        PositionUpdater.updatePosition(
            vault1,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(
                false,
                true,
                false,
                context.isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                int256(_marginAmount0),
                int256(_marginAmount1),
                EMPTY_METADATA
            )
        );

        assertEq(vault1.marginAmount0, int256(_marginAmount0));
        assertEq(vault1.marginAmount1, int256(_marginAmount1));
    }

    function testUpdatePositionWithdrawMargin() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        assertEq(vault3.marginAmount0, int256(101 * 1e6));
        assertEq(vault3.marginAmount1, int256(0));

        PositionUpdater.updatePosition(
            vault3,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(
                false,
                true,
                false,
                context.isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                -10 * 1e6,
                0,
                EMPTY_METADATA
            )
        );

        assertEq(vault3.marginAmount0, int256(91 * 1e6));
        assertEq(vault3.marginAmount1, int256(0));
    }

    function testUpdatePositionWithdrawFullMargin() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        assertEq(vault3.marginAmount0, int256(101 * 1e6));
        assertEq(vault3.marginAmount1, int256(0));

        PositionUpdater.updatePosition(
            vault3,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(
                false,
                true,
                false,
                context.isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                -200 * 1e6,
                0,
                EMPTY_METADATA
            )
        );

        assertEq(vault3.marginAmount0, int256(0));
        assertEq(vault3.marginAmount1, int256(0));
    }

    function testDepositTokenFromMargin(uint256 _marginAmount0, uint256 _marginAmount1) public {
        vm.assume(0 < _marginAmount0 && _marginAmount0 <= Constants.MAX_MARGIN_AMOUNT);
        vm.assume(0 < _marginAmount1 && _marginAmount1 <= Constants.MAX_MARGIN_AMOUNT);

        {
            DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

            PositionUpdater.updatePosition(
                vault1,
                subVaults,
                context,
                ranges,
                positionUpdates,
                DataType.TradeOption(
                    false,
                    false,
                    false,
                    context.isMarginZero,
                    Constants.MARGIN_USE,
                    Constants.MARGIN_USE,
                    PositionUpdater.roundMargin(int256(_marginAmount0), Constants.MARGIN_ROUNDED_DECIMALS),
                    int256(_marginAmount1),
                    EMPTY_METADATA
                )
            );
        }

        {
            DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.DEPOSIT_TOKEN,
                0,
                false,
                0,
                0,
                0,
                _marginAmount0,
                _marginAmount1
            );

            PositionUpdater.updatePosition(
                vault1,
                subVaults,
                context,
                ranges,
                positionUpdates,
                DataType.TradeOption(
                    false,
                    false,
                    false,
                    context.isMarginZero,
                    Constants.MARGIN_USE,
                    Constants.MARGIN_USE,
                    0,
                    0,
                    EMPTY_METADATA
                )
            );
        }

        assertEq(vault1.marginAmount0, int256(0));
        assertEq(vault1.marginAmount1, int256(0));
    }

    /**************************
     *   Test: depositTokens   *
     **************************/

    function testDepositTokens(uint256 _amount0, uint256 _amount1) public {
        uint256 amount0 = bound(_amount0, 1, 1e32);
        uint256 amount1 = bound(_amount1, 1, 1e32);

        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            0,
            false,
            0,
            0,
            0,
            amount0,
            amount1
        );

        PositionUpdater.depositTokens(subVaults[100], context, positionUpdate);

        assertEq(subVaults[100].balance0.assetAmount, amount0);
        assertEq(subVaults[100].balance1.assetAmount, amount1);
    }

    /**************************
     *   Test: depositLPT     *
     **************************/

    function testDepositLPT(uint256 _liquidity) public {
        uint128 liquidity = uint128(bound(_liquidity, 1e15, 1e20));
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            0,
            false,
            liquidity,
            100,
            200,
            0,
            0
        );

        // mint
        PositionUpdater.depositLPT(subVaults[1], context, ranges, positionUpdate);

        bytes32 rangeKey = LPTStateLib.getRangeKey(100, 200);

        assertGt(ranges[rangeKey].lastTouchedTimestamp, 0);
        assertEq(subVaults[1].lpts[0].rangeId, rangeKey);

        // increase
        PositionUpdater.depositLPT(subVaults[1], context, ranges, positionUpdate);

        assertGt(uint256(subVaults[1].lpts[0].liquidityAmount), liquidity);
        assertEq(uint256(subVaults[1].lpts[0].liquidityAmount), liquidity * 2);
    }

    function testCannotDepositLPTWithZeroAmount() public {
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            0,
            false,
            0,
            100,
            200,
            0,
            0
        );

        vm.expectRevert(bytes("PU3"));
        PositionUpdater.depositLPT(subVaults[1], context, ranges, positionUpdate);
    }

    /**************************
     *    Test: withdrawLPT   *
     **************************/

    function createTestDataDepositLPT(
        uint128 _liquidity,
        int24 _lower,
        int24 _upper
    ) internal {
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            0,
            false,
            _liquidity,
            _lower,
            _upper,
            0,
            0
        );

        PositionUpdater.depositLPT(subVaults[1], context, ranges, positionUpdate);
    }

    function testWithdrawLPT(uint256 _liquidity) public {
        uint128 liquidity = uint128(bound(_liquidity, 1000, 1e20));

        // deposit LPT
        createTestDataDepositLPT(1000, 100, 200);

        {
            // withdraw LPT
            DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
                DataType.PositionUpdateType.WITHDRAW_LPT,
                0,
                false,
                liquidity,
                100,
                200,
                0,
                0
            );

            PositionUpdater.withdrawLPT(subVaults[1], context, ranges, positionUpdate);
        }

        bytes32 rangeKey = LPTStateLib.getRangeKey(100, 200);

        uint256 liquidityAmount = LPTStateLib.getAvailableLiquidityAmount(
            address(this),
            context.uniswapPool,
            ranges[rangeKey]
        );

        assertEq(liquidityAmount, 0);
    }

    function testCannotWithdrawLPT(uint256 _liquidity) public {
        uint128 liquidity = uint128(bound(_liquidity, 1000, 1e20));

        // deposit LPT
        createTestDataDepositLPT(1000, 100, 200);

        {
            // borrow LPT
            DataType.PositionUpdate memory positionUpdateToBorrow = DataType.PositionUpdate(
                DataType.PositionUpdateType.BORROW_LPT,
                0,
                false,
                500,
                100,
                200,
                0,
                0
            );

            PositionUpdater.borrowLPT(subVaults[2], context, ranges, positionUpdateToBorrow);
        }

        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_LPT,
            0,
            false,
            liquidity,
            100,
            200,
            0,
            0
        );

        vm.expectRevert(bytes("LS"));
        PositionUpdater.withdrawLPT(subVaults[1], context, ranges, positionUpdate);
    }

    function testCannotWithdrawLPTWithZeroAmount() public {
        // deposit LPT
        createTestDataDepositLPT(1000, 100, 200);

        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_LPT,
            0,
            false,
            0,
            100,
            200,
            0,
            0
        );

        vm.expectRevert(bytes("PU3"));
        PositionUpdater.withdrawLPT(subVaults[1], context, ranges, positionUpdate);
    }

    /**************************
     *    Test: borrowLPT     *
     **************************/

    function testCannotBorrowLPTWithZeroAmount() public {
        // deposit LPT
        createTestDataDepositLPT(1000, 100, 200);

        // borrow LPT
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_LPT,
            0,
            false,
            0,
            100,
            200,
            0,
            0
        );

        vm.expectRevert(bytes("PU3"));
        PositionUpdater.borrowLPT(subVaults[2], context, ranges, positionUpdate);
    }

    function testBorrowLPT() public {
        // deposit LPT
        createTestDataDepositLPT(1000, 100, 200);

        {
            // borrow LPT
            DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
                DataType.PositionUpdateType.BORROW_LPT,
                0,
                false,
                500,
                100,
                200,
                0,
                0
            );

            PositionUpdater.borrowLPT(subVaults[2], context, ranges, positionUpdate);
        }

        bytes32 rangeKey = LPTStateLib.getRangeKey(100, 200);

        assertEq(uint256(ranges[rangeKey].borrowedLiquidity), 500);
    }

    // Cannot borrow LPT because the liquidity amount is less than the amount try to borrow
    function testCannotBorrowLPT() public {
        // deposit LPT
        createTestDataDepositLPT(1000, 100, 200);

        // borrow LPT
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_LPT,
            0,
            false,
            1001,
            100,
            200,
            0,
            0
        );

        vm.expectRevert(bytes("LS"));
        PositionUpdater.borrowLPT(subVaults[2], context, ranges, positionUpdate);
    }

    /**************************
     *    Test: repayLPT      *
     **************************/

    function createTestDataRepayLPT() internal {
        {
            // deposit LPT
            DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
                DataType.PositionUpdateType.DEPOSIT_LPT,
                0,
                false,
                1000,
                100,
                200,
                0,
                0
            );

            PositionUpdater.depositLPT(subVaults[1], context, ranges, positionUpdate);
        }

        {
            // borrow LPT
            DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
                DataType.PositionUpdateType.BORROW_LPT,
                0,
                false,
                500,
                100,
                200,
                0,
                0
            );

            PositionUpdater.borrowLPT(subVaults[2], context, ranges, positionUpdate);
        }
    }

    function testRepayLPT(uint256 _liquidity) public {
        uint128 liquidity = uint128(bound(_liquidity, 500, 1e20));

        createTestDataRepayLPT();

        {
            DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
                DataType.PositionUpdateType.REPAY_LPT,
                0,
                false,
                liquidity,
                100,
                200,
                0,
                0
            );

            PositionUpdater.repayLPT(subVaults[2], context, ranges, positionUpdate);
        }

        bytes32 rangeKey = LPTStateLib.getRangeKey(100, 200);

        assertEq(uint256(ranges[rangeKey].borrowedLiquidity), 0);
    }

    function testCannotRepayLPTWithZeroAmount() public {
        createTestDataRepayLPT();

        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_LPT,
            0,
            false,
            0,
            100,
            200,
            0,
            0
        );

        vm.expectRevert(bytes("PU3"));
        PositionUpdater.repayLPT(subVaults[2], context, ranges, positionUpdate);
    }

    /**************************
     *   Test: swapExactIn     *
     **************************/

    function testSwapExactInZeroForOne() public {
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_IN,
            0,
            true,
            500,
            0,
            0,
            1000000,
            0
        );

        (int256 requiredAmount0, int256 requiredAmount1) = PositionUpdater.swapExactIn(vault2, context, positionUpdate);

        assertEq(requiredAmount0, 1000000);
        assertLt(requiredAmount1, 0);
    }

    function testSwapExactInOneForZero() public {
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_IN,
            0,
            false,
            500,
            0,
            0,
            1e18,
            0
        );

        (int256 requiredAmount0, int256 requiredAmount1) = PositionUpdater.swapExactIn(vault2, context, positionUpdate);

        assertLt(requiredAmount0, 0);
        assertEq(requiredAmount1, 1e18);
    }

    /**************************
     *   Test: swapExactOut     *
     **************************/

    function testSwapExactOutZeroForOne() public {
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_OUT,
            0,
            true,
            500,
            0,
            0,
            1e18,
            0
        );

        (int256 requiredAmount0, int256 requiredAmount1) = PositionUpdater.swapExactOut(
            vault2,
            context,
            positionUpdate
        );

        assertGt(requiredAmount0, 0);
        assertEq(requiredAmount1, -1e18);
    }

    function testSwapExactOutOneForZero() public {
        DataType.PositionUpdate memory positionUpdate = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_OUT,
            0,
            false,
            500,
            0,
            0,
            1000000,
            0
        );

        (int256 requiredAmount0, int256 requiredAmount1) = PositionUpdater.swapExactOut(
            vault2,
            context,
            positionUpdate
        );

        assertEq(requiredAmount0, -1000000);
        assertGt(requiredAmount1, 0);
    }
}
