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

        (liquidity, buffer0, buffer1) = LPTMath.getLiquidityAndAmountToDeposit(
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

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, 1e18, 202600, 202500, 202600);

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
            0,
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
            0,
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

    /**************************
     *  Test: updatePosition  *
     **************************/

    function testDepositLPT() public {
        (
            DataType.PositionUpdate[] memory positionUpdates,
            uint256 amount0,
            uint256 amount1
        ) = createPositionUpdatesForDepositLPT();

        controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA)
        );
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
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA)
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(lpVaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }

    function testBorrowLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        (uint256 vaultId, , ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, getIsMarginZero(), int256(margin), -1, EMPTY_METADATA)
        );

        vm.warp(block.timestamp + 1 minutes);

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertGt(vaultStatus.subVaults[0].values.assetValue, 0);
        assertGt(vaultStatus.subVaults[0].values.debtValue, 0);
    }

    function testCannotBorrowLPT() public {
        uint256 margin = 0;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        // no enough deposit
        vm.expectRevert(bytes("P3"));
        controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, isQuoteZero, -1, -1, EMPTY_METADATA)
        );
    }

    function testRepayLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        (uint256 vaultId, , ) = controller.updatePosition(
            0,
            positionUpdates,
            DataType.TradeOption(false, false, false, getIsMarginZero(), int256(margin), -1, EMPTY_METADATA)
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
            DataType.TradeOption(false, false, false, getIsMarginZero(), -1, -1, EMPTY_METADATA)
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.subVaults.length, 0);
    }
}
