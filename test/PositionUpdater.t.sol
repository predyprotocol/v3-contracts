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
    DataType.Vault private vault4;
    DataType.Vault private vault5;

    mapping(bytes32 => DataType.PerpStatus) private ranges;

    DataType.TradeOption private tradeOption;

    function setUp() public {
        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(address(this), factory);
        vm.warp(block.timestamp + 1 minutes);

        context = getContext();
        tradeOption = DataType.TradeOption(false, false, false, context.isMarginZero, -1, -1, EMPTY_METADATA);

        // vault1 is empty
        // vault2 has deposited token
        // vault3 has borrowed token
        // vault4 has deposited token with compound option
        // vault5 has borrowed token with compound option
        depositToken(vault2, context, ranges, 2 * 1e6, 2 * 1e18, false);
        borrowToken(vault3, context, ranges, 1e6, 1e18, false, 100 * 1e6);
        depositToken(vault4, context, ranges, 2 * 1e6, 2 * 1e18, true);
        borrowToken(vault5, context, ranges, 1e6, 1e18, true, -1);
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

        assertEq(subVaults[vault1.subVaults[0]].assetAmount0, 1e6);
        assertEq(subVaults[vault1.subVaults[0]].assetAmount1, 1e18);
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

        assertEq(subVaults[vault1.subVaults[0]].assetAmount0, 0);
        assertEq(subVaults[vault1.subVaults[0]].assetAmount1, 0);
        assertEq(BaseToken.getAssetValue(context.tokenState0, subVaults[vault1.subVaults[0]].balance0), 1e6);
        assertEq(BaseToken.getAssetValue(context.tokenState1, subVaults[vault1.subVaults[0]].balance1), 1e18);
    }

    function testUpdatePositionWithdrawToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            0,
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
            0,
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

        assertEq(subVaults[vault1.subVaults[0]].debtAmount0, 0);
        assertEq(subVaults[vault1.subVaults[0]].debtAmount1, 1e18);
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

        assertEq(subVaults[vault1.subVaults[0]].debtAmount0, 0);
        assertEq(subVaults[vault1.subVaults[0]].debtAmount1, 0);
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
            DataType.TradeOption(false, false, false, context.isMarginZero, 1e8, -1, EMPTY_METADATA)
        );

        assertEq(subVaults[vault1.subVaults[0]].debtAmount0, 0);
        assertEq(subVaults[vault1.subVaults[0]].debtAmount1, 1e18);
        assertEq(vault1.marginAmount0, 1e8);
    }

    function testUpdatePositionRepayToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_TOKEN,
            0,
            false,
            0,
            0,
            0,
            1e6,
            1e18
        );

        PositionUpdater.updatePosition(vault3, subVaults, context, ranges, positionUpdates, tradeOption);

        assertEq(vault3.subVaults.length, 0);
    }

    function testUpdatePositionRepayTokenWithCompound() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_TOKEN,
            0,
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
        depositToken(vault3, context, ranges, 1e6, 1e18, false);

        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](2);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            0,
            false,
            0,
            0,
            0,
            1e6,
            1e18
        );

        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_TOKEN,
            0,
            false,
            0,
            0,
            0,
            1e6,
            1e18
        );

        // test interest rate
        BaseToken.updateScaler(context.tokenState0, 1e15);
        BaseToken.updateScaler(context.tokenState1, 1e15);

        PositionUpdater.updatePosition(
            vault3,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(false, true, false, context.isMarginZero, -2, -1, EMPTY_METADATA)
        );

        assertEq(vault3.subVaults.length, 0);
        // margin must be less than 1e8 because vault paid interest.
        assertLt(vault3.marginAmount0, 1e8);
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
            DataType.TradeOption(false, true, false, context.isMarginZero, -1, -1, EMPTY_METADATA)
        );

        assertEq(vault1.marginAmount0, 0);
        assertEq(vault1.marginAmount1, 0);
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
                int256(_marginAmount0),
                int256(_marginAmount1),
                EMPTY_METADATA
            )
        );

        assertEq(vault1.marginAmount0, _marginAmount0);
        assertEq(vault1.marginAmount1, _marginAmount1);
    }

    function testUpdatePositionWithdrawMargin() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        assertEq(vault3.marginAmount0, 100 * 1e6);
        assertEq(vault3.marginAmount1, 0);

        PositionUpdater.updatePosition(
            vault3,
            subVaults,
            context,
            ranges,
            positionUpdates,
            DataType.TradeOption(false, true, false, context.isMarginZero, 90 * 1e6, -1, EMPTY_METADATA)
        );

        assertEq(vault3.marginAmount0, 90 * 1e6);
        assertEq(vault3.marginAmount1, 0);
    }

    function testDepositTokenFromMargin(uint256 _marginAmount0, uint256 _marginAmount1) public {
        vm.assume(_marginAmount0 <= Constants.MAX_MARGIN_AMOUNT);
        vm.assume(_marginAmount1 <= Constants.MAX_MARGIN_AMOUNT);

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
                    int256(_marginAmount0),
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
                    EMPTY_METADATA
                )
            );
        }

        assertEq(vault1.marginAmount0, 0);
        assertEq(vault1.marginAmount1, 0);
    }

    /**************************
     *   Test: swapAnyway     *
     **************************/

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
