//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./PredyMath.sol";
import "./Constants.sol";

library BaseToken {
    using SafeMath for uint256;

    enum InterestType {
        EMPTY,
        COMPOUND,
        NORMAL
    }

    struct TokenState {
        uint256 totalCompoundDeposited;
        uint256 totalCompoundBorrowed;
        uint256 totalNormalDeposited;
        uint256 totalNormalBorrowed;
        uint256 assetScaler;
        uint256 debtScaler;
        uint256 assetGrowth;
        uint256 debtGrowth;
    }

    struct AccountState {
        InterestType interestType;
        uint256 assetAmount;
        uint256 debtAmount;
        uint256 lastAssetGrowth;
        uint256 lastDebtGrowth;
    }

    function initialize(TokenState storage tokenState) internal {
        tokenState.assetScaler = Constants.ONE;
        tokenState.debtScaler = Constants.ONE;
    }

    function addAsset(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount,
        bool _isCompound
    ) internal returns (uint256 mintAmount) {
        if (_amount == 0) {
            return 0;
        }

        if (_isCompound) {
            require(accountState.interestType != InterestType.NORMAL, "B1");
            mintAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.assetScaler);

            accountState.assetAmount = accountState.assetAmount.add(mintAmount);
            tokenState.totalCompoundDeposited = tokenState.totalCompoundDeposited.add(mintAmount);

            accountState.interestType = InterestType.COMPOUND;
        } else {
            require(accountState.interestType != InterestType.COMPOUND, "B2");

            accountState.lastAssetGrowth = tokenState.assetGrowth;

            accountState.assetAmount += _amount;
            tokenState.totalNormalDeposited += _amount;

            accountState.interestType = InterestType.NORMAL;
        }
    }

    function addDebt(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount,
        bool _isCompound
    ) internal returns (uint256 mintAmount) {
        if (_amount == 0) {
            return 0;
        }

        require(getAvailableCollateralValue(tokenState) >= _amount, "B0");

        if (_isCompound) {
            require(accountState.interestType != InterestType.NORMAL, "B1");
            mintAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.debtScaler);

            accountState.debtAmount = accountState.debtAmount.add(mintAmount);
            tokenState.totalCompoundBorrowed = tokenState.totalCompoundBorrowed.add(mintAmount);

            accountState.interestType = InterestType.COMPOUND;
        } else {
            require(accountState.interestType != InterestType.COMPOUND, "B2");

            accountState.lastDebtGrowth = tokenState.debtGrowth;

            accountState.debtAmount += _amount;
            tokenState.totalNormalBorrowed += _amount;

            accountState.interestType = InterestType.NORMAL;
        }
    }

    function removeAsset(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 finalBurnAmount) {
        if (_amount == 0) {
            return 0;
        }

        if (accountState.interestType == InterestType.COMPOUND) {
            uint256 burnAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.assetScaler);

            if (accountState.assetAmount < burnAmount) {
                finalBurnAmount = accountState.assetAmount;
                accountState.assetAmount = 0;
            } else {
                finalBurnAmount = burnAmount;
                accountState.assetAmount = accountState.assetAmount.sub(burnAmount);
            }

            tokenState.totalCompoundDeposited = tokenState.totalCompoundDeposited.sub(finalBurnAmount);

            finalBurnAmount = PredyMath.mulDiv(finalBurnAmount, tokenState.assetScaler, Constants.ONE);
        } else {
            if (accountState.assetAmount < _amount) {
                finalBurnAmount = accountState.assetAmount;
                accountState.assetAmount = 0;
            } else {
                finalBurnAmount = _amount;
                accountState.assetAmount = accountState.assetAmount.sub(_amount);
            }

            tokenState.totalNormalDeposited = tokenState.totalNormalDeposited.sub(finalBurnAmount);
        }
    }

    function removeDebt(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 finalBurnAmount) {
        if (_amount == 0) {
            return 0;
        }

        if (accountState.interestType == InterestType.COMPOUND) {
            uint256 burnAmount = PredyMath.mulDiv(_amount, Constants.ONE, tokenState.debtScaler);

            if (accountState.debtAmount < burnAmount) {
                finalBurnAmount = accountState.debtAmount;
                accountState.debtAmount = 0;
            } else {
                finalBurnAmount = burnAmount;
                accountState.debtAmount = accountState.debtAmount.sub(burnAmount);
            }

            tokenState.totalCompoundBorrowed = tokenState.totalCompoundBorrowed.sub(finalBurnAmount);

            finalBurnAmount = PredyMath.mulDiv(finalBurnAmount, tokenState.debtScaler, Constants.ONE);
        } else {
            if (accountState.debtAmount < _amount) {
                finalBurnAmount = accountState.debtAmount;
                accountState.debtAmount = 0;
            } else {
                finalBurnAmount = _amount;
                accountState.debtAmount = accountState.debtAmount.sub(_amount);
            }

            tokenState.totalNormalBorrowed = tokenState.totalNormalBorrowed.sub(finalBurnAmount);
        }
    }

    function refreshFee(TokenState memory tokenState, AccountState storage accountState) internal {
        accountState.lastAssetGrowth = tokenState.assetGrowth;
        accountState.lastDebtGrowth = tokenState.debtGrowth;
    }

    function getAssetFee(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        if (accountState.interestType != InterestType.NORMAL) {
            return 0;
        }

        return
            PredyMath.mulDiv(
                tokenState.assetGrowth.sub(accountState.lastAssetGrowth),
                accountState.assetAmount,
                Constants.ONE
            );
    }

    function getDebtFee(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        if (accountState.interestType != InterestType.NORMAL) {
            return 0;
        }

        return
            PredyMath.mulDiv(
                tokenState.debtGrowth.sub(accountState.lastDebtGrowth),
                accountState.debtAmount,
                Constants.ONE
            );
    }

    // get collateral value
    function getAssetValue(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        if (accountState.interestType == InterestType.COMPOUND) {
            return PredyMath.mulDiv(accountState.assetAmount, tokenState.assetScaler, Constants.ONE);
        } else {
            return accountState.assetAmount;
        }
    }

    // get debt value
    function getDebtValue(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        if (accountState.interestType == InterestType.COMPOUND) {
            return PredyMath.mulDiv(accountState.debtAmount, tokenState.debtScaler, Constants.ONE);
        } else {
            return accountState.debtAmount;
        }
    }

    // update scaler
    function updateScaler(TokenState storage tokenState, uint256 _interestRate) internal returns (uint256) {
        if (tokenState.totalCompoundDeposited == 0 && tokenState.totalNormalDeposited == 0) {
            return 0;
        }

        uint256 protocolFee = PredyMath.mulDiv(
            PredyMath.mulDiv(_interestRate, getTotalDebtValue(tokenState), Constants.ONE),
            Constants.RESERVE_FACTOR,
            Constants.ONE
        );

        // supply interest rate is InterestRate * Utilization * (1 - ReserveFactor)
        uint256 supplyInterestRate = PredyMath.mulDiv(
            PredyMath.mulDiv(_interestRate, getTotalDebtValue(tokenState), getTotalCollateralValue(tokenState)),
            Constants.ONE - Constants.RESERVE_FACTOR,
            Constants.ONE
        );

        // round up
        tokenState.debtScaler = PredyMath.mulDivUp(
            tokenState.debtScaler,
            (Constants.ONE.add(_interestRate)),
            Constants.ONE
        );
        tokenState.debtGrowth = tokenState.debtGrowth.add(_interestRate);
        tokenState.assetScaler = PredyMath.mulDiv(
            tokenState.assetScaler,
            Constants.ONE + supplyInterestRate,
            Constants.ONE
        );
        tokenState.assetGrowth = tokenState.assetGrowth.add(supplyInterestRate);

        return protocolFee;
    }

    function getTotalCollateralValue(TokenState memory tokenState) internal pure returns (uint256) {
        return
            PredyMath.mulDiv(tokenState.totalCompoundDeposited, tokenState.assetScaler, Constants.ONE) +
            tokenState.totalNormalDeposited;
    }

    function getTotalDebtValue(TokenState memory tokenState) internal pure returns (uint256) {
        return
            PredyMath.mulDiv(tokenState.totalCompoundBorrowed, tokenState.debtScaler, Constants.ONE) +
            tokenState.totalNormalBorrowed;
    }

    function getAvailableCollateralValue(TokenState memory tokenState) internal pure returns (uint256) {
        return getTotalCollateralValue(tokenState).sub(getTotalDebtValue(tokenState));
    }

    function getUtilizationRatio(TokenState memory tokenState) internal pure returns (uint256) {
        if (tokenState.totalCompoundDeposited == 0 && tokenState.totalNormalBorrowed == 0) {
            return Constants.ONE;
        }

        return PredyMath.mulDiv(getTotalDebtValue(tokenState), Constants.ONE, getTotalCollateralValue(tokenState));
    }
}
