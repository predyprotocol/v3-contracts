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

    uint256 private lpVaultId;
    bool isQuoteZero;

    // expected events
    event FeeCollected(uint256 vaultId, int256 feeAmount0, int256 feeAmount1);

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        depositToken(0, 2000 * 1e6, 1e18);
        lpVaultId = depositLPT(0, 202500, 202600, 2 * 1e18);

        isQuoteZero = controller.getIsMarginZero();
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
        view
        returns (DataType.PositionUpdate[] memory positionUpdates)
    {
        positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_LPT,
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
            _margin,
            1e18
        );
        positionUpdates[2] = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_OUT,
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
            false,
            0,
            0,
            0,
            _margin,
            1e18
        );

        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.SWAP_EXACT_IN,
            false,
            0,
            0,
            0,
            _ethAmountToSwap,
            (_ethAmountToSwap * 1200) / 1e12
        );

        positionUpdates[2] = DataType.PositionUpdate(
            DataType.PositionUpdateType.REPAY_LPT,
            false,
            _liquidity,
            202500,
            202600,
            0,
            0
        );
    }

    // Tests

    function testCannotDepositLPTByNoEnoughAmount0() public {
        (DataType.PositionUpdate[] memory positionUpdates, , uint256 amount1) = createPositionUpdatesForDepositLPT();

        vm.expectRevert(bytes("P5"));
        controller.updatePosition(
            0,
            positionUpdates,
            0,
            amount1 * 2,
            DataType.TradeOption(false, false, false, isQuoteZero),
            bytes("")
        );
    }

    function testCannotDepositLPTByNoEnoughAmount1() public {
        (DataType.PositionUpdate[] memory positionUpdates, uint256 amount0, ) = createPositionUpdatesForDepositLPT();

        vm.expectRevert(bytes("P6"));
        controller.updatePosition(
            0,
            positionUpdates,
            amount0 * 2,
            0,
            DataType.TradeOption(false, false, false, isQuoteZero),
            bytes("")
        );
    }

    function testDepositLPT() public {
        (
            DataType.PositionUpdate[] memory positionUpdates,
            uint256 amount0,
            uint256 amount1
        ) = createPositionUpdatesForDepositLPT();

        controller.updatePosition(
            0,
            positionUpdates,
            amount0 * 2,
            amount1 * 2,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            bytes("")
        );
    }

    function testWithdrawLPT() public {
        swapToSamePrice(owner);

        DataType.Vault memory vault = controller.getVault(lpVaultId);

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForWithdrawLPT(
            vault.lpts[0].liquidityAmount
        );

        // expect fee collected event
        // vm.expectEmit(true, false, false, false);
        // emit FeeCollected(lpVaultId, 0, 0);

        // execute transaction
        controller.updatePosition(
            lpVaultId,
            positionUpdates,
            0,
            0,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            bytes("")
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(lpVaultId);

        assertGt(vaultStatus.values.collateralValue, 0);
        assertEq(vaultStatus.values.debtValue, 0);
    }

    function testBorrowLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        uint256 vaultId = controller.updatePosition(
            0,
            positionUpdates,
            (1e18 * 1800) / 1e12,
            margin,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            bytes("")
        );

        vm.warp(block.timestamp + 1 minutes);

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertGt(vaultStatus.values.collateralValue, 0);
        assertGt(vaultStatus.values.debtValue, 0);
    }

    function testCannotBorrowLPT() public {
        uint256 margin = 0;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        // no enough collateral
        vm.expectRevert(bytes("P3"));
        controller.updatePosition(
            0,
            positionUpdates,
            (1e18 * 1800) / 1e12,
            margin,
            DataType.TradeOption(false, false, false, isQuoteZero),
            bytes("")
        );
    }

    function testRepayLPT() public {
        uint256 margin = 100 * 1e6;

        DataType.PositionUpdate[] memory positionUpdates = createPositionUpdatesForBorrowLPT(margin);

        uint256 vaultId = controller.updatePosition(
            0,
            positionUpdates,
            (1e18 * 1800) / 1e12,
            margin,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            bytes("")
        );

        DataType.Vault memory vault = controller.getVault(vaultId);

        DataType.PositionUpdate[] memory positionUpdates2 = createPositionUpdatesForRepayLPT(
            vault.lpts[0].liquidityAmount,
            margin,
            62 * 1e16
        );

        controller.updatePosition(
            vaultId,
            positionUpdates2,
            0,
            0,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            bytes("")
        );

        DataType.VaultStatus memory vaultStatus = controller.getVaultStatus(vaultId);

        assertEq(vaultStatus.values.collateralValue, 0);
        assertEq(vaultStatus.values.debtValue, 0);
    }
}
