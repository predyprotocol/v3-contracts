// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./Setup.t.sol";
import "../../src/Controller.sol";
import "../../src/mocks/MockERC20.sol";

contract ControllerUpdatePositionTest is TestController {
    function setUp() public override {
        TestController.setUp();
    }

    // Helper Functions

    function createPositionUpdatesForDepositLPT()
        internal
        view
        returns (
            DataType.PositionUpdate[] memory positionUpdates,
            uint256 buffer0,
            uint256 buffer1
        )
    {
        positionUpdates = new DataType.PositionUpdate[](1);

        uint128 liquidity;

        (liquidity, buffer0, buffer1) = getLiquidityAndAmountToDeposit(
            true,
            1e18,
            controller.getSqrtPrice(),
            202560,
            202570
        );
        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            0,
            false,
            liquidity,
            202560,
            202570,
            0,
            0
        );
    }

    function createPositionUpdatesForWithdrawLPT(uint256 _subVaultId, uint128 _liquidity)
        internal
        pure
        returns (DataType.PositionUpdate[] memory positionUpdates)
    {
        positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_LPT,
            _subVaultId,
            false,
            _liquidity,
            202500,
            202600,
            0,
            0
        );
    }

    function createPositionUpdatesForBorrowLPT(uint256 _margin)
        internal
        pure
        returns (DataType.PositionUpdate[] memory positionUpdates)
    {
        positionUpdates = new DataType.PositionUpdate[](3);

        (uint128 liquidity, , ) = getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_LPT,
            0,
            false,
            liquidity,
            202500,
            202600,
            0,
            0
        );
        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            0,
            false,
            0,
            0,
            0,
            _margin,
            1e18
        );
        positionUpdates[2] = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_OUT,
            0,
            true,
            500,
            0,
            0,
            1e18,
            (1e18 * 1800) / 1e12
        );
    }

    function createPositionUpdatesForRepayLPT(
        uint256 _subVaultId,
        uint128 _liquidity,
        uint256 _margin,
        uint256 _ethAmountToSwap
    ) internal pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](3);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            _subVaultId,
            false,
            0,
            0,
            0,
            _margin,
            1e18
        );

        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_IN,
            0,
            false,
            500,
            0,
            0,
            _ethAmountToSwap,
            (_ethAmountToSwap * 1200) / 1e12
        );

        positionUpdates[2] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_LPT,
            _subVaultId,
            false,
            _liquidity,
            202500,
            202600,
            0,
            0
        );
    }

    function getOpenPositionParams() internal view returns (DataType.OpenPositionOption memory) {
        return DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp);
    }

    /**************************
     *  Test: updatePosition  *
     **************************/

    function testCannotUpdatePositionBecauseVaultIdDoesNotExists() public {
        (DataType.PositionUpdate[] memory positionUpdates, , ) = createPositionUpdatesForDepositLPT();

        bool isMarginZero = getIsMarginZero();

        DataType.OpenPositionOption memory openPositionOption = getOpenPositionParams();

        vm.expectRevert(bytes("P2"));
        controller.updatePosition(
            1000,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                isMarginZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            openPositionOption
        );
    }

    function testCannotCreateVault() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        bool isMarginZero = getIsMarginZero();

        DataType.OpenPositionOption memory openPositionOption = getOpenPositionParams();

        vm.expectRevert(bytes("P4"));
        controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                isMarginZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            openPositionOption
        );
    }

    function testDepositAndWithdrawMargin0(uint256 _marginAmount) public {
        int256 marginAmount = int256(bound(_marginAmount, 0, 1e10));

        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        uint256 beforeBalance0 = token0.balanceOf(user);

        (uint256 vaultId, DataType.TokenAmounts memory addedAmounts, ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                true,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                1e10,
                0,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );

        uint256 middleBalance0 = token0.balanceOf(user);

        assertEq(addedAmounts.amount0, 1e10);
        assertEq(beforeBalance0 - middleBalance0, 1e10);

        (, DataType.TokenAmounts memory removedAmounts, ) = controller.updatePosition(
            vaultId,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                true,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                -marginAmount,
                0,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );
        uint256 afterBalance0 = token0.balanceOf(user);

        assertEq(removedAmounts.amount0, -marginAmount);
        assertEq(afterBalance0 - middleBalance0, uint256(marginAmount));
    }

    function testDepositAndWithdrawMargin1(uint256 _marginAmount) public {
        int256 marginAmount = int256(bound(_marginAmount, 0, 1e10));

        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        uint256 beforeBalance1 = token1.balanceOf(user);

        (uint256 vaultId, DataType.TokenAmounts memory addedAmounts, ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                false,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                Constants.MIN_MARGIN_AMOUNT,
                1e10,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );

        uint256 middleBalance1 = token1.balanceOf(user);

        assertEq(addedAmounts.amount1, 1e10);
        assertEq(beforeBalance1 - middleBalance1, 1e10);

        (, DataType.TokenAmounts memory removedAmounts, ) = controller.updatePosition(
            vaultId,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                false,
                Constants.MARGIN_STAY,
                Constants.MARGIN_USE,
                0,
                -marginAmount,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );
        uint256 afterBalance1 = token1.balanceOf(user);

        assertEq(removedAmounts.amount1, -marginAmount);
        assertEq(afterBalance1 - middleBalance1, uint256(marginAmount));
    }

    function testDepositLPT() public {
        (DataType.PositionUpdate[] memory positionUpdates, , ) = createPositionUpdatesForDepositLPT();

        controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );
    }

    function testDepositLPTOnExistentVault() public {
        (DataType.PositionUpdate[] memory positionUpdates, , ) = createPositionUpdatesForDepositLPT();

        DataType.Vault memory vault = controller.getVault(vaultId2);
        positionUpdates[0].subVaultId = vault.subVaults[0];

        controller.updatePosition(
            vaultId2,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );

        DataType.SubVault memory subVault = controller.getSubVault(vault.subVaults[0]);

        assertEq(controller.getVault(vaultId2).subVaults.length, 1);
        assertEq(subVault.lpts.length, 2);
    }

    function testWithdrawLPT() public {
        swapToSamePrice(user);

        DataType.Vault memory vault = controller.getVault(vaultId2);
        DataType.SubVault memory subVault = controller.getSubVault(vault.subVaults[0]);

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForWithdrawLPT(
            subVault.id,
            subVault.lpts[0].liquidityAmount
        );

        // execute transaction
        controller.updatePosition(
            vaultId2,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );

        DataType.Vault memory vaultAfter = controller.getVault(vaultId2);

        assertEq(vaultAfter.subVaults.length, 0);
    }

    function testBorrowLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        (uint256 vaultId, , ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                int256(margin),
                0,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );

        vm.warp(block.timestamp + 1 minutes);
        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertGt(vaultStatus.subVaults[0].values.assetValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);
    }

    function testCannotBorrowLPT() public {
        uint256 margin = 0;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        DataType.OpenPositionOption memory openPositionOption = getOpenPositionParams();

        // no enough deposit
        vm.expectRevert(bytes("UPL0"));
        controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                isQuoteZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            openPositionOption
        );
    }

    function testRepayLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        (uint256 vaultId, , ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                int256(margin),
                0,
                EMPTY_METADATA
            ),
            getOpenPositionParams()
        );

        DataType.Vault memory vault = controller.getVault(vaultId);
        DataType.SubVault memory subVault = controller.getSubVault(vault.subVaults[0]);

        DataType.PositionUpdate[] memory positionUpdates2 = createPositionUpdatesForRepayLPT(
            subVault.id,
            subVault.lpts[0].liquidityAmount,
            margin,
            62 * 1e16
        );

        controller.updatePosition(
            vaultId,
            positionUpdates2,
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
            getOpenPositionParams()
        );

        DataType.Vault memory vaultAfter = controller.getVault(vaultId);

        assertEq(vaultAfter.subVaults.length, 0);
    }

    function testUpdatePositionMarginBecomesNegative() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_TOKEN,
            0,
            false,
            0,
            0,
            0,
            100 * 1e6,
            0
        );

        bool isMarginZero = getIsMarginZero();

        DataType.OpenPositionOption memory openPositionOption = getOpenPositionParams();

        (uint256 vaultId, , ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                200 * 1e6,
                0,
                EMPTY_METADATA
            ),
            openPositionOption
        );

        DataType.ClosePositionOption memory closePositionOption = DataType.ClosePositionOption(
            getLowerSqrtPrice(),
            getUpperSqrtPrice(),
            100,
            100,
            block.timestamp
        );

        vm.expectRevert(bytes("PU2"));
        controller.closeVault(
            vaultId,
            DataType.TradeOption(
                false,
                true,
                false,
                !isMarginZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_USE,
                0,
                0,
                EMPTY_METADATA
            ),
            closePositionOption
        );
    }
}
