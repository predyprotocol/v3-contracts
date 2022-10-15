// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/LPTStateLib.sol";

contract LPTStateLibTest is Test {
    DataType.PerpStatus private perpStatus;

    function testRegisterNewLPTState() public {
        LPTStateLib.registerNewLPTState(perpStatus, 0, 10);

        assertEq(perpStatus.lowerTick, 0);
        assertEq(perpStatus.upperTick, 10);
    }
}
