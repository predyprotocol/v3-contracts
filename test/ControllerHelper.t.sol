// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/TestDeployer.sol";
import "../src/Controller.sol";
import "../src/mocks/MockERC20.sol";

contract ControllerHelperTest is TestDeployer, Test {
    address owner;
    bool isQuoteZero;

    uint256 private vaultId1;
    uint256 private vaultId2;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        vaultId1 = depositToken(0, 1e10, 5 * 1e18);
        vaultId2 = depositLPT(0, 0, 202500, 202600, 2 * 1e18);

        isQuoteZero = getIsMarginZero();
    }

    /**************************
     *   Test: openPosition   *
     **************************/

    function testDepositETH() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        uint256 beforeBalance0 = token0.balanceOf(owner);
        uint256 beforeBalance1 = token1.balanceOf(owner);
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, false, false, false, -1, -1, EMPTY_METADATA),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
        uint256 afterBalance0 = token0.balanceOf(owner);
        uint256 afterBalance1 = token1.balanceOf(owner);

        assertEq(beforeBalance0, afterBalance0);
        assertGt(beforeBalance1, afterBalance1);
    }

    function testDepositLPT() public {
        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202560, 202570);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202560, 202570);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 0, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, getIsMarginZero(), -1, -1, EMPTY_METADATA),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function testDepositLPTAndBorrowETH() public {
        int256 margin = 500 * 1e6;

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 5 minutes);

        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 1e18, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, getIsMarginZero(), margin, -1, EMPTY_METADATA),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 0, block.timestamp)
        );
    }

    function testBorrowLPT(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 10 * 1e18);

        slip(owner, true, swapAmount);

        int256 margin = 500 * 1e6;

        DataType.Position[] memory positions = getBorrowLPTPosition(0, 202600, 202500, 202600, 1e18);

        (uint256 vaultId, , ) = controller.openPosition(
            0,
            positions[0],
            DataType.TradeOption(false, true, false, getIsMarginZero(), margin, -1, EMPTY_METADATA),
            // deposit margin
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.marginValue, margin);
        assertGt(vaultStatus.subVaults[0].values.assetValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);
    }

    function testBorrowLPTWithLowPrice(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 10 * 1e18);

        slip(owner, false, swapAmount);

        uint256 margin = 100 * 1e6;

        (uint128 liquidity, , ) = getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(0, margin, 1e18, 0, 0, lpts);

        (uint256 vaultId, , ) = controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, getIsMarginZero(), int256(margin), -1, EMPTY_METADATA),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertGt(vaultStatus.subVaults[0].values.assetValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);
    }

    function testCannotOpenPositionBecauseSlippage() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        uint256 lowerSqrtPrice = getSqrtPrice();
        uint256 upperSqrtPrice = getSqrtPrice();
        bool isMarginZero = getIsMarginZero();

        vm.expectRevert(bytes("CH2"));
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, isMarginZero, -1, -1, EMPTY_METADATA),
            DataType.OpenPositionOption(lowerSqrtPrice, upperSqrtPrice, 100, block.timestamp)
        );
    }

    function testCannotQuoterMode() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 1e8, 0, 0, 0, lpts);

        uint256 lowerSqrtPrice = getLowerSqrtPrice();
        uint256 upperSqrtPrice = getUpperSqrtPrice();

        vm.expectRevert(abi.encode(DataType.TokenAmounts(1e8, 0), DataType.TokenAmounts(0, 0)));
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, false, true, true, -1, -1, EMPTY_METADATA),
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
            DataType.TradeOption(false, true, false, getIsMarginZero(), int256(margin), -1, EMPTY_METADATA),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function testSubVaults() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202600, 202700);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202600, 202700);
        DataType.Position memory position = DataType.Position(1, 0, 0, 0, 0, lpts);

        controller.openPosition(
            vaultId,
            position,
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 2);
    }

    function testCannotCreateSubVaults() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202600, 202700);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202600, 202700);
        DataType.Position memory position = DataType.Position(2, 0, 0, 0, 0, lpts);

        uint256 lowerSqrtPrice = getLowerSqrtPrice();
        uint256 upperSqrtPrice = getUpperSqrtPrice();
        bool isMarginZero = getIsMarginZero();

        vm.expectRevert(bytes("V0"));
        controller.openPosition(
            vaultId,
            position,
            DataType.TradeOption(false, false, false, isMarginZero, -1, -1, EMPTY_METADATA),
            DataType.OpenPositionOption(lowerSqrtPrice, upperSqrtPrice, 100, block.timestamp)
        );
    }

    /**************************
     *   Test: closePosition  *
     **************************/

    function testRepayHalfOfLPT() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 5 minutes);

        DataType.Position[] memory positions = getBorrowLPTPosition(0, 202600, 202500, 202600, 1e18 / 2);

        controller.closePosition(
            vaultId,
            positions,
            DataType.TradeOption(false, true, false, getIsMarginZero(), -2, -2, EMPTY_METADATA),
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
        depositLPT(vaultId, 1, 202600, 202700, 1e18);

        vm.warp(block.timestamp + 5 minutes);

        controller.closeSubVault(
            vaultId,
            0,
            DataType.TradeOption(false, true, false, true, -2, -1, EMPTY_METADATA),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 1);
    }

    /**************************
     *   Test: closeVault     *
     **************************/

    function testCannotClosePositionBecauseCallerIsNotOwner() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        vm.stopPrank();

        vm.prank(otherAccount);
        vm.expectRevert(bytes("P2"));
        controller.closeVault(
            vaultId,
            DataType.TradeOption(false, false, false, isQuoteZero, -1, -1, EMPTY_METADATA),
            DataType.ClosePositionOption(1500 * 1e6, 2000, 100, 1e4, block.timestamp)
        );
    }

    function testComplecatedPosition(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 20 * 1e18);

        uint256 vaultId = depositLPT(0, 0, 202600, 202700, 1 * 1e18);
        borrowLPT(vaultId, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        slip(owner, false, swapAmount);

        vm.warp(block.timestamp + 5 minutes);

        uint256 before0 = token0.balanceOf(owner);
        uint256 before1 = token1.balanceOf(owner);
        controller.closeVault(
            vaultId,
            DataType.TradeOption(false, true, false, getIsMarginZero(), -1, -1, EMPTY_METADATA),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );
        uint256 afterBalance0 = token0.balanceOf(owner);
        uint256 afterBalance1 = token1.balanceOf(owner);

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
            DataType.TradeOption(false, true, false, true, -1, -1, EMPTY_METADATA),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );
    }

    function testWithdrawLPT(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 5 * 1e18);

        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);
        uint256 vaultId3 = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        slip(owner, true, swapAmount);

        vm.warp(block.timestamp + 5 minutes);

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            getIsMarginZero(),
            0,
            -1,
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
    }

    function testRepayLPT(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 10 * 1e18);

        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        slip(owner, true, swapAmount);

        vm.warp(block.timestamp + 5 minutes);

        uint256 before0 = token0.balanceOf(owner);
        uint256 before1 = token1.balanceOf(owner);
        controller.closeVault(
            vaultId,
            DataType.TradeOption(false, true, false, getIsMarginZero(), 0, -1, EMPTY_METADATA),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 54, 1e4, block.timestamp)
        );
        uint256 afterBalance0 = token0.balanceOf(owner);
        uint256 afterBalance1 = token1.balanceOf(owner);

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
        openShortPut(vaultId, 1, 202600, 202700, 1e18);

        vm.warp(block.timestamp + 5 minutes);

        controller.closeVault(
            vaultId,
            DataType.TradeOption(false, true, false, true, -2, -1, EMPTY_METADATA),
            DataType.ClosePositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, 1e4, block.timestamp)
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testWithdrawProtocolFee() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 60 minutes);

        controller.closeVault(
            vaultId,
            DataType.TradeOption(false, true, false, getIsMarginZero(), 0, -1, EMPTY_METADATA),
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
        assertFalse(controller.checkLiquidatable(100));

        DataType.LiquidationOption memory option = DataType.LiquidationOption(100, 1e4);

        vm.expectRevert(bytes("P5"));
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
            DataType.TradeOption(false, false, false, getIsMarginZero(), 1000, -1, EMPTY_METADATA),
            DataType.OpenPositionOption(lowerSqrtPrice, upperSqrtPrice, 100, block.timestamp)
        );

        assertFalse(controller.checkLiquidatable(vaultId));

        DataType.LiquidationOption memory option = DataType.LiquidationOption(100, 1e4);

        vm.expectRevert(bytes("L0"));
        controller.liquidate(vaultId, option);
    }

    function testCannotLiquidate() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 5 minutes);

        assertFalse(controller.checkLiquidatable(vaultId));

        DataType.LiquidationOption memory option = DataType.LiquidationOption(100, 1e4);

        vm.expectRevert(bytes("L0"));
        controller.liquidate(vaultId, option);
    }

    function testLiquidateBorrowLPTPosition() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 7 hours);

        assertTrue(controller.checkLiquidatable(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(owner);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 1e4));
        uint256 afterBalance0 = token0.balanceOf(owner);

        // get penalty amount
        console.log(afterBalance0 - beforeBalance0);
        assertGt(afterBalance0, beforeBalance0);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);

        assertFalse(controller.checkLiquidatable(vaultId));
    }

    function testLiquidateBecauseMarginIsNegative() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);
        depositToken(vaultId, 1e11, 0);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 2 days);

        DataType.VaultStatus memory vaultStatus1 = getVaultStatus(vaultId);

        assertLt(vaultStatus1.marginValue, 0);

        assertTrue(controller.checkLiquidatable(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(owner);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 1e4));
        uint256 afterBalance0 = token0.balanceOf(owner);

        // get penalty amount
        console.log(afterBalance0 - beforeBalance0);
        assertGt(afterBalance0, beforeBalance0);

        DataType.VaultStatus memory vaultStatus2 = getVaultStatus(vaultId);

        assertEq(vaultStatus2.subVaults.length, 0);

        assertFalse(controller.checkLiquidatable(vaultId));
    }

    function testLiquidatePartially() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 7 hours);

        assertTrue(controller.checkLiquidatable(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(owner);
        controller.liquidate(vaultId, DataType.LiquidationOption(100, 5000));
        uint256 afterBalance0 = token0.balanceOf(owner);

        // get penalty amount
        assertGt(afterBalance0, beforeBalance0);

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 1);

        assertFalse(controller.checkLiquidatable(vaultId));
    }
}
