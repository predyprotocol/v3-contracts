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

    uint256 private assetAmount = 1000 * 1e6;
    uint256 private debtAmount = 200 * 1e6;

    function setUp() public {
        tokenState.assetScaler = 1e18;
        tokenState.debtScaler = 1e18;

        BaseToken.addCollateral(tokenState, accountState, assetAmount);
        BaseToken.addDebt(tokenState, accountState, debtAmount);
    }

    function testCollateralValue() public {
        uint256 value = BaseToken.getAssetValue(tokenState, accountState);
        assertEq(value, 1000 * 1e6);
    }

    function testCollateralBecomesLarger() public {
        uint256 valueBefore = BaseToken.getAssetValue(tokenState, accountState);
        BaseToken.updateScaler(tokenState, 1e10);
        uint256 valueAfter = BaseToken.getAssetValue(tokenState, accountState);
        assertGt(valueAfter, valueBefore);
    }

    function testDebtBecomesLarger() public {
        uint256 valueBefore = BaseToken.getDebtValue(tokenState, accountState);
        BaseToken.updateScaler(tokenState, 1e10);
        uint256 valueAfter = BaseToken.getDebtValue(tokenState, accountState);
        assertGt(valueAfter, valueBefore);
    }

    function testUpdateScaler(uint256 _interestAmount) public {
        uint256 interestAmount = bound(_interestAmount, 1, 1e20);

        uint256 protocolFee = BaseToken.updateScaler(tokenState, interestAmount);

        uint256 assetValue = BaseToken.getAssetValue(tokenState, accountState);
        uint256 debtValue = BaseToken.getDebtValue(tokenState, accountState);

        assertLe(assetValue - debtValue + protocolFee, 800000000);
        assertGe(assetValue - debtValue + protocolFee, 800000000 - 1);
    }

    function testRemoveCollateralAll(uint256 _amount) public {
        vm.assume(assetAmount < _amount && _amount < type(uint128).max);

        assertEq(BaseToken.removeCollateral(tokenState, accountState, _amount), assetAmount);
    }

    function testRemoveAllDebt(uint256 _amount) public {
        vm.assume(debtAmount < _amount && _amount < type(uint128).max);

        assertEq(BaseToken.removeDebt(tokenState, accountState, _amount), debtAmount);
    }

    function testRemoveCollateral() public {
        BaseToken.removeCollateral(tokenState, accountState, 500 * 1e6);

        uint256 value = BaseToken.getAssetValue(tokenState, accountState);
        assertEq(value, 500 * 1e6);
    }

    function testRemoveDebt() public {
        BaseToken.removeDebt(tokenState, accountState, 100 * 1e6);

        uint256 debtValue = BaseToken.getDebtValue(tokenState, accountState);
        assertEq(debtValue, 100 * 1e6);
    }
}
