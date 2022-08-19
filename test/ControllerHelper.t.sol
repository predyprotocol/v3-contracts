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

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        depositLPT(0, 202500, 202600, 2 * 1e18);
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
        DataType.Position memory position = DataType.Position(0, 0, 0, 0, lpts);

        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = controllerHelper
            .getPositionUpdatesToOpen(position, 1800);

        controller.updatePosition(0, positionUpdates, (buffer0 * 150) / 100, (buffer1 * 150) / 100);
    }

    function testBorrowLPT(uint256 _swapAmount) public {
        vm.assume(1e16 <= _swapAmount && _swapAmount < 5 * 1e18);

        slip(owner, true, _swapAmount);

        uint256 margin = 100 * 1e6;

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(margin, 1e18, 0, 0, lpts);

        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = controllerHelper
            .getPositionUpdatesToOpen(position, 1800);

        uint256 vaultId = controller.updatePosition(0, positionUpdates, buffer0, (buffer1 * 105) / 100);

        (uint256 collateralValue, uint256 debtValue) = controller.getVaultStatus(vaultId);

        assertGt(collateralValue, 0);
        assertGt(debtValue, 0);
    }

    function testWithdrawLPT(uint256 _swapAmount) public {
        vm.assume(1e16 <= _swapAmount && _swapAmount < 5 * 1e18);

        uint256 vaultId = depositLPT(0, 202500, 202600, 1e18);
        borrowLPT(0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        slip(owner, true, _swapAmount);

        vm.warp(block.timestamp + 5 minutes);

        DataType.Position memory position = controller.getPosition(vaultId);

        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = controllerHelper
            .getPositionUpdatesToClose(position, 1800, 100);

        controller.updatePosition(vaultId, positionUpdates, buffer0, buffer1);

        (uint256 collateralValue, uint256 debtValue) = controller.getVaultStatus(vaultId);

        assertEq(collateralValue, 0);
        assertEq(debtValue, 0);
    }

    function testRepayLPT() public {
        uint256 vaultId = borrowLPT(0, 202600, 202500, 202600, 1e18, 100 * 1e6);

        swapToSamePrice(owner);

        vm.warp(block.timestamp + 5 minutes);

        DataType.Position memory position = controller.getPosition(vaultId);

        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = controllerHelper
            .getPositionUpdatesToClose(position, 1200, 55);

        controller.updatePosition(vaultId, positionUpdates, buffer0, buffer1);

        (uint256 collateralValue, uint256 debtValue) = controller.getVaultStatus(vaultId);

        assertEq(collateralValue, 0);
        assertEq(debtValue, 0);
    }
}
