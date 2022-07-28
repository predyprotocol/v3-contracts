//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "v3-core/contracts/libraries/FullMath.sol";
import "forge-std/console2.sol";

library BaseToken {
    struct TokenState {
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 collateralScaler;
        uint256 debtScaler;
    }

    struct AccountState {
        uint256 collateralAmount;
        uint256 debtAmount;
    }

    function initialize(TokenState storage tokenState) internal returns(uint256) {
        tokenState.collateralScaler = 1e18;
        tokenState.debtScaler = 1e18;
    }


    function addCollateral(TokenState storage tokenState, AccountState storage accountState, uint256 _amount) internal returns(uint256) {
        uint256 mintAmount = FullMath.mulDiv(_amount, 1e18, tokenState.collateralScaler);

        accountState.collateralAmount += mintAmount;
        tokenState.totalDeposited += mintAmount;
    }

    function addDebt(TokenState storage tokenState, AccountState storage accountState, uint256 _amount) internal returns(uint256) {
        uint256 mintAmount = FullMath.mulDiv(_amount, 1e18, tokenState.debtScaler);

        accountState.debtAmount += mintAmount;
        tokenState.totalBorrowed += mintAmount;
    }

    function clearCollateral(TokenState storage tokenState, AccountState storage accountState) internal returns(uint256) {
        tokenState.totalDeposited -= accountState.collateralAmount;
        accountState.collateralAmount = 0;
    }

    function clearDebt(TokenState storage tokenState, AccountState storage accountState) internal returns(uint256) {
        tokenState.totalBorrowed -= accountState.debtAmount;
        accountState.debtAmount = 0;
    }

    function removeCollateral(TokenState storage tokenState, AccountState storage accountState, uint256 _amount) internal returns(uint256) {
        uint256 burnAmount = FullMath.mulDiv(_amount, 1e18, tokenState.collateralScaler);

        accountState.collateralAmount -= burnAmount;
        tokenState.totalDeposited -= burnAmount;
    }

    function remomveDebt(TokenState storage tokenState, AccountState storage accountState, uint256 _amount) internal returns(uint256) {
        uint256 burnAmount = FullMath.mulDiv(_amount, 1e18, tokenState.debtScaler);

        accountState.debtAmount -= burnAmount;
        tokenState.totalBorrowed -= burnAmount;
    }

    // get collateral value
    function getCollateralValue(TokenState memory tokenState, AccountState memory accountState) internal pure returns(uint256) {
        return FullMath.mulDiv(accountState.collateralAmount, tokenState.collateralScaler, 1e18);
    }

    // get debt value
    function getDebtValue(TokenState memory tokenState, AccountState memory accountState) internal pure returns(uint256) {
        return FullMath.mulDiv(accountState.debtAmount, tokenState.debtScaler, 1e18);
    }

    // update scaler;
    function updateScaler(TokenState storage tokenState, uint256 _interestAmount) internal {
        if(tokenState.totalDeposited == 0) {
            return;
        }
        tokenState.debtScaler = FullMath.mulDiv(tokenState.debtScaler, (1e18 + _interestAmount), 1e18);

        uint256 updateCollateralScaler = 1e18 + FullMath.mulDiv(_interestAmount, tokenState.totalBorrowed, tokenState.totalDeposited);

        tokenState.collateralScaler = FullMath.mulDiv(tokenState.collateralScaler, updateCollateralScaler, 1e18);
    }
}
