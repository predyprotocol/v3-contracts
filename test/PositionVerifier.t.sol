// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PositionVerifier.sol";
import "../src/libraries/BorrowLPTLib.sol";
import "../src/libraries/LPTMath.sol";

contract PositionVerifierTest is Test {
    function testVerify() public {
        (PositionVerifier.Position memory position, PositionVerifier.Proof[] memory proofs) = BorrowLPTLib
            .createPositionAndProof(true, 10000000000, 100000, 400000, 100000);

        assertTrue(PositionVerifier.verifyPosition(position, proofs, true, 0));
    }

    function testVerify2(uint128 ethAmount) public {
        vm.assume(ethAmount >= 1e8);

        int24 lower = 202500;
        int24 upper = 202600;

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](1);

        (uint128 liquidity, uint256 amount0, uint256 amount1) = LPTMath.getLiquidityAndAmount(
            0,
            ethAmount,
            TickMath.getSqrtRatioAtTick(upper),
            TickMath.getSqrtRatioAtTick(upper),
            lower,
            upper
        );

        lpts[0] = PositionVerifier.LPT(false, liquidity, lower, upper);

        PositionVerifier.Position memory position = PositionVerifier.Position(amount0, amount1, 0, 0, lpts);

        PositionVerifier.Proof[] memory proofs = PositionVerifier.generateProof(position, true);

        assertTrue(PositionVerifier.verifyPosition(position, proofs, true, 0));
    }

    function testVerify3(uint128 liquidity) public {
        vm.assume(liquidity >= 1e12);
        vm.assume(liquidity <= type(uint128).max);

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](1);
        lpts[0] = PositionVerifier.LPT(false, liquidity, 202500, 202600);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(lpts[0].lowerTick),
            TickMath.getSqrtRatioAtTick(lpts[0].lowerTick),
            TickMath.getSqrtRatioAtTick(lpts[0].upperTick),
            lpts[0].liquidity
        );

        PositionVerifier.Position memory position = PositionVerifier.Position(amount0, amount1, 0, 0, lpts);

        PositionVerifier.Proof[] memory proofs = PositionVerifier.generateProof(position, true);

        assertTrue(PositionVerifier.verifyPosition(position, proofs, true, 0));
    }

    function testGenerateProof(uint256 ethAmount, bool isMarginZero) public {
        vm.assume(ethAmount >= 1e8);
        vm.assume(ethAmount <= type(uint128).max);

        int24 lower = 202500;
        int24 upper = 202600;

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](1);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            ethAmount
        );

        lpts[0] = PositionVerifier.LPT(false, liquidity, lower, upper);

        PositionVerifier.Position memory position = PositionVerifier.Position(0, ethAmount, 0, 0, lpts);

        PositionVerifier.Proof[] memory proofs = PositionVerifier.generateProof(position, isMarginZero);

        assertEq(proofs[0].tick, upper);
    }

    function testGenerateProofLower(uint256 usdcAmount) public {
        vm.assume(usdcAmount >= 1e6);
        vm.assume(usdcAmount <= type(uint96).max);

        int24 lower = 202500;
        int24 upper = 202600;

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](1);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            usdcAmount
        );

        lpts[0] = PositionVerifier.LPT(false, liquidity, lower, upper);

        PositionVerifier.Position memory position = PositionVerifier.Position(usdcAmount, 0, 0, 0, lpts);

        PositionVerifier.Proof[] memory proofs = PositionVerifier.generateProof(position, true);

        assertEq(proofs[0].tick, lower);
    }
}
