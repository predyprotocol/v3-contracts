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

            accountState.lastAssetGrowth = (
                accountState.lastAssetGrowth.mul(accountState.assetAmount).add(tokenState.assetGrowth.mul(_amount))
            ).div(accountState.assetAmount.add(_amount));

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

            accountState.lastDebtGrowth = (
                accountState.lastDebtGrowth.mul(accountState.debtAmount).add(tokenState.debtGrowth.mul(_amount))
            ).div(accountState.debtAmount.add(_amount));

            accountState.debtAmount += _amount;
            tokenState.totalNormalBorrowed += _amount;

            accountState.interestType = InterestType.NORMAL;
        }
    }

    function removeAsset(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 finalBurnAmount, uint256 fee) {
        if (_amount == 0) {
            return (0, 0);
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

            // TODO: roundUp
            finalBurnAmount = PredyMath.mulDiv(finalBurnAmount, tokenState.assetScaler, Constants.ONE);
        } else {
            fee = getAssetFee(tokenState, accountState);

            if (accountState.assetAmount < _amount) {
                finalBurnAmount = accountState.assetAmount;
                accountState.assetAmount = 0;
            } else {
                finalBurnAmount = _amount;
                fee = (fee * finalBurnAmount) / accountState.assetAmount;
                accountState.assetAmount = accountState.assetAmount.sub(_amount);
            }

            tokenState.totalNormalDeposited = tokenState.totalNormalDeposited.sub(finalBurnAmount);
        }
    }

    function removeDebt(
        TokenState storage tokenState,
        AccountState storage accountState,
        uint256 _amount
    ) internal returns (uint256 finalBurnAmount, uint256 fee) {
        if (_amount == 0) {
            return (0, 0);
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

            // TODO: roundUp
            finalBurnAmount = PredyMath.mulDiv(finalBurnAmount, tokenState.debtScaler, Constants.ONE);
        } else {
            fee = getDebtFee(tokenState, accountState);

            if (accountState.debtAmount < _amount) {
                finalBurnAmount = accountState.debtAmount;
                accountState.debtAmount = 0;
            } else {
                finalBurnAmount = _amount;
                fee = (fee * finalBurnAmount) / accountState.debtAmount;
                accountState.debtAmount = accountState.debtAmount.sub(_amount);
            }

            tokenState.totalNormalBorrowed = tokenState.totalNormalBorrowed.sub(finalBurnAmount);
        }
    }

    function getAssetFee(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        return ((tokenState.assetGrowth.sub(accountState.lastAssetGrowth)) * accountState.assetAmount) / 1e18;
    }

    function getDebtFee(TokenState memory tokenState, AccountState memory accountState)
        internal
        pure
        returns (uint256)
    {
        return ((tokenState.debtGrowth.sub(accountState.lastDebtGrowth)) * accountState.debtAmount) / 1e18;
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
    function updateScaler(TokenState storage tokenState, uint256 _interestAmount) internal returns (uint256) {
        if (tokenState.totalCompoundDeposited == 0 && tokenState.totalNormalDeposited == 0) {
            return 0;
        }

        uint256 protocolFee = PredyMath.mulDiv(
            PredyMath.mulDiv(_interestAmount, getTotalDebtValue(tokenState), Constants.ONE),
            Constants.RESERVE_FACTOR,
            Constants.ONE
        );

        uint256 updateAssetGrowth = PredyMath.mulDiv(
            PredyMath.mulDiv(_interestAmount, getTotalDebtValue(tokenState), getTotalCollateralValue(tokenState)),
            Constants.ONE - Constants.RESERVE_FACTOR,
            Constants.ONE
        );

        // round up
        tokenState.debtScaler = PredyMath.mulDivUp(
            tokenState.debtScaler,
            (Constants.ONE.add(_interestAmount)),
            Constants.ONE
        );
        tokenState.debtGrowth = tokenState.debtGrowth.add(_interestAmount);
        tokenState.assetScaler = PredyMath.mulDiv(
            tokenState.assetScaler,
            Constants.ONE + updateAssetGrowth,
            Constants.ONE
        );
        tokenState.assetGrowth = tokenState.assetGrowth.add(updateAssetGrowth);

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
