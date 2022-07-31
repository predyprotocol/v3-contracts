// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PositionVerifier.sol";
import "../src/libraries/ProofGenerator.sol";


contract PositionVerifierTest is Test {

    function testVerify() public {
        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](1);
        lpts[0] = PositionVerifier.LPT(false, 10000000000, 100000, 400000);

        PositionVerifier.Proof[] memory proofs = new PositionVerifier.Proof[](1);

        PositionVerifier.Position memory position = PositionVerifier.Position(
            0,
            0,
            0,
            0,
            lpts
        );

        (position.collateral0, position.collateral1, proofs[0]) = ProofGenerator.generateProof(lpts[0], 400000);

        assertTrue(PositionVerifier.verifyPosition(position, proofs));
    }

}
