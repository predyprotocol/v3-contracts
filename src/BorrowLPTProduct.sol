// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./libraries/PositionVerifier.sol";
import "./libraries/BorrowLPTLib.sol";

contract BorrowLPTProduct {
    bool private isMarginZero;

    constructor(bool _isMarginZero) {
        isMarginZero = _isMarginZero;
    }

    function createPositionAndProof(
        uint256 requestedAmount,
        int24 lower,
        int24 upper,
        int24 tick
    ) external view returns (PositionVerifier.Position memory position, PositionVerifier.Proof[] memory proofs) {
        return BorrowLPTLib.createPositionAndProof(isMarginZero, requestedAmount, lower, upper, tick);
    }
}
