// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../src/libraries/PositionUpdater.sol";
import "./utils/TestDeployer.sol";

contract PositionUpdaterTest is TestDeployer, Test {
    address owner;

    DataType.Context private context;

    DataType.Vault private vault1;
    DataType.Vault private vault2;
    DataType.Vault private vault3;

    mapping(bytes32 => DataType.PerpStatus) private ranges;

    DataType.TradeOption tradeOption;

    function setUp() public {
        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(address(this), factory);
        vm.warp(block.timestamp + 1 minutes);

        context = getContext();
        tradeOption = DataType.TradeOption(false, false, false, context.isMarginZero);

        // vault1 is empty
        // vault2 has deposited token
        // vault3 has borrowed token
        depositToken(vault2, context, ranges, 2 * 1e6, 2 * 1e18);
        borrowToken(vault3, context, ranges, 1e6, 1e18);
    }

    function testUpdatePosition() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);
        PositionUpdater.updatePosition(vault1, context, ranges, positionUpdates, tradeOption);
    }

    function testUpdatePositionDepositToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            false,
            0,
            0,
            0,
            1e6,
            1e18
        );

        PositionUpdater.updatePosition(vault1, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getCollateralValue(context.tokenState0, vault1.balance0), 1e6);
        assertEq(BaseToken.getCollateralValue(context.tokenState1, vault1.balance1), 1e18);
    }

    function testUpdatePositionWithdrawToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            false,
            0,
            0,
            0,
            2 * 1e6,
            2 * 1e18
        );

        PositionUpdater.updatePosition(vault2, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getCollateralValue(context.tokenState0, vault2.balance0), 0);
        assertEq(BaseToken.getCollateralValue(context.tokenState1, vault2.balance1), 0);
    }

    function testUpdatePositionBorrowToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(DataType.PositionUpdateType.BORROW_TOKEN, false, 0, 0, 0, 0, 1e18);

        PositionUpdater.updatePosition(vault1, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getDebtValue(context.tokenState0, vault1.balance0), 0);
        assertEq(BaseToken.getDebtValue(context.tokenState1, vault1.balance1), 1e18);
    }

    function testUpdatePositionRepayToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_TOKEN,
            false,
            0,
            0,
            0,
            1e6,
            1e18
        );

        PositionUpdater.updatePosition(vault3, context, ranges, positionUpdates, tradeOption);

        assertEq(BaseToken.getDebtValue(context.tokenState0, vault3.balance0), 0);
        assertEq(BaseToken.getDebtValue(context.tokenState1, vault3.balance1), 0);
    }

    function testUpdatePositionDepositLPT() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            false,
            1000000000000,
            202560,
            202570,
            0,
            0
        );

        PositionUpdater.updatePosition(vault1, context, ranges, positionUpdates, tradeOption);

        assertEq(vault1.lpts.length, 1);
    }

    function testSwapAnywayETHRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 < 0);
        vm.assume(requiredAmount1 > 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_OUT));
        assertEq(positionUpdate.zeroForOne, true);
        assertEq(positionUpdate.param0, uint256(requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }

    function testSwapAnywayUSDCRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 > 0);
        vm.assume(requiredAmount1 < 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_IN));
        assertEq(positionUpdate.zeroForOne, false);
        assertEq(positionUpdate.param0, uint256(-requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }

    function testSwapAnywayNoRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 < 0);
        vm.assume(requiredAmount1 < 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_IN));
        assertEq(positionUpdate.zeroForOne, false);
        assertEq(positionUpdate.param0, uint256(-requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }

    function testSwapAnywayBothRequired(int256 requiredAmount0, int256 requiredAmount1) public {
        vm.assume(requiredAmount0 > 0);
        vm.assume(requiredAmount1 > 0);

        DataType.PositionUpdate memory positionUpdate = PositionUpdater.swapAnyway(
            requiredAmount0,
            requiredAmount1,
            context.isMarginZero
        );

        assertEq(uint256(positionUpdate.positionUpdateType), uint256(DataType.PositionUpdateType.SWAP_EXACT_OUT));
        assertEq(positionUpdate.zeroForOne, true);
        assertEq(positionUpdate.param0, uint256(requiredAmount1));
        assertEq(positionUpdate.param1, 0);
    }
}
