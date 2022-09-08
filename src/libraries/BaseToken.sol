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
        uint256 collateralScaler;
        uint256 debtScaler;
    }

    struct AccountState {
        uint256 collateralAmountNotInMarket;
        uint256 collateralAmount;
        uint256 debtAmount;
    }

    function initialize(TokenState storage tokenState) internal {
        tokenState.collateralScaler = Constants.ONE;
        tokenState.debtScaler = Constants.ONE;
    }

    function addCollateral(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount,
        bool _withEnteringMarket
    ) internal returns (uint256 mintAmount) {
        if (_withEnteringMarket) {
            mintAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.collateralScaler);

            accountState.collateralAmount = accountState.collateralAmount.add(mintAmount);
            tokenState.totalDeposited = tokenState.totalDeposited.add(mintAmount);
        } else {
            accountState.collateralAmountNotInMarket = accountState.collateralAmountNotInMarket.add(_amount);
        }
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

    function removeCollateral(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount,
        bool _withEnteringMarket
    ) internal returns (uint256 finalBurnAmount) {
        if (_withEnteringMarket) {
            uint256 burnAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.collateralScaler);

            if (accountState.collateralAmount < burnAmount) {
                finalBurnAmount = accountState.collateralAmount;
                accountState.collateralAmount = 0;
            } else {
                finalBurnAmount = burnAmount;
                accountState.collateralAmount = accountState.collateralAmount.sub(burnAmount);
            }

            tokenState.totalDeposited = tokenState.totalDeposited.sub(finalBurnAmount);
        } else {
            if (accountState.collateralAmountNotInMarket < _amount) {
                finalBurnAmount = accountState.collateralAmountNotInMarket;
                accountState.collateralAmountNotInMarket = 0;
            } else {
                finalBurnAmount = _amount;
                accountState.collateralAmountNotInMarket = accountState.collateralAmountNotInMarket.sub(_amount);
            }
        }
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
    function getCollateralValue(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        return
            PredyMath.mulDiv(accountState.collateralAmount, tokenState.collateralScaler, Constants.ONE) +
            accountState.collateralAmountNotInMarket;
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

        tokenState.collateralScaler = PredyMath.mulDiv(
            tokenState.collateralScaler,
            updateCollateralScaler,
            Constants.ONE
        );

        return protocolFee;
    }

    function getTotalCollateralValue(TokenState memory tokenState) internal pure returns (uint256) {
        return PredyMath.mulDiv(tokenState.totalDeposited, tokenState.collateralScaler, Constants.ONE);
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
