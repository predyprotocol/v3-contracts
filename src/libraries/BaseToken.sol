//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./PredyMath.sol";
import "./Constants.sol";

library BaseToken {
    using SafeMath for uint256;

    struct TokenState {
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 assetScaler;
        uint256 debtScaler;
    }

    struct AccountState {
        uint256 assetAmount;
        uint256 debtAmount;
    }

    function initialize(TokenState storage tokenState) internal {
        tokenState.assetScaler = Constants.ONE;
        tokenState.debtScaler = Constants.ONE;
    }

    function addCollateral(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 mintAmount) {
        mintAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.assetScaler);

        accountState.assetAmount = accountState.assetAmount.add(mintAmount);
        tokenState.totalDeposited = tokenState.totalDeposited.add(mintAmount);
    }

    function addDebt(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 mintAmount) {
        require(getAvailableCollateralValue(tokenState) >= _amount, "B0");

        mintAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.debtScaler);

        accountState.debtAmount = accountState.debtAmount.add(mintAmount);
        tokenState.totalBorrowed = tokenState.totalBorrowed.add(mintAmount);
    }

    function clearCollateral(TokenState storage tokenState, AccountState storage accountState)
        internal
        returns (uint256 finalRemoveAmount)
    {
        finalRemoveAmount = accountState.assetAmount;
        tokenState.totalDeposited = tokenState.totalDeposited.sub(finalRemoveAmount);
        accountState.assetAmount = 0;

        finalRemoveAmount = PredyMath.mulDiv(finalRemoveAmount, tokenState.assetScaler, Constants.ONE);
    }

    function clearDebt(TokenState storage tokenState, AccountState storage accountState)
        internal
        returns (uint256 finalRemoveAmount)
    {
        finalRemoveAmount = accountState.debtAmount;
        tokenState.totalBorrowed = tokenState.totalBorrowed.sub(finalRemoveAmount);
        accountState.debtAmount = 0;

        finalRemoveAmount = PredyMath.mulDiv(finalRemoveAmount, tokenState.debtScaler, Constants.ONE);
    }

    function removeCollateral(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 finalBurnAmount) {
        uint256 burnAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.assetScaler);

        if (accountState.assetAmount < burnAmount) {
            finalBurnAmount = accountState.assetAmount;
            accountState.assetAmount = 0;
        } else {
            finalBurnAmount = burnAmount;
            accountState.assetAmount = accountState.assetAmount.sub(burnAmount);
        }

        tokenState.totalDeposited = tokenState.totalDeposited.sub(finalBurnAmount);

        // TODO: roundUp
        finalBurnAmount = PredyMath.mulDiv(finalBurnAmount, tokenState.assetScaler, Constants.ONE);
    }

    function removeDebt(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 finalBurnAmount) {
        uint256 burnAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.debtScaler);

        if (accountState.debtAmount < burnAmount) {
            finalBurnAmount = accountState.debtAmount;
            accountState.debtAmount = 0;
        } else {
            finalBurnAmount = burnAmount;
            accountState.debtAmount = accountState.debtAmount.sub(burnAmount);
        }

        tokenState.totalBorrowed = tokenState.totalBorrowed.sub(finalBurnAmount);

        // TODO: roundUp
        finalBurnAmount = PredyMath.mulDiv(finalBurnAmount, tokenState.debtScaler, Constants.ONE);
    }

    // get collateral value
    function getAssetValue(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        return PredyMath.mulDiv(accountState.assetAmount, tokenState.assetScaler, Constants.ONE);
    }

    // get debt value
    function getDebtValue(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        return PredyMath.mulDiv(accountState.debtAmount, tokenState.debtScaler, Constants.ONE);
    }

    // update scaler
    function updateScaler(TokenState storage tokenState, uint256 _interestAmount) internal returns (uint256) {
        if (tokenState.totalDeposited == 0) {
            return 0;
        }

        uint256 protocolFee = (((getTotalDebtValue(tokenState) * _interestAmount) / Constants.ONE) *
            Constants.RESERVE_FACTOR) / Constants.ONE;

        tokenState.debtScaler = PredyMath.mulDiv(
            tokenState.debtScaler,
            (Constants.ONE + _interestAmount),
            Constants.ONE
        );

        uint256 updateCollateralScaler = Constants.ONE +
            PredyMath.mulDiv(
                PredyMath.mulDiv(_interestAmount, tokenState.totalBorrowed, tokenState.totalDeposited),
                Constants.ONE - Constants.RESERVE_FACTOR,
                Constants.ONE
            );

        tokenState.assetScaler = PredyMath.mulDiv(tokenState.assetScaler, updateCollateralScaler, Constants.ONE);

        return protocolFee;
    }

    function getTotalCollateralValue(TokenState memory tokenState) internal pure returns (uint256) {
        return PredyMath.mulDiv(tokenState.totalDeposited, tokenState.assetScaler, Constants.ONE);
    }

    function getTotalDebtValue(TokenState memory tokenState) internal pure returns (uint256) {
        return PredyMath.mulDiv(tokenState.totalBorrowed, tokenState.debtScaler, Constants.ONE);
    }

    function getAvailableCollateralValue(TokenState memory tokenState) internal pure returns (uint256) {
        return getTotalCollateralValue(tokenState) - getTotalDebtValue(tokenState);
    }

    function getUtilizationRatio(TokenState memory tokenState) internal pure returns (uint256) {
        if (tokenState.totalDeposited == 0) {
            return Constants.ONE;
        }

        return PredyMath.mulDiv(getTotalDebtValue(tokenState), Constants.ONE, getTotalCollateralValue(tokenState));
    }
}
