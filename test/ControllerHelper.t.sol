// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/TestDeployer.sol";
import "../src/ControllerHelper.sol";
import "../src/mocks/MockERC20.sol";

contract ControllerHelperTest is TestDeployer, Test {
    address owner;
    bool isQuoteZero;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        depositToken(0, 1e10, 5 * 1e18);
        depositLPT(0, 0, 202500, 202600, 2 * 1e18);

        isQuoteZero = controller.getIsMarginZero();
    }

    function testCannotClosePositionBecauseCallerIsNotOwner() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        vm.stopPrank();

        vm.prank(otherAccount);
        vm.expectRevert(bytes("P2"));
        controller.closePosition(
            vaultId,
            DataType.TradeOption(false, false, false, isQuoteZero),
            DataType.ClosePositionOption(0, 1500 * 1e6, 2000, 100, bytes(""))
        );
    }

    function testDepositETH() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        uint256 beforeBalance0 = token0.balanceOf(owner);
        uint256 beforeBalance1 = token1.balanceOf(owner);
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, false, false, false),
            DataType.OpenPositionOption(0, 1500 * 1e6, 1000, 0, 1e18, bytes(""))
        );
        uint256 afterBalance0 = token0.balanceOf(owner);
        uint256 afterBalance1 = token1.balanceOf(owner);

        assertEq(beforeBalance0, afterBalance0);
        assertGt(beforeBalance1, afterBalance1);
    }

    function testDepositLPT() public {
        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToDeposit(
            true,
            1e18,
            controller.getSqrtPrice(),
            202560,
            202570
        );

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202560, 202570);
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, 0, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            DataType.OpenPositionOption(0, 1500 * 1e6, 1000, 1e10, 0, bytes(""))
        );
    }

    function testBorrowLPT1(uint256 _swapAmount) public {
        vm.assume(1e16 <= _swapAmount && _swapAmount < 10 * 1e18);

        slip(owner, true, _swapAmount);

        uint256 margin = 500 * 1e6;

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        uint256 vaultId = controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, controller.getIsMarginZero()),
            // deposit margin
            DataType.OpenPositionOption(int256(margin), controller.getPrice(), 500, 1e10, 0, bytes(""))
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertGt(vaultStatus.subVaults[0].values.collateralValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);
    }

    function testBorrowLPTWithLowPrice(uint256 _swapAmount) public {
        vm.assume(1e16 <= _swapAmount && _swapAmount < 10 * 1e18);

        slip(owner, false, _swapAmount);

        uint256 margin = 100 * 1e6;

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(0, margin, 1e18, 0, 0, lpts);

        uint256 vaultId = controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, controller.getIsMarginZero()),
            DataType.OpenPositionOption(0, controller.getPrice(), 500, 1e10, 0, bytes(""))
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertGt(vaultStatus.subVaults[0].values.collateralValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);
    }

    function testCannotOpenPositionBecauseSlippage() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 0, 1e18, 0, 0, lpts);

        uint256 price = controller.getPrice();
        bool isMarginZero = controller.getIsMarginZero();

        vm.expectRevert(bytes("CH2"));
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, isMarginZero),
            DataType.OpenPositionOption(0, price, 0, 1e10, 0, bytes(""))
        );
    }

    function testWithdrawLPTWithSwapAnyway() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        vm.warp(block.timestamp + 5 minutes);

        // vm.expectRevert(bytes("AS"));
        controller.closePosition(
            vaultId,
            DataType.TradeOption(false, true, false, true),
            DataType.ClosePositionOption(0, 1500 * 1e6, 2000, 100, bytes(""))
        );
    }

    function testWithdrawLPT(uint256 _swapAmount) public {
        vm.assume(1e16 <= _swapAmount && _swapAmount < 5 * 1e18);

        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);
        borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        slip(owner, true, _swapAmount);

        vm.warp(block.timestamp + 5 minutes);

        controller.closePosition(
            vaultId,
            DataType.TradeOption(false, true, false, controller.getIsMarginZero()),
            DataType.ClosePositionOption(0, controller.getPrice(), 2000, 100, bytes(""))
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testRepayLPT() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 5 minutes);

        uint256 before0 = token0.balanceOf(owner);
        uint256 before1 = token1.balanceOf(owner);
        controller.closePosition(
            vaultId,
            DataType.TradeOption(false, true, false, controller.getIsMarginZero()),
            DataType.ClosePositionOption(-1e20, 1500 * 1e6, 1000, 54, bytes(""))
        );
        uint256 afterBalance0 = token0.balanceOf(owner);
        uint256 afterBalance1 = token1.balanceOf(owner);

        console.log(0, afterBalance0 - before0);
        console.log(1, afterBalance1 - before1);

        assertGt(afterBalance0, before0);
        assertEq(afterBalance1, before1);

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testComplecatedPosition() public {
        uint256 vaultId = depositLPT(0, 0, 202600, 202700, 1 * 1e18);
        borrowLPT(vaultId, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 5 minutes);

        uint256 before0 = token0.balanceOf(owner);
        uint256 before1 = token1.balanceOf(owner);
        controller.closePosition(
            vaultId,
            DataType.TradeOption(false, true, false, controller.getIsMarginZero()),
            DataType.ClosePositionOption(0, 1500 * 1e6, 1000, 100, bytes(""))
        );
        uint256 afterBalance0 = token0.balanceOf(owner);
        uint256 afterBalance1 = token1.balanceOf(owner);

        console.log(0, afterBalance0 - before0);
        console.log(1, afterBalance1 - before1);

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testCannotQuoterMode() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        DataType.Position memory position = DataType.Position(0, 1e8, 0, 0, 0, lpts);

        vm.expectRevert(abi.encode(1e8, 0));
        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, false, true, true),
            DataType.OpenPositionOption(0, 1500 * 1e6, 1000, 0, 0, bytes(""))
        );
    }

    function testLiquidateBorrowLPTPosition() public {
        uint256 vaultId = borrowLPT(0, 0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 100 minutes);

        assertTrue(controller.checkLiquidatable(vaultId));

        uint256 beforeBalance0 = token0.balanceOf(owner);
        controller.liquidate(vaultId, DataType.LiquidationOption(1500 * 1e6, 2000, 54, true));
        uint256 afterBalance0 = token0.balanceOf(owner);

        // get penalty amount
        console.log(afterBalance0 - beforeBalance0);
        assertGt(afterBalance0, beforeBalance0);

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testBorrowETH() public {
        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToDeposit(
            true,
            1e18,
            controller.getSqrtPrice(),
            202560,
            202570
        );

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202560, 202570);
        DataType.Position memory position = DataType.Position(0, 1000 * 1e6, 0, 0, 1e18, lpts);

        controller.openPosition(
            0,
            position,
            DataType.TradeOption(false, true, false, controller.getIsMarginZero()),
            DataType.OpenPositionOption(0, 1500 * 1e6, 1000, 1e10, 0, bytes(""))
        );
    }

    function testSubVaults() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToDeposit(
            true,
            1e18,
            controller.getSqrtPrice(),
            202600,
            202700
        );

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202600, 202700);
        DataType.Position memory position = DataType.Position(1, 0, 0, 0, 0, lpts);

        controller.openPosition(
            vaultId,
            position,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            DataType.OpenPositionOption(0, 1500 * 1e6, 1000, 1e10, 0, bytes(""))
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 2);
    }

    function testCannotCreateSubVaults() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToDeposit(
            true,
            1e18,
            controller.getSqrtPrice(),
            202600,
            202700
        );

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202600, 202700);
        DataType.Position memory position = DataType.Position(2, 0, 0, 0, 0, lpts);

        bool isMarginZero = controller.getIsMarginZero();

        vm.expectRevert(bytes("PU4"));
        controller.openPosition(
            vaultId,
            position,
            DataType.TradeOption(false, false, false, isMarginZero),
            DataType.OpenPositionOption(0, 1500 * 1e6, 1000, 1e10, 0, bytes(""))
        );
    }

    function testCloseSubVaults() public {
        uint256 vaultId = depositLPT(0, 0, 202500, 202600, 1e18);
        depositLPT(vaultId, 1, 202600, 202700, 1e18);

        vm.warp(block.timestamp + 5 minutes);

        uint256 price = controller.getPrice();

        controller.closePosition(
            vaultId,
            DataType.TradeOption(false, true, false, true),
            DataType.ClosePositionOption(0, price, 500, 100, bytes(""))
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);
        assertEq(vaultStatus.subVaults.length, 0);
    }
}
