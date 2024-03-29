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
        BaseToken.addAsset(tokenState, accountState, assetAmount, true);
        BaseToken.addDebt(tokenState, accountState, debtAmount, true);

        // normal interest
        BaseToken.addAsset(tokenState, normalAccountState, assetAmount, false);
        BaseToken.addDebt(tokenState, normalAccountState, debtAmount, false);
    }

    function testCannotAddCollateralOnCompound() public {
        vm.expectRevert(bytes("B2"));
        BaseToken.addAsset(tokenState, accountState, assetAmount, false);
    }

    function testCannotAddCollateralOnNormal() public {
        vm.expectRevert(bytes("B1"));
        BaseToken.addAsset(tokenState, normalAccountState, assetAmount, true);
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

    function testAddAssetToUpdateLastAssetGrowth() public {
        BaseToken.updateScaler(tokenState, 1e16);

        assertEq(BaseToken.getAssetFee(tokenState, normalAccountState), 1800000);

        BaseToken.addAsset(tokenState, normalAccountState, 1000 * 1e6, false);

        assertEq(BaseToken.getAssetFee(tokenState, normalAccountState), 0);
    }

    function testAddDebtToUpdateLastDebtGrowth() public {
        BaseToken.updateScaler(tokenState, 1e16);

        assertEq(BaseToken.getDebtFee(tokenState, normalAccountState), 2000000);

        BaseToken.addDebt(tokenState, normalAccountState, 200 * 1e6, false);

        assertEq(BaseToken.getDebtFee(tokenState, normalAccountState), 0);
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

    function testUpdateScaler2(uint256 _interestAmount) public {
        uint256 interestAmount = bound(_interestAmount, 1, 1e20);

        uint256 protocolFee1 = BaseToken.updateScaler(tokenState, 1e16);

        uint256 assetValue;
        uint256 debtValue;
        {
            assetValue = BaseToken.getAssetFee(tokenState, normalAccountState);
            debtValue = BaseToken.getDebtFee(tokenState, normalAccountState);
            BaseToken.refreshFee(tokenState, normalAccountState);
        }

        BaseToken.addDebt(tokenState, accountState, 100 * 1e6, true);
        BaseToken.addDebt(tokenState, normalAccountState, 100 * 1e6, false);

        uint256 protocolFee2 = BaseToken.updateScaler(tokenState, interestAmount);

        assetValue += BaseToken.getAssetValue(tokenState, accountState);
        debtValue += BaseToken.getDebtValue(tokenState, accountState);

        assetValue +=
            BaseToken.getAssetValue(tokenState, normalAccountState) +
            BaseToken.getAssetFee(tokenState, normalAccountState);
        debtValue +=
            BaseToken.getDebtValue(tokenState, normalAccountState) +
            BaseToken.getDebtFee(tokenState, normalAccountState);

        assertLe(assetValue - debtValue + protocolFee1 + protocolFee2, 1400000000 + 2);
        assertGe(assetValue - debtValue + protocolFee1 + protocolFee2, 1400000000 - 2);
    }

    // Cannot remove asset if there is no enough available asset
    function testCannotRemoveAsset(uint256 _amount) public {
        vm.assume(assetAmount < _amount && _amount < type(uint128).max);

        BaseToken.removeAsset(tokenState, accountState, _amount);
        vm.expectRevert(bytes("B0"));
        BaseToken.removeAsset(tokenState, normalAccountState, _amount);
    }

    function testRemoveAssetAll(uint256 _amount) public {
        vm.assume(assetAmount < _amount && _amount < type(uint128).max);

        BaseToken.removeDebt(tokenState, accountState, debtAmount);
        BaseToken.removeDebt(tokenState, normalAccountState, debtAmount);

        uint256 removedAssetAmount1 = BaseToken.removeAsset(tokenState, accountState, _amount);
        uint256 removedAssetAmount2 = BaseToken.removeAsset(tokenState, normalAccountState, _amount);

        assertEq(removedAssetAmount1, assetAmount);
        assertEq(removedAssetAmount2, assetAmount);

        // asset values are 0
        uint256 assetValue1 = BaseToken.getAssetValue(tokenState, accountState);
        assertEq(assetValue1, 0);

        uint256 assetValue2 = BaseToken.getAssetValue(tokenState, normalAccountState);
        assertEq(assetValue2, 0);
    }

    function testRemoveAllDebt(uint256 _amount) public {
        vm.assume(debtAmount < _amount && _amount < type(uint128).max);

        uint256 removedDebtAmount1 = BaseToken.removeDebt(tokenState, accountState, _amount);
        uint256 removedDebtAmount2 = BaseToken.removeDebt(tokenState, normalAccountState, _amount);

        assertEq(removedDebtAmount1, debtAmount);
        assertEq(removedDebtAmount2, debtAmount);

        // debt values are 0
        uint256 debtValue1 = BaseToken.getDebtValue(tokenState, accountState);
        assertEq(debtValue1, 0);

        uint256 debtValue2 = BaseToken.getDebtValue(tokenState, normalAccountState);
        assertEq(debtValue2, 0);
    }

    function testRemoveCollateral() public {
        // remove 500 asset of 1000
        uint256 removedAssetAmount1 = BaseToken.removeAsset(tokenState, accountState, 500 * 1e6);
        uint256 removedAssetAmount2 = BaseToken.removeAsset(tokenState, normalAccountState, 500 * 1e6);

        assertEq(removedAssetAmount1, 500 * 1e6);
        assertEq(removedAssetAmount2, 500 * 1e6);

        uint256 assetValue1 = BaseToken.getAssetValue(tokenState, accountState);
        assertEq(assetValue1, 500 * 1e6);

        uint256 assetValue2 = BaseToken.getAssetValue(tokenState, normalAccountState);
        assertEq(assetValue2, 500 * 1e6);
    }

    function testRemoveDebt() public {
        // remove 100 debt of 200
        uint256 removedDebtAmount1 = BaseToken.removeDebt(tokenState, accountState, 100 * 1e6);
        uint256 removedDebtAmount2 = BaseToken.removeDebt(tokenState, normalAccountState, 100 * 1e6);

        assertEq(removedDebtAmount1, 100 * 1e6);
        assertEq(removedDebtAmount2, 100 * 1e6);

        uint256 debtValue1 = BaseToken.getDebtValue(tokenState, accountState);
        assertEq(debtValue1, 100 * 1e6);

        uint256 debtValue2 = BaseToken.getDebtValue(tokenState, normalAccountState);
        assertEq(debtValue2, 100 * 1e6);
    }
}
