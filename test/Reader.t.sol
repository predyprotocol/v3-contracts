// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "./controller/Setup.t.sol";

contract ReaderTest is TestController {
    function setUp() public override {
        TestController.setUp();
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
