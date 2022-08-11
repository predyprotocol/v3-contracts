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

    function testDepositLPT() public {

        VaultLib.depositLPT(vault, ranges, LPTStateLib.getRangeKey(0, 0), 0);

        assertEq(vault.lpts.length, 1);
    }

}