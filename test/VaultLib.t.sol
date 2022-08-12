// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/LPTStateLib.sol";
import "../src/libraries/VaultLib.sol";

contract VaultLibTest is Test {
    DataType.Vault private vault;
    mapping(bytes32 => DataType.PerpStatus) private ranges;

    bytes32 private rangeId;

    function setUp() public {
        rangeId = LPTStateLib.getRangeKey(0, 10);
    }

    function testDepositLPT() public {
        VaultLib.depositLPT(vault, ranges, LPTStateLib.getRangeKey(0, 0), 0);

        assertEq(vault.lpts.length, 1);
    }

    function testDepositLPT2() public {
        VaultLib.depositLPT(vault, ranges, rangeId, 100);
        VaultLib.depositLPT(vault, ranges, rangeId, 200);

        assertEq(vault.lpts.length, 1);
    }

    function testWithdrawLPT1() public {
        VaultLib.depositLPT(vault, ranges, rangeId, 100);
        VaultLib.withdrawLPT(vault, rangeId, 50);

        assertEq(vault.lpts.length, 1);
    }

    function testWithdrawLPTAll() public {
        VaultLib.depositLPT(vault, ranges, rangeId, 100);
        VaultLib.withdrawLPT(vault, rangeId, 100);

        assertEq(vault.lpts.length, 0);
    }

    function testBorrowLPT() public {
        VaultLib.borrowLPT(vault, ranges, LPTStateLib.getRangeKey(0, 0), 0);

        assertEq(vault.lpts.length, 1);
    }

    function testBorrowLPT2() public {
        VaultLib.borrowLPT(vault, ranges, rangeId, 100);
        VaultLib.borrowLPT(vault, ranges, rangeId, 200);

        assertEq(vault.lpts.length, 1);
    }

    function testRepayLPT1() public {
        VaultLib.borrowLPT(vault, ranges, rangeId, 100);
        VaultLib.repayLPT(vault, rangeId, 50);

        assertEq(vault.lpts.length, 1);
    }

    function testRepayLPTAll() public {
        VaultLib.borrowLPT(vault, ranges, rangeId, 100);
        VaultLib.repayLPT(vault, rangeId, 100);

        assertEq(vault.lpts.length, 0);
    }
}
