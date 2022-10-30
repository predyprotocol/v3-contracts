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
    address private user = vm.addr(uint256(1));

    uint256 private lpVaultId;
    bool private isQuoteZero;

    // expected events
    event FeeCollected(uint256 vaultId, int256 feeAmount0, int256 feeAmount1);

    function setUp() public {
        vm.startPrank(user);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(user, factory);
        vm.warp(block.timestamp + 1 minutes);

        depositToken(0, 2000 * 1e6, 5 * 1e18);
        lpVaultId = depositLPT(0, 0, 202500, 202600, 2 * 1e18);

        isQuoteZero = getIsMarginZero();
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

    function createPositionUpdatesForWithdrawLPT(uint128 _liquidity)
        internal
        pure
        returns (DataType.PositionUpdate[] memory positionUpdates)
    {
        positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_LPT,
            0,
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
        uint128 _liquidity,
        uint256 _margin,
        uint256 _ethAmountToSwap
    ) internal pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](3);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            0,
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
            0,
            false,
            _liquidity,
            202500,
            202600,
            0,
            0
        );
    }

    function getOpenPositionParams() internal returns (DataType.OpenPositionOption memory) {
        return DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp);
    }

    /**************************
     *  Test: updatePosition  *
     **************************/

    function testCannotUpdatePositionBecauseVaultIdDoesNotExists() public {
        (DataType.PositionUpdate[] memory positionUpdates, , ) = createPositionUpdatesForDepositLPT();

        bool isMarginZero = getIsMarginZero();

        DataType.OpenPositionOption memory openPositionOption = getOpenPositionParams();

        vm.expectRevert(bytes("P5"));
        controller.updatePosition(
            1000,
            positionUpdates,
            DataType.TradeOption(false, false, false, isMarginZero, -1, -1, EMPTY_METADATA),
            openPositionOption
        );
    }

    function testCannotCreateVault() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);

        bool isMarginZero = getIsMarginZero();

        DataType.OpenPositionOption memory openPositionOption = getOpenPositionParams();

        vm.expectRevert(bytes("P7"));
        controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, isMarginZero, -1, -1, EMPTY_METADATA),
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
            DataType.TradeOption(false, false, false, true, 1e10, -1, EMPTY_METADATA),
            getOpenPositionParams()
        );

        uint256 middleBalance0 = token0.balanceOf(user);

        assertEq(addedAmounts.amount0, 1e10);
        assertEq(beforeBalance0 - middleBalance0, 1e10);

        (, DataType.TokenAmounts memory removedAmounts, ) = controller.updatePosition(
            vaultId,
            positionUpdates,
            DataType.TradeOption(false, false, false, true, 1e10 - marginAmount, -1, EMPTY_METADATA),
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
            DataType.TradeOption(false, false, false, false, -1, 1e10, EMPTY_METADATA),
            getOpenPositionParams()
        );

        uint256 middleBalance1 = token1.balanceOf(user);

        assertEq(addedAmounts.amount1, 1e10);
        assertEq(beforeBalance1 - middleBalance1, 1e10);

        (, DataType.TokenAmounts memory removedAmounts, ) = controller.updatePosition(
            vaultId,
            positionUpdates,
            DataType.TradeOption(false, false, false, false, -1, 1e10 - marginAmount, EMPTY_METADATA),
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
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA),
            getOpenPositionParams()
        );
    }

    function testDepositLPTOnExistentVault() public {
        (DataType.PositionUpdate[] memory positionUpdates, , ) = createPositionUpdatesForDepositLPT();

        controller.updatePosition(
            lpVaultId,
            positionUpdates,
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA),
            getOpenPositionParams()
        );

        DataType.Vault memory vault = controller.getVault(lpVaultId);
        DataType.SubVault memory subVault = controller.getSubVault(vault.subVaults[0]);

        assertEq(subVault.lpts.length, 2);
    }

    function testWithdrawLPT() public {
        swapToSamePrice(user);

        DataType.Vault memory vault = controller.getVault(lpVaultId);
        DataType.SubVault memory subVault = controller.getSubVault(vault.subVaults[0]);

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForWithdrawLPT(
            subVault.lpts[0].liquidityAmount
        );

        // expect fee collected event
        // vm.expectEmit(true, false, false, false);
        // emit FeeCollected(lpVaultId, 0, 0);

        // execute transaction
        controller.updatePosition(
            lpVaultId,
            positionUpdates,
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA),
            getOpenPositionParams()
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(lpVaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testBorrowLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        (uint256 vaultId, , ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, getIsMarginZero(), int256(margin), -1, EMPTY_METADATA),
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
        vm.expectRevert(bytes("P3"));
        controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, isQuoteZero, -1, -1, EMPTY_METADATA),
            openPositionOption
        );
    }

    function testRepayLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        (uint256 vaultId, , ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, getIsMarginZero(), int256(margin), -1, EMPTY_METADATA),
            getOpenPositionParams()
        );

        DataType.Vault memory vault = controller.getVault(vaultId);
        DataType.SubVault memory subVault = controller.getSubVault(vault.subVaults[0]);

        DataType.PositionUpdate[] memory positionUpdates2 = createPositionUpdatesForRepayLPT(
            subVault.lpts[0].liquidityAmount,
            margin,
            62 * 1e16
        );

        controller.updatePosition(
            vaultId,
            positionUpdates2,
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA),
            getOpenPositionParams()
        );

        DataType.VaultStatus memory vaultStatus = getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }
}
