// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "v3-periphery/libraries/LiquidityAmounts.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "../libraries/PositionVerifier.sol";

library ProofGenerator {
    function generateProof(PositionVerifier.LPT memory debt, int24 tick) external pure returns(uint256 amount0, uint256 amount1, PositionVerifier.Proof memory proof) {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(tick),
            TickMath.getSqrtRatioAtTick(debt.lowerTick),
            TickMath.getSqrtRatioAtTick(debt.upperTick),
            debt.liquidity
        );

        proof = PositionVerifier.Proof(true, true, tick);
    }
}