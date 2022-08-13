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
    ControllerHelper private controllerHelper;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        controllerHelper = new ControllerHelper(controller);

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

        controller.updatePosition(0, positionUpdates, buffer0, buffer1);
    }

    function testBorrowLPT() public {
        uint256 margin = 100 * 1e6;

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, 202500, 202600);
        DataType.Position memory position = DataType.Position(margin, 1e18, 0, 0, lpts);

        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = controllerHelper
            .getPositionUpdatesToOpen(position, 1800);

        controller.updatePosition(0, positionUpdates, buffer0, (buffer1 * 105) / 100);
    }
}
