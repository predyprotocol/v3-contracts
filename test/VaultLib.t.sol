// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/LPTStateLib.sol";
import "../src/libraries/VaultLib.sol";

contract VaultLibTest is Test {
    DataType.SubVault private subVault;
    mapping(bytes32 => DataType.PerpStatus) private ranges;

    bytes32 private rangeId;

    function setUp() public {
        rangeId = LPTStateLib.getRangeKey(0, 10);
    }

    function testDepositLPT() public {
        VaultLib.depositLPT(subVault, ranges, LPTStateLib.getRangeKey(0, 0), 0);

        assertEq(subVault.lpts.length, 1);
    }

    function testDepositLPT2() public {
        VaultLib.depositLPT(subVault, ranges, rangeId, 100);
        ranges[rangeId].premiumGrowthForLender += 100;
        VaultLib.depositLPT(subVault, ranges, rangeId, 200);

        assertEq(subVault.lpts.length, 1);
        assertTrue(subVault.lpts[0].isCollateral);
    }

    function testWithdrawLPT1() public {
        VaultLib.depositLPT(subVault, ranges, rangeId, 100);
        VaultLib.withdrawLPT(subVault, rangeId, 50);

        assertEq(subVault.lpts.length, 1);
        assertEq(uint256(subVault.lpts[0].liquidityAmount), 50);
    }

    function testWithdrawLPTAll() public {
        VaultLib.depositLPT(subVault, ranges, rangeId, 100);
        VaultLib.withdrawLPT(subVault, rangeId, 100);

        assertEq(subVault.lpts.length, 0);
    }

    function testBorrowLPT() public {
        VaultLib.borrowLPT(subVault, ranges, LPTStateLib.getRangeKey(0, 0), 0);

        assertEq(subVault.lpts.length, 1);
    }

    function testBorrowLPT2() public {
        VaultLib.borrowLPT(subVault, ranges, rangeId, 100);
        ranges[rangeId].premiumGrowthForBorrower += 100;
        VaultLib.borrowLPT(subVault, ranges, rangeId, 200);

        assertEq(subVault.lpts.length, 1);
        assertFalse(subVault.lpts[0].isCollateral);
    }

    function testRepayLPT1() public {
        VaultLib.borrowLPT(subVault, ranges, rangeId, 100);
        VaultLib.repayLPT(subVault, rangeId, 50);

        assertEq(subVault.lpts.length, 1);
        assertEq(uint256(subVault.lpts[0].liquidityAmount), 50);
    }

    function testRepayLPTAll() public {
        VaultLib.borrowLPT(subVault, ranges, rangeId, 100);
        VaultLib.repayLPT(subVault, rangeId, 100);

        assertEq(subVault.lpts.length, 0);
    }
}
