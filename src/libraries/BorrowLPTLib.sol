// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "../libraries/PositionVerifier.sol";

library BorrowLPTLib {
    function createPositionAndProof(
        bool isMarginZero,
        uint256 requestedAmount,
        int24 lower,
        int24 upper,
        int24 tick
    ) external view returns (PositionVerifier.Position memory position, PositionVerifier.Proof[] memory proofs) {
        (uint128 liquidity, uint256 amount0, uint256 amount1) = PositionVerifier.getLiquidityAndAmount(
            isMarginZero,
            requestedAmount,
            tick,
            lower,
            upper
        );

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](1);

        lpts[0] = PositionVerifier.LPT(false, liquidity, lower, upper);

        proofs = new PositionVerifier.Proof[](1);

        position = PositionVerifier.Position(amount0, amount1, 0, 0, lpts);

        proofs[0] = PositionVerifier.Proof(true, true, tick);
    }
}
