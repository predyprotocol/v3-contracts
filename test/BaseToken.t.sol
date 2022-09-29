// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/BaseToken.sol";

contract BaseTokenTest is Test {
    BaseToken.TokenState private tokenState;
    BaseToken.AccountState private accountState;
    BaseToken.AccountState private normalAccountState;

    uint256 private assetAmount = 1000 * 1e6;
    uint256 private debtAmount = 200 * 1e6;

    function setUp() public {
        tokenState.assetScaler = 1e18;
        tokenState.debtScaler = 1e18;

        // compound interest
        BaseToken.addCollateral(tokenState, accountState, assetAmount, true);
        BaseToken.addDebt(tokenState, accountState, debtAmount, true);

        // normal interest
        BaseToken.addCollateral(tokenState, normalAccountState, assetAmount, false);
        BaseToken.addDebt(tokenState, normalAccountState, debtAmount, false);
    }

    function testCannotAddCollateralOnCompound() public {
        vm.expectRevert(bytes("B2"));
        BaseToken.addCollateral(tokenState, accountState, assetAmount, false);
    }

    function testCannotAddCollateralOnNormal() public {
        vm.expectRevert(bytes("B1"));
        BaseToken.addCollateral(tokenState, normalAccountState, assetAmount, true);
    }

    function testCannotAddDebtOnCompound() public {
        vm.expectRevert(bytes("B2"));
        BaseToken.addDebt(tokenState, accountState, debtAmount, false);
    }

    function testCannotAddDebtOnNormal() public {
        vm.expectRevert(bytes("B1"));
        BaseToken.addDebt(tokenState, normalAccountState, debtAmount, true);
    }

    function testCannotAddDebtBecauseAmountIsTooLarge(uint256 _amount) public {
        uint256 amount = bound(_amount, assetAmount * 2 + 1, type(uint256).max);

        vm.expectRevert(bytes("B0"));
        BaseToken.addDebt(tokenState, normalAccountState, amount, true);
    }

    function testAssetValue() public {
        assertEq(BaseToken.getAssetValue(tokenState, accountState), 1000 * 1e6);
        assertEq(BaseToken.getAssetValue(tokenState, normalAccountState), 1000 * 1e6);
    }

    function testDebtValue() public {
        assertEq(BaseToken.getDebtValue(tokenState, accountState), 200 * 1e6);
        assertEq(BaseToken.getDebtValue(tokenState, normalAccountState), 200 * 1e6);
    }

    function testAssetAndDebtBecomesLarger() public {
        BaseToken.updateScaler(tokenState, 1e10);

        assertGt(BaseToken.getAssetValue(tokenState, accountState), 1000 * 1e6);
        assertGt(BaseToken.getDebtValue(tokenState, accountState), 200 * 1e6);
        assertEq(BaseToken.getAssetValue(tokenState, normalAccountState), 1000 * 1e6);
        assertEq(BaseToken.getDebtValue(tokenState, normalAccountState), 200 * 1e6);
        assertGt(BaseToken.getAssetFee(tokenState, normalAccountState), 0);
        assertGt(BaseToken.getDebtFee(tokenState, normalAccountState), 0);
    }

    function testUpdateScaler(uint256 _interestAmount) public {
        uint256 interestAmount = bound(_interestAmount, 1, 1e20);

        uint256 protocolFee = BaseToken.updateScaler(tokenState, interestAmount);

        uint256 assetValue1 = BaseToken.getAssetValue(tokenState, accountState);
        uint256 debtValue1 = BaseToken.getDebtValue(tokenState, accountState);

        uint256 assetValue2 = BaseToken.getAssetValue(tokenState, normalAccountState) +
            BaseToken.getAssetFee(tokenState, normalAccountState);
        uint256 debtValue2 = BaseToken.getDebtValue(tokenState, normalAccountState) +
            BaseToken.getDebtFee(tokenState, normalAccountState);

        assertLe(assetValue1 + assetValue2 - debtValue1 - debtValue2 + protocolFee, 1600000000 + 2);
        assertGe(assetValue1 + assetValue2 - debtValue1 - debtValue2 + protocolFee, 1600000000 - 2);
    }

    function testRemoveCollateralAll(uint256 _amount) public {
        vm.assume(assetAmount < _amount && _amount < type(uint128).max);

        (uint256 removedAssetAmount, ) = BaseToken.removeCollateral(tokenState, accountState, _amount);

        assertEq(removedAssetAmount, assetAmount);
    }

    function testRemoveAllDebt(uint256 _amount) public {
        vm.assume(debtAmount < _amount && _amount < type(uint128).max);

        (uint256 removedDebtAmount, ) = BaseToken.removeDebt(tokenState, accountState, _amount);

        assertEq(removedDebtAmount, debtAmount);
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

    function testRemoveCollateralOfNormalInterest() public {
        BaseToken.updateScaler(tokenState, 1e16);

        (, uint256 assetFee) = BaseToken.removeCollateral(tokenState, normalAccountState, 500 * 1e6);

        // 0.01 * 200 * 0.9
        assertEq(assetFee, 900000);

        uint256 value = BaseToken.getAssetValue(tokenState, normalAccountState);
        assertEq(value, 500 * 1e6);
    }

    function testRemoveDebtOfNormalInterest() public {
        BaseToken.updateScaler(tokenState, 1e16);

        (, uint256 assetFee) = BaseToken.removeDebt(tokenState, normalAccountState, 100 * 1e6);

        // 0.01 * 200
        assertEq(assetFee, 1000000);

        uint256 value = BaseToken.getDebtValue(tokenState, normalAccountState);
        assertEq(value, 100 * 1e6);
    }
}
