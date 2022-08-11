//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "./PredyMath.sol";

library BaseToken {
    struct TokenState {
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 collateralScaler;
        uint256 debtScaler;
    }

    struct AccountState {
        uint256 collateralAmountNotInMarket;
        uint256 collateralAmount;
        uint256 debtAmount;
    }

    function initialize(TokenState storage tokenState) internal {
        tokenState.collateralScaler = 1e18;
        tokenState.debtScaler = 1e18;
    }

    function addCollateral(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount,
        bool _withEnteringMarket
    ) internal returns (uint256 mintAmount) {
        if(_withEnteringMarket) {
            mintAmount = PredyMath.mulDiv(_amount, 1e18, tokenState.collateralScaler);

            accountState.collateralAmount += mintAmount;
            tokenState.totalDeposited += mintAmount;
        } else{
            accountState.collateralAmountNotInMarket += _amount;
        }
    }

    function addDebt(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 mintAmount) {
        mintAmount = PredyMath.mulDiv(_amount, 1e18, tokenState.debtScaler);

        accountState.debtAmount += mintAmount;
        tokenState.totalBorrowed += mintAmount;
    }

    function clearCollateral(TokenState storage tokenState, AccountState storage accountState)
        internal
    {
        tokenState.totalDeposited -= accountState.collateralAmount;
        accountState.collateralAmount = 0;
    }

    function clearDebt(TokenState storage tokenState, AccountState storage accountState) internal {
        tokenState.totalBorrowed -= accountState.debtAmount;
        accountState.debtAmount = 0;
    }

    function removeCollateral(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal {
        uint256 burnAmount = PredyMath.mulDiv(_amount, 1e18, tokenState.collateralScaler);

        accountState.collateralAmount -= burnAmount;
        tokenState.totalDeposited -= burnAmount;
    }

    function remomveDebt(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal {
        uint256 burnAmount = PredyMath.mulDiv(_amount, 1e18, tokenState.debtScaler);

        accountState.debtAmount -= burnAmount;
        tokenState.totalBorrowed -= burnAmount;
    }

    // get collateral value
    function getCollateralValue(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        return PredyMath.mulDiv(accountState.collateralAmount, tokenState.collateralScaler, 1e18) + accountState.collateralAmountNotInMarket;
    }

    // get debt value
    function getDebtValue(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        return PredyMath.mulDiv(accountState.debtAmount, tokenState.debtScaler, 1e18);
    }

    // update scaler;
    function updateScaler(TokenState storage tokenState, uint256 _interestAmount) internal {
        if (tokenState.totalDeposited == 0) {
            return;
        }
        tokenState.debtScaler = PredyMath.mulDiv(tokenState.debtScaler, (1e18 + _interestAmount), 1e18);

        uint256 updateCollateralScaler = 1e18 +
            PredyMath.mulDiv(_interestAmount, tokenState.totalBorrowed, tokenState.totalDeposited);

        tokenState.collateralScaler = PredyMath.mulDiv(tokenState.collateralScaler, updateCollateralScaler, 1e18);
    }
}
