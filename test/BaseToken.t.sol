// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/BaseToken.sol";

contract BaseTokenTest is Test {
    BaseToken.TokenState tokenState;
    BaseToken.AccountState accountState;

    uint256 private collateralAmount = 1000 * 1e6;
    uint256 private debtAmount = 200 * 1e6;

    function setUp() public {
        tokenState.collateralScaler = 1e18;
        tokenState.debtScaler = 1e18;

        BaseToken.addCollateral(tokenState, accountState, collateralAmount);
        BaseToken.addDebt(tokenState, accountState, debtAmount);
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

        uint256 protocolFee = BaseToken.updateScaler(tokenState, _interestAmount);

        uint256 collateralValue = BaseToken.getCollateralValue(tokenState, accountState);
        uint256 debtValue = BaseToken.getDebtValue(tokenState, accountState);

        assertLe(collateralValue - debtValue + protocolFee, 800000000);
        assertGe(collateralValue - debtValue + protocolFee, 800000000 - 1);
    }

    function testRemoveCollateralAll(uint256 _amount) public {
        vm.assume(collateralAmount < _amount && _amount < type(uint128).max);

        assertEq(BaseToken.removeCollateral(tokenState, accountState, _amount), collateralAmount);
    }

    function testRemoveAllDebt(uint256 _amount) public {
        vm.assume(debtAmount < _amount && _amount < type(uint128).max);

        assertEq(BaseToken.removeDebt(tokenState, accountState, _amount), debtAmount);
    }

    function testRemoveCollateral() public {
        BaseToken.removeCollateral(tokenState, accountState, 500 * 1e6);

        uint256 value = BaseToken.getCollateralValue(tokenState, accountState);
        assertEq(value, 500 * 1e6);
    }

    function testRemoveDebt() public {
        BaseToken.removeDebt(tokenState, accountState, 100 * 1e6);

        uint256 debtValue = BaseToken.getDebtValue(tokenState, accountState);
        assertEq(debtValue, 100 * 1e6);
    }
}
