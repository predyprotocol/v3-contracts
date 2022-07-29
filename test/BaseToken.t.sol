// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/BaseToken.sol";

contract BaseTokenTest is Test {
    BaseToken.TokenState tokenState;
    BaseToken.AccountState accountState;

    function setUp() public {
        tokenState.collateralScaler = 1e18;
        tokenState.debtScaler = 1e18;

        BaseToken.addCollateral(tokenState, accountState, 1000 * 1e6);
        BaseToken.addDebt(tokenState, accountState, 200 * 1e6);
    }

    function testCollateralValue() public {
        uint256 value = BaseToken.getCollateralValue(tokenState, accountState);
        assertEq(value, 1000 * 1e6);
    }

    function testCollateralBecomesLarger() public {
        uint256 valueBefore = BaseToken.getCollateralValue(tokenState, accountState);
        BaseToken.updateScaler(tokenState, 1e10);
        uint256 valueAfter = BaseToken.getCollateralValue(tokenState, accountState);
        assertGt(valueAfter, valueBefore);
    }

    function testDebtBecomesLarger() public {
        uint256 valueBefore = BaseToken.getDebtValue(tokenState, accountState);
        BaseToken.updateScaler(tokenState, 1e10);
        uint256 valueAfter = BaseToken.getDebtValue(tokenState, accountState);
        assertGt(valueAfter, valueBefore);
    }

    function testUpdateScaler(uint256 _interestAmount) public {
        vm.assume(_interestAmount > 0);
        vm.assume(_interestAmount <= 1e20);

        BaseToken.updateScaler(tokenState, _interestAmount);

        uint256 collateralValue = BaseToken.getCollateralValue(tokenState, accountState);
        uint256 debtValue = BaseToken.getDebtValue(tokenState, accountState);

        assertEq(collateralValue - debtValue, 800000000);
        // assertLt(collateralValue - debtValue, 800000000 + 1);
    }
}
