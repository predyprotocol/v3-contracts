// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./Setup.t.sol";
import "../../src/Controller.sol";
import "../../src/mocks/MockERC20.sol";

contract ControllerTest is TestController {
    function setUp() public override {
        TestController.setUp();
    }

    /**************************
     *   Test: openPosition   *
     **************************/

    function testDepositETH() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        uint256 beforeBalance0 = token0.balanceOf(user);
        uint256 beforeBalance1 = token1.balanceOf(user);
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                false,
                false,
                false,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                Constants.MIN_MARGIN_AMOUNT,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
        uint256 afterBalance0 = token0.balanceOf(user);
        uint256 afterBalance1 = token1.balanceOf(user);

        assertEq(beforeBalance0 - afterBalance0, uint256(Constants.MIN_MARGIN_AMOUNT));
        assertEq(beforeBalance1 - afterBalance1, 1e18);
    }

    function testDepositLPT() public {
        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202560, 202570);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202560, 202570);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 0, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function testDepositLPTOnNonInitializedTick() public {
        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 205000, 205600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 205000, 205600);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 0, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function testDepositLPTAndBorrowETH() public {
        int256 margin = 500 * 1e6;

        swapToSamePrice(user);

        vm.warp(block.timestamp + 5 minutes);

        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 1e18, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                margin,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 0, block.timestamp)
        );
    }

    function testBorrowLPT1(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 10 * 1e18);

        slip(user, true, swapAmount);

        int256 margin = 500 * 1e6;

        DataType.Position[] memory positions = getBorrowLPTPosition(0, 202600, 202500, 202600, 1e18);

        (uint256 vaultId, , ) = controller.openPosition(
            0,
            positions[0],
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                margin,
                0,
                EMPTY_METADATA
            ),
            // deposit margin
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertLt(vaultStatus.marginValue, margin);
        assertGt(vaultStatus.subVaults[0].values.assetValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);

        DataType.PerpStatus memory range = controller.getRange(LPTStateLib.getRangeKey(202500, 202600));
        assertGt(range.fee0Growth, 0);
    }

    function testBorrowLPTAndFullUtilization() public {
        int256 margin = 500 * 1e6;

        DataType.Position[] memory positions = getBorrowLPTPosition(0, 202600, 202500, 202600, 2 * 1e18);

        (uint256 vaultId, , ) = controller.openPosition(
            0,
            positions[0],
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                margin,
                0,
                EMPTY_METADATA
            ),
            // deposit margin
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        // Checks utilization ratio is 100%
        (, , uint256 ur) = controller.getUtilizationRatio(LPTStateLib.getRangeKey(202500, 202600));
        assertEq(ur, 1e18);

        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                false,
                false,
                isQuoteZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );
    }

    function testCannotBorrowLPTBecauseOfLessLiquidity() public {
        int256 margin = 500 * 1e6;

        DataType.Position[] memory positions = getBorrowLPTPosition(0, 202600, 202500, 202600, 3 * 1e18);

        bool isMarginZero = getIsMarginZero();

        vm.expectRevert(bytes("LS"));
        controller.openPosition(
            0,
            positions[0],
            DataType.TradeOption(
                false,
                true,
                false,
                isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                margin,
                0,
                EMPTY_METADATA
            ),
            // deposit margin
            DataType.OpenPositionOption(0, 0, 100, block.timestamp)
        );

        DataType.PerpStatus memory range = controller.getRange(LPTStateLib.getRangeKey(202500, 202600));
        assertEq(uint256(range.borrowedLiquidity), 0);
    }

    function testBorrowLPTWithLowPrice(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 10 * 1e18);

        slip(user, false, swapAmount);

        uint256 margin = 100 * 1e6;

        (uint128 liquidity, , ) = getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(0, margin, 1e18, 0, 0, lpts);

        (uint256 vaultId, , ) = controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                int256(margin),
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertGt(vaultStatus.subVaults[0].values.assetValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);
    }

    function testCannotOpenPositionBecauseTxTooOld() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        vm.expectRevert(bytes("P7"));
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                true,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(0, 0, 100, block.timestamp - 1)
        );
    }

    function testCannotOpenPositionBecauseSlippage() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        uint256 lowerSqrtPrice = getSqrtPrice();
        uint256 upperSqrtPrice = getSqrtPrice();
        bool isMarginZero = getIsMarginZero();

        vm.expectRevert(bytes("P8"));
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                isMarginZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(lowerSqrtPrice, upperSqrtPrice, 100, block.timestamp)
        );
    }

    function testCannotQuoterMode() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 1e8, 0, 0, 0, lpts);

        uint256 lowerSqrtPrice = getLowerSqrtPrice();
        uint256 upperSqrtPrice = getUpperSqrtPrice();

        vm.expectRevert(
            abi.encode(
                DataType.TokenAmounts(1e8, 0),
                DataType.TokenAmounts(0, 0),
                DataType.TokenAmounts(1e8, 0),
                DataType.TokenAmounts(0, 0)
            )
        );
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                false,
                true,
                true,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(lowerSqrtPrice, upperSqrtPrice, 100, block.timestamp)
        );
    }

    function testBorrowETH() public {
        uint256 margin = 500 * 1e6;

        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202560, 202570);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202560, 202570);
        DataType.Position memory position = DataType.Position(0, 1000 * 1e6, 0, 0, 1e18, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                int256(margin),
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function testCannotBorrowETH() public {
        uint256 margin = 5000 * 1e6;

        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 5 * 1e18 + 1, lpts);

        bool isMarginZero = getIsMarginZero();

        vm.expectRevert(bytes("B0"));
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                false,
                isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                int256(margin),
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(0, 0, 100, block.timestamp)
        );
    }

    function testSubVaults() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202600, 202700);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202600, 202700);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 0, lpts);

        controller.openPosition(
            vaultId,
            position,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 2);
    }

    /**************************
     *   Test: closePosition  *
     **************************/

    function testRepayHalfOfLPT() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 5 minutes);

        DataType.Vault memory vault = controller.getVault(vaultId);

        DataType.Position[] memory positions = getBorrowLPTPosition(
            vault.subVaults[0],
            202600,
            202500,
            202600,
            1e18 / 2
        );

        controller.closePosition(
            vaultId,
            positions,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 54, 1e4, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertGt(vaultStatus.marginValue, 0);
        assertEq(vaultStatus.subVaults.length, 1);
    }

    /**************************
     *   Test: closeSubVault  *
     **************************/

    function testCloseOneSubVault() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);
        depositLPT(vaultId, 0, 202600, 202700, 1e18);

        vm.warp(block.timestamp + 5 minutes);

        DataType.Vault memory vault = controller.getVault(vaultId);

        controller.closeSubVault(
            vaultId,
            vault.subVaults[0],
            DataType.TradeOption(
                false,
                true,
                false,
                true,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 1);
    }

    function testCloseLendingSubVault() public {
        uint256 vaultId = depositToken(0, 1e11, 0, true);
        uint256 vaultId2 = depositToken(0, 1e11, 0, false);
        borrowToken(vaultId2, 7 * 1e10, 0);

        vm.warp(block.timestamp + 1 days);

        DataType.Vault memory vault = controller.getVault(vaultId);

        controller.closeSubVault(
            vaultId,
            vault.subVaults[0],
            DataType.TradeOption(
                false,
                true,
                false,
                true,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 0);
    }

    /**************************
     *   Test: closeVault     *
     **************************/

    function testCannotClosePositionBecauseCallerIsNotOwner() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        vm.stopPrank();

        vm.prank(OTHER_ACCOUNT);
        vm.expectRevert(bytes("P1"));
        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                false,
                false,
                isQuoteZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(1500 * 1e6, 2000, 100, 1e4, block.timestamp)
        );
    }

    function testComplecatedPosition(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 20 * 1e18);

        uint256 vaultId = depositLPT(0, 0, 202600, 202700, 1 * 1e18);
        borrowLPT(vaultId, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        slip(user, false, swapAmount);

        vm.warp(block.timestamp + 5 minutes);

        uint256 before0 = token0.balanceOf(user);
        uint256 before1 = token1.balanceOf(user);
        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );
        uint256 afterBalance0 = token0.balanceOf(user);
        uint256 afterBalance1 = token1.balanceOf(user);

        console.log(0, afterBalance0 - before0);
        console.log(1, afterBalance1 - before1);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testWithdrawLPTWithSwapAnyway() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        vm.warp(block.timestamp + 5 minutes);

        // vm.expectRevert(bytes("AS"));
        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                true,
                false,
                true,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                -1,
                -1,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );
    }

    function testCannotWithdrawLPT(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 5 * 1e18);

        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);
        borrowLPT(0, 0, 202600, 202500, 202600, 25 * 1e17, 100 * 1e6);

        slip(user, true, swapAmount);

        vm.warp(block.timestamp + 7 hours);

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            getIsMarginZero(),
            Constants.MARGIN_USE,
            Constants.MARGIN_STAY,
            Constants.FULL_WITHDRAWAL,
            0,
            EMPTY_METADATA
        );
        DataType.ClosePositionOption memory closeOption = DataType.ClosePositionOption(
            getLowerSqrtPrice(),
            getUpperSqrtPrice(),
            100,
            1e4,
            block.timestamp
        );

        vm.expectRevert(bytes("LS"));
        controller.closeVault(vaultId, tradeOption, closeOption);
    }

    function testWithdrawLPT(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 5 * 1e18);

        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);
        uint256 vaultId3 = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        slip(user, true, swapAmount);

        vm.warp(block.timestamp + 7 hours);

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            getIsMarginZero(),
            Constants.MARGIN_USE,
            Constants.MARGIN_STAY,
            Constants.FULL_WITHDRAWAL,
            0,
            EMPTY_METADATA
        );
        DataType.ClosePositionOption memory closeOption = DataType.ClosePositionOption(
            getLowerSqrtPrice(),
            getUpperSqrtPrice(),
            100,
            1e4,
            block.timestamp
        );

        controller.closeVault(vaultId, tradeOption, closeOption);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);

        // close all positions
        controller.closeVault(vaultId3, tradeOption, closeOption);

        controller.closeVault(vaultId2, tradeOption, closeOption);

        controller.closeVault(vaultId1, tradeOption, closeOption);

        // withdraw protocol fee
        (, , , uint256 protocolFee0, uint256 protocolFee1) = controller.getContext();

        controller.withdrawProtocolFee(protocolFee0, protocolFee1);
    }

    function testRepayLPT(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 10 * 1e18);

        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        slip(user, true, swapAmount);

        vm.warp(block.timestamp + 5 minutes);

        uint256 before0 = token0.balanceOf(user);
        uint256 before1 = token1.balanceOf(user);
        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                Constants.FULL_WITHDRAWAL,
                0,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 54, 1e4, block.timestamp)
        );
        uint256 afterBalance0 = token0.balanceOf(user);
        uint256 afterBalance1 = token1.balanceOf(user);

        console.log(0, afterBalance0 - before0);
        console.log(1, afterBalance1 - before1);

        assertGt(afterBalance0, before0);
        assertEq(afterBalance1, before1);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.marginValue, 0);
        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testCloseSubVaults() public {
        uint256 vaultId = openShortPut(0, 0, 202500, 202600, 1e18);
        openShortPut(vaultId, 0, 202600, 202700, 1e18);

        vm.warp(block.timestamp + 5 minutes);

        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                true,
                false,
                true,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testWithdrawProtocolFee() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 60 minutes);

        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                Constants.FULL_WITHDRAWAL,
                0,
                EMPTY_METADATA
            ),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );

        (, , , uint256 protocolFee0, uint256 protocolFee1) = controller.getContext();

        controller.withdrawProtocolFee(protocolFee0, protocolFee1);

        (, , , uint256 protocolFee0After, uint256 protocolFee1After) = controller.getContext();

        assertEq(protocolFee0After, 0);
        assertEq(protocolFee1After, 0);
        assertGt(protocolFee0, 0);
        assertEq(protocolFee1, 0);
    }

    /**************************
     *   Test: liquidate      *
     **************************/

    function testCannotLiquidateNonExistingVault() public {
        assertFalse(!controller.isVaultSafe(100));

        DataType.LiquidationOption memory option = DataType.LiquidationOption(100, 1e4);

        vm.expectRevert(bytes("P2"));
        controller.liquidate(100, option);
    }

    function testCannotLiquidateEmptyVault() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 0, lpts);

        uint256 lowerSqrtPrice = getLowerSqrtPrice();
        uint256 upperSqrtPrice = getUpperSqrtPrice();

        (uint256 vaultId, , ) = controller.openPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                1000000,
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(lowerSqrtPrice, upperSqrtPrice, 100, block.timestamp)
        );

        assertFalse(!controller.isVaultSafe(vaultId));

        DataType.LiquidationOption memory option = DataType.LiquidationOption(100, 1e4);

        vm.expectRevert(bytes("L0"));
        controller.liquidate(vaultId, option);
    }

    function testCannotLiquidate() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 5 minutes);

        assertFalse(!controller.isVaultSafe(vaultId));

        DataType.LiquidationOption memory option = DataType.LiquidationOption(100, 1e4);

        vm.expectRevert(bytes("L0"));
        controller.liquidate(vaultId, option);
    }

    function testLiquidateBorrowLPTPosition() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 7 hours);

        assertTrue(!controller.isVaultSafe(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(user);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 1e4));
        uint256 afterBalance0 = token0.balanceOf(user);

        // get penalty amount
        console.log(afterBalance0 - beforeBalance0);
        assertGt(afterBalance0, beforeBalance0);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);

        assertFalse(!controller.isVaultSafe(vaultId));
    }

    function testLiquidateBecauseMarginIsNegative() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);
        depositToken(vaultId, 1e11, 0, false);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 2 days);

        DataType.VaultStatus memory vaultStatus1 = getVaultStatus(vaultId);

        assertLt(vaultStatus1.marginValue, 0);

        assertTrue(!controller.isVaultSafe(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(user);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 1e4));
        uint256 afterBalance0 = token0.balanceOf(user);

        // get penalty amount
        console.log(afterBalance0 - beforeBalance0);
        assertGt(afterBalance0, beforeBalance0);

        DataType.VaultStatus memory vaultStatus2 = getVaultStatus(vaultId);

        assertEq(vaultStatus2.subVaults.length, 0);

        assertFalse(!controller.isVaultSafe(vaultId));
    }

    function testLiquidatePartially() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 7 hours);

        assertTrue(!controller.isVaultSafe(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(user);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 5000));
        uint256 afterBalance0 = token0.balanceOf(user);

        // get penalty amount
        assertGt(afterBalance0, beforeBalance0);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 1);

        assertFalse(!controller.isVaultSafe(vaultId));
    }

    function testLiquidateDefaultPosition() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 24 hours);

        assertTrue(!controller.isVaultSafe(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(user);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 1e4));
        uint256 afterBalance0 = token0.balanceOf(user);

        // penalty amount is zero
        assertEq(afterBalance0, beforeBalance0);

        DataType.Vault memory vault = controller.getVault(vaultId);

        assertLt(vault.marginAmount0, 0);
        assertEq(vault.marginAmount1, 0);
        assertFalse(!controller.isVaultSafe(vaultId));
    }

    function testLiquidateAndGetMinPenalty() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 2 * 1e14, 1e6 + 1e4);

        swapToSamePrice(user);

        vm.warp(block.timestamp + 1 days);

        assertTrue(!controller.isVaultSafe(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(user);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 1e4));
        uint256 afterBalance0 = token0.balanceOf(user);

        // get penalty amount
        assertEq(afterBalance0 - beforeBalance0, Constants.MIN_PENALTY);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);

        assertFalse(!controller.isVaultSafe(vaultId));
    }
}
