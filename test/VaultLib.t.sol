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
        ranges[rangeId].premiumGrowthForLender += 100;
        VaultLib.depositLPT(vault, ranges, rangeId, 200);

        assertEq(vault.lpts.length, 1);
        assertTrue(vault.lpts[0].isCollateral);
    }

    function testWithdrawLPT1() public {
        VaultLib.depositLPT(vault, ranges, rangeId, 100);
        VaultLib.withdrawLPT(vault, rangeId, 50);

        assertEq(vault.lpts.length, 1);
        assertEq(uint256(vault.lpts[0].liquidityAmount), 50);
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
        ranges[rangeId].premiumGrowthForBorrower += 100;
        VaultLib.borrowLPT(vault, ranges, rangeId, 200);

        assertEq(vault.lpts.length, 1);
        assertFalse(vault.lpts[0].isCollateral);
    }

    function testRepayLPT1() public {
        VaultLib.borrowLPT(vault, ranges, rangeId, 100);
        VaultLib.repayLPT(vault, rangeId, 50);

        assertEq(vault.lpts.length, 1);
        assertEq(uint256(vault.lpts[0].liquidityAmount), 50);
    }

    function testRepayLPTAll() public {
        VaultLib.borrowLPT(vault, ranges, rangeId, 100);
        VaultLib.repayLPT(vault, rangeId, 100);

        assertEq(vault.lpts.length, 0);
    }
}
