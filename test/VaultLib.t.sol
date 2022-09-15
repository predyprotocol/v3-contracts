// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/LPTStateLib.sol";
import "../src/libraries/VaultLib.sol";

contract VaultLibTest is Test {
    DataType.Context private context;

    DataType.Vault private vault;

    DataType.SubVault private subVault;

    mapping(uint256 => DataType.SubVault) private subVaults;

    mapping(bytes32 => DataType.PerpStatus) private ranges;

    bytes32 private rangeId2;

    function setUp() public {
        context = DataType.Context(
            address(0),
            address(0),
            500,
            address(0),
            address(0),
            address(0),
            true,
            1,
            BaseToken.TokenState(0, 0, 0, 0),
            BaseToken.TokenState(0, 0, 0, 0),
            0,
            0
        );

        rangeId2 = LPTStateLib.getRangeKey(0, 10);
    }

    function testAddSubVault() public {
        VaultLib.addSubVault(vault, subVaults, context, 0);

        assertEq(vault.subVaults.length, 1);
    }

    function testCannotAddSubVault() public {
        vm.expectRevert(bytes("V0"));
        VaultLib.addSubVault(vault, subVaults, context, 1);
    }

    function testRemoveSubVault() public {
        VaultLib.addSubVault(vault, subVaults, context, 0);
        VaultLib.removeSubVault(vault, 0);

        assertEq(vault.subVaults.length, 0);
    }

    function testCannotRemoveSubVault() public {
        VaultLib.addSubVault(vault, subVaults, context, 0);

        vm.expectRevert();
        VaultLib.removeSubVault(vault, 1);
    }

    function testDepositLPT() public {
        bytes32 rangeId = LPTStateLib.getRangeKey(0, 0);

        VaultLib.depositLPT(subVault, ranges[rangeId], rangeId, 0);

        assertEq(subVault.lpts.length, 1);
    }

    function testDepositLPT2() public {
        VaultLib.depositLPT(subVault, ranges[rangeId2], rangeId2, 100);
        ranges[rangeId2].premiumGrowthForLender += 100;
        VaultLib.depositLPT(subVault, ranges[rangeId2], rangeId2, 200);

        assertEq(subVault.lpts.length, 1);
        assertTrue(subVault.lpts[0].isCollateral);
    }

    function testWithdrawLPT1() public {
        VaultLib.depositLPT(subVault, ranges[rangeId2], rangeId2, 100);
        VaultLib.withdrawLPT(subVault, ranges[rangeId2], rangeId2, 50, true);

        assertEq(subVault.lpts.length, 1);
        assertEq(uint256(subVault.lpts[0].liquidityAmount), 50);
    }

    function testWithdrawLPTAll() public {
        VaultLib.depositLPT(subVault, ranges[rangeId2], rangeId2, 100);
        VaultLib.withdrawLPT(subVault, ranges[rangeId2], rangeId2, 100, true);

        assertEq(subVault.lpts.length, 0);
    }

    function testBorrowLPT() public {
        bytes32 rangeId = LPTStateLib.getRangeKey(0, 0);

        VaultLib.borrowLPT(subVault, ranges[rangeId], rangeId, 0);

        assertEq(subVault.lpts.length, 1);
    }

    function testBorrowLPT2() public {
        VaultLib.borrowLPT(subVault, ranges[rangeId2], rangeId2, 100);
        ranges[rangeId2].premiumGrowthForBorrower += 100;
        VaultLib.borrowLPT(subVault, ranges[rangeId2], rangeId2, 200);

        assertEq(subVault.lpts.length, 1);
        assertFalse(subVault.lpts[0].isCollateral);
    }

    function testRepayLPT1() public {
        VaultLib.borrowLPT(subVault, ranges[rangeId2], rangeId2, 100);
        VaultLib.repayLPT(subVault, ranges[rangeId2], rangeId2, 50, true);

        assertEq(subVault.lpts.length, 1);
        assertEq(uint256(subVault.lpts[0].liquidityAmount), 50);
    }

    function testRepayLPTAll() public {
        VaultLib.borrowLPT(subVault, ranges[rangeId2], rangeId2, 100);
        VaultLib.repayLPT(subVault, ranges[rangeId2], rangeId2, 100, true);

        assertEq(subVault.lpts.length, 0);
    }
}
