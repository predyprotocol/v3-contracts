// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/TestDeployer.sol";
import "../src/Controller.sol";
import "../src/mocks/MockERC20.sol";

contract ReaderTest is TestDeployer, Test {
    address owner;
    bool isQuoteZero;

    uint256 private vaultId1;
    uint256 private vaultId2;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        vaultId1 = depositToken(0, 1e10, 5 * 1e18);
        vaultId2 = depositLPT(0, 0, 202500, 202600, 2 * 1e18);

        isQuoteZero = getIsMarginZero();
    }

    function createPositionForDepositLPT() internal view returns (DataType.Position memory position) {
        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(true, 1e18, controller.getSqrtPrice(), 202560, 202570);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(true, liquidity, 202560, 202570);
        return DataType.Position(0, 0, 0, 0, 0, lpts);
    }

    /***************************
     * Test: quoteOpenPosition *
     ***************************/

    function testCannotQuoteOpenPositionOfNewVault() public {
        DataType.Position memory position = createPositionForDepositLPT();

        uint160 lowerSqrtPrice = getLowerSqrtPrice();
        uint160 upperSqrtPrice = getUpperSqrtPrice();

        vm.expectRevert();
        reader.quoteOpenPosition(
            0,
            position,
            DataType.TradeOption(
                false,
                true,
                true,
                isQuoteZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(lowerSqrtPrice, upperSqrtPrice, 100, block.timestamp)
        );
    }

    function testQuoteOpenPosition() public {
        DataType.Position memory position = createPositionForDepositLPT();

        DataType.PositionUpdateResult memory result = reader.quoteOpenPosition(
            vaultId1,
            position,
            DataType.TradeOption(
                false,
                true,
                true,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );

        assertGt(result.requiredAmounts.amount0, 0);
    }
}
