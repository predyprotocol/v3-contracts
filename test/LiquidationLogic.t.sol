// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "../src/libraries/logic/LiquidationLogic.sol";

contract LiquidationLogicTest is Test {
    function getPositionParams(
        int256 _marginAmount0,
        int256 _marginAmount1,
        uint256 _assetAmount0,
        uint256 _debtAmount0
    ) internal pure returns (PositionCalculator.PositionCalculatorParams memory) {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        return
            PositionCalculator.PositionCalculatorParams(
                _marginAmount0,
                _marginAmount1,
                _assetAmount0,
                0,
                _debtAmount0,
                0,
                lpts
            );
    }

    // The vault is safe if debt is zero
    function testIsVaultSafeTrueIfDebtIsZero(uint256 _margin, uint256 _sqrtPrice) public {
        int256 margin = int256(bound(_margin, 0, 2 * 1e8)) - 1e8;
        uint256 sqrtPrice = bound(_sqrtPrice, Constants.MIN_SQRT_PRICE, Constants.MAX_SQRT_PRICE);

        assertTrue(LiquidationLogic._isVaultSafe(true, getPositionParams(margin, 0, 0, 0), uint160(sqrtPrice)));
    }

    // The vault is not safe if margin is negative value
    function testIsVaultSafeFalseIfMarginIsNegative(uint256 _sqrtPrice) public {
        uint256 sqrtPrice = bound(_sqrtPrice, Constants.MIN_SQRT_PRICE, Constants.MAX_SQRT_PRICE);

        assertFalse(LiquidationLogic._isVaultSafe(true, getPositionParams(-10, 0, 500, 100), uint160(sqrtPrice)));
    }

    // The vault is safe if vault value > min vault value
    function testIsVaultSafeTrue(uint256 _sqrtPrice) public {
        uint256 sqrtPrice = bound(_sqrtPrice, Constants.MIN_SQRT_PRICE, Constants.MAX_SQRT_PRICE);

        assertFalse(LiquidationLogic._isVaultSafe(true, getPositionParams(0, 0, 500, 100), uint160(sqrtPrice)));
    }

    function testCalculateLiquidationSlippageTolerance() public {
        assertEq(
            LiquidationLogic.calculateLiquidationSlippageTolerance(1e6),
            Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE
        );
        assertEq(
            LiquidationLogic.calculateLiquidationSlippageTolerance(100000 * 1e6),
            Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE
        );
        assertEq(LiquidationLogic.calculateLiquidationSlippageTolerance(500000 * 1e6), 16556);
        assertEq(LiquidationLogic.calculateLiquidationSlippageTolerance(1000000 * 1e6), 23000);
    }

    function testCalculatePenaltyAmount() public {
        assertEq(LiquidationLogic.calculatePenaltyAmount(10 * 1e6), Constants.MIN_PENALTY);

        assertEq(LiquidationLogic.calculatePenaltyAmount(1000 * 1e6), 4 * 1e6);

        assertEq(LiquidationLogic.calculatePenaltyAmount(1000 * 1e6 + 100), 4 * 1e6);
    }
}
