// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/TestDeployer.sol";
import "../src/Controller.sol";
import "../src/mocks/MockERC20.sol";

contract ControllerTest is TestDeployer, Test {
    address owner;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        depositLPT(
            0,
            202500,
            202600,
            2 * 1e18
        );
    }


    function testDepositLPT() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        (uint128 liquidity,
        uint256 amount0,
        uint256 amount1) = LPTMath.getLiquidityAndAmountToDeposit(
            true,
            1e18,
            controller.getSqrtPrice(),
            202560,
            202570
        );
        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            false,
            liquidity,
            202560,
            202570,
            0,
            0
        );

        controller.updatePosition(0, positionUpdates, amount0*2, amount1*2);
    }

    function testBorrowLPT() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](3);
        uint256 margin = 100 * 1e6;

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(
            true,
            1e18,
            202600,
            202500,
            202600
        );

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_LPT,
            false,
            liquidity,
            202500,
            202600,
            0,
            0
        );
        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            false,
            0,
            0,
            0,
            margin,
            1e18
        );
        positionUpdates[2] = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_OUT,
            true,
            0,
            0,
            0,
            1e18,
            1e18 * 1800 / 1e12
        );

        controller.updatePosition(0, positionUpdates, 1e18 * 1800 / 1e12, margin);
    }

}
