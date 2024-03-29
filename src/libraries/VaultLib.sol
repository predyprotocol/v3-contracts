// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "./PredyMath.sol";
import "./Constants.sol";
import "./PriceHelper.sol";
import "./BaseToken.sol";
import "./DataType.sol";
import "./PositionCalculator.sol";
import "./PositionLib.sol";

/**
 * Error Codes
 * V0: sub-vault not found
 * V1: Exceeds max num of sub-vaults
 */
library VaultLib {
    using SafeMath for uint256;
    using SafeMath for uint128;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using BaseToken for BaseToken.TokenState;

    event SubVaultCreated(uint256 indexed vaultId, uint256 subVaultIndex, uint256 subVaultId);
    event SubVaultRemoved(uint256 indexed vaultId, uint256 subVaultIndex, uint256 subVaultId);

    /**
     * @notice add sub-vault to the vault
     * @param _vault vault object
     * @param _subVaults sub-vaults map
     * @param _context context object
     * @param _subVaultId index of sub-vault in the vault to add
     */
    function addSubVault(
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context storage _context,
        uint256 _subVaultId
    ) internal returns (DataType.SubVault storage subVault, uint256 subVaultIndex) {
        if (_subVaultId == 0) {
            require(_vault.subVaults.length < Constants.MAX_NUM_OF_SUBVAULTS, "V1");

            uint256 subVaultId = _context.nextSubVaultId;

            _context.nextSubVaultId += 1;

            subVaultIndex = _vault.subVaults.length;

            _vault.subVaults.push(subVaultId);

            emit SubVaultCreated(_vault.vaultId, subVaultIndex, subVaultId);

            _subVaults[subVaultId].id = subVaultId;

            subVault = _subVaults[subVaultId];
        } else {
            subVaultIndex = getSubVaultIndex(_vault, _subVaultId);

            uint256 subVaultId = _vault.subVaults[subVaultIndex];

            subVault = _subVaults[subVaultId];
        }
    }

    /**
     * @notice remove sub-vault from the vault
     * @param _vault vault object
     * @param _subVaultIndex index of sub-vault in the vault to remove
     */
    function removeSubVault(DataType.Vault storage _vault, uint256 _subVaultIndex) internal {
        require(_subVaultIndex < _vault.subVaults.length, "V0");

        uint256 subVaultId = _vault.subVaults[_subVaultIndex];

        _vault.subVaults[_subVaultIndex] = _vault.subVaults[_vault.subVaults.length - 1];
        _vault.subVaults.pop();

        emit SubVaultRemoved(_vault.vaultId, _subVaultIndex, subVaultId);
    }

    function getSubVaultIndex(DataType.Vault memory _vault, uint256 _subVaultId) internal pure returns (uint256) {
        uint256 subVaultIndex = type(uint256).max;

        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            if (_vault.subVaults[i] == _subVaultId) {
                subVaultIndex = i;
                break;
            }
        }

        require(subVaultIndex <= Constants.MAX_NUM_OF_SUBVAULTS, "V0");

        return subVaultIndex;
    }

    function depositLPT(
        DataType.SubVault storage _subVault,
        DataType.PerpStatus memory _range,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            DataType.LPTState storage lpt = _subVault.lpts[i];

            if (lpt.rangeId == _rangeId && lpt.isCollateral) {
                lpt.premiumGrowthLast = _range.premiumGrowthForLender;

                lpt.fee0Last = _range.fee0Growth;
                lpt.fee1Last = _range.fee1Growth;

                lpt.liquidityAmount = lpt.liquidityAmount.add(_liquidityAmount).toUint128();

                return;
            }
        }

        _subVault.lpts.push(
            DataType.LPTState(
                true,
                _rangeId,
                _liquidityAmount,
                _range.premiumGrowthForLender,
                _range.fee0Growth,
                _range.fee1Growth
            )
        );
    }

    function withdrawLPT(
        DataType.SubVault storage _subVault,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal returns (uint128 liquidityAmount) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            DataType.LPTState storage lpt = _subVault.lpts[i];

            if (lpt.rangeId == _rangeId && lpt.isCollateral) {
                liquidityAmount = _liquidityAmount;

                if (_liquidityAmount > lpt.liquidityAmount) {
                    liquidityAmount = lpt.liquidityAmount;
                }

                lpt.liquidityAmount = lpt.liquidityAmount.sub(liquidityAmount).toUint128();

                if (lpt.liquidityAmount == 0) {
                    _subVault.lpts[i] = _subVault.lpts[_subVault.lpts.length - 1];
                    _subVault.lpts.pop();
                }

                return liquidityAmount;
            }
        }
    }

    function borrowLPT(
        DataType.SubVault storage _subVault,
        DataType.PerpStatus memory _range,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            DataType.LPTState storage lpt = _subVault.lpts[i];

            if (lpt.rangeId == _rangeId && !lpt.isCollateral) {
                lpt.premiumGrowthLast = _range.premiumGrowthForBorrower;

                lpt.liquidityAmount = lpt.liquidityAmount.add(_liquidityAmount).toUint128();

                return;
            }
        }

        _subVault.lpts.push(
            DataType.LPTState(false, _rangeId, _liquidityAmount, _range.premiumGrowthForBorrower, 0, 0)
        );
    }

    function repayLPT(
        DataType.SubVault storage _subVault,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal returns (uint128 liquidityAmount) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            DataType.LPTState storage lpt = _subVault.lpts[i];

            if (lpt.rangeId == _rangeId && !lpt.isCollateral) {
                liquidityAmount = _liquidityAmount;

                if (_liquidityAmount > lpt.liquidityAmount) {
                    liquidityAmount = lpt.liquidityAmount;
                }

                lpt.liquidityAmount = lpt.liquidityAmount.sub(liquidityAmount).toUint128();

                if (lpt.liquidityAmount == 0) {
                    _subVault.lpts[i] = _subVault.lpts[_subVault.lpts.length - 1];
                    _subVault.lpts.pop();
                }

                return liquidityAmount;
            }
        }
    }

    function updateEntryPrice(
        uint256 _entryPrice,
        uint256 _position,
        uint256 _tradePrice,
        uint256 _positionTrade
    ) internal pure returns (uint256 newEntryPrice) {
        newEntryPrice = (_entryPrice.mul(_position).add(_tradePrice.mul(_positionTrade))).div(
            _position.add(_positionTrade)
        );
    }

    function calculateProfit(
        uint256 _entryPrice,
        uint256 _tradePrice,
        uint256 _positionTrade,
        uint256 _denominator
    ) internal pure returns (uint256 profit) {
        return _tradePrice.sub(_entryPrice).mul(_positionTrade).div(_denominator);
    }

    function getVaultStatus(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) external view returns (DataType.VaultStatus memory) {
        DataType.SubVaultStatus[] memory subVaultsStatus = new DataType.SubVaultStatus[](_vault.subVaults.length);

        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVaultAmount memory statusAmount = getVaultStatusAmount(
                _subVaults[_vault.subVaults[i]],
                _ranges,
                _context,
                _sqrtPrice
            );

            DataType.SubVaultPremium memory subVaultPremium = getVaultStatusPremium(
                _subVaults[_vault.subVaults[i]],
                _ranges
            );

            DataType.SubVaultInterest memory statusInterest = getVaultStatusInterest(
                _subVaults[_vault.subVaults[i]],
                _context
            );

            subVaultsStatus[i] = DataType.SubVaultStatus(
                getVaultStatusValue(statusAmount, statusInterest, subVaultPremium, _sqrtPrice, _context.isMarginZero),
                statusAmount,
                statusInterest,
                subVaultPremium
            );
        }

        PositionCalculator.PositionCalculatorParams memory params = getPositionCalculatorParams(
            _vault,
            _subVaults,
            _ranges,
            _context
        );

        (int256 marginValue, uint256 assetValue, uint256 debtValue) = PositionCalculator
            .calculateCollateralAndDebtValue(params, _sqrtPrice, _context.isMarginZero);

        return
            DataType.VaultStatus(
                int256(assetValue).sub(int256(debtValue)),
                marginValue,
                PositionCalculator.calculateMinDeposit(params, _sqrtPrice, _context.isMarginZero),
                subVaultsStatus
            );
    }

    function getMarginAmount(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) internal view returns (int256 marginAmount0, int256 marginAmount1) {
        (int256 fee0, int256 fee1) = getPremiumAndFee(_vault, _subVaults, _ranges, _context);

        marginAmount0 = int256(_vault.marginAmount0).add(fee0);
        marginAmount1 = int256(_vault.marginAmount1).add(fee1);
    }

    function getVaultValue(
        DataType.Context memory _context,
        PositionCalculator.PositionCalculatorParams memory _params,
        uint160 _sqrtPrice
    ) internal pure returns (int256) {
        return PositionCalculator.calculateValue(_params, _sqrtPrice, _context.isMarginZero);
    }

    function getVaultStatusValue(
        DataType.SubVaultAmount memory statusAmount,
        DataType.SubVaultInterest memory statusInterest,
        DataType.SubVaultPremium memory statusPremium,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (DataType.SubVaultValue memory) {
        int256 fee0 = statusInterest.assetFee0.sub(statusInterest.debtFee0);
        int256 fee1 = statusInterest.assetFee1.sub(statusInterest.debtFee1);

        fee0 = fee0.add(int256(statusPremium.receivedTradeAmount0));
        fee1 = fee1.add(int256(statusPremium.receivedTradeAmount1));

        int256 premium = int256(statusPremium.receivedPremium).sub(int256(statusPremium.paidPremium));

        return
            DataType.SubVaultValue(
                uint256(
                    PriceHelper.getValue(
                        _isMarginZero,
                        _sqrtPrice,
                        int256(statusAmount.assetAmount0),
                        int256(statusAmount.assetAmount1)
                    )
                ),
                uint256(
                    PriceHelper.getValue(
                        _isMarginZero,
                        _sqrtPrice,
                        int256(statusAmount.debtAmount0),
                        int256(statusAmount.debtAmount1)
                    )
                ),
                PriceHelper.getValue(_isMarginZero, _sqrtPrice, fee0, fee1).add(premium)
            );
    }

    function getVaultStatusAmount(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) internal view returns (DataType.SubVaultAmount memory) {
        (uint256 assetAmount0, uint256 assetAmount1) = getAssetPositionAmounts(
            _subVault,
            _ranges,
            _context,
            _sqrtPrice
        );
        (uint256 debtAmount0, uint256 debtAmount1) = getDebtPositionAmounts(_subVault, _ranges, _context, _sqrtPrice);

        return DataType.SubVaultAmount(assetAmount0, assetAmount1, debtAmount0, debtAmount1);
    }

    function getVaultStatusPremium(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) internal view returns (DataType.SubVaultPremium memory) {
        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_subVault, _ranges);

        return
            DataType.SubVaultPremium(
                fee0,
                fee1,
                getEarnedDailyPremium(_subVault, _ranges),
                getPaidDailyPremium(_subVault, _ranges)
            );
    }

    function getVaultStatusInterest(DataType.SubVault memory _subVault, DataType.Context memory _context)
        internal
        pure
        returns (DataType.SubVaultInterest memory)
    {
        (int256 assetFee0, int256 assetFee1, int256 debtFee0, int256 debtFee1) = getTokenInterestOfSubVault(
            _subVault,
            _context
        );

        return DataType.SubVaultInterest(assetFee0, assetFee1, debtFee0, debtFee1);
    }

    /**
     * @notice latest asset amounts
     */
    function getAssetPositionAmounts(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        totalAmount0 = totalAmount0.add(_context.tokenState0.getAssetValue(_subVault.balance0));
        totalAmount1 = totalAmount1.add(_context.tokenState1.getAssetValue(_subVault.balance1));

        {
            (uint256 amount0, uint256 amount1) = getLPTPositionAmounts(_subVault, _ranges, _sqrtPrice, true);

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }
    }

    function getDebtPositionAmounts(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        totalAmount0 = totalAmount0.add(_context.tokenState0.getDebtValue(_subVault.balance0));
        totalAmount1 = totalAmount1.add(_context.tokenState1.getDebtValue(_subVault.balance1));

        {
            (uint256 amount0, uint256 amount1) = getLPTPositionAmounts(_subVault, _ranges, _sqrtPrice, false);

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }
    }

    function getLPTPositionAmounts(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint160 _sqrtPrice,
        bool _isCollateral
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            DataType.LPTState memory lpt = _subVault.lpts[i];

            if (_isCollateral != lpt.isCollateral) {
                continue;
            }

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                TickMath.getSqrtRatioAtTick(_ranges[lpt.rangeId].lowerTick),
                TickMath.getSqrtRatioAtTick(_ranges[lpt.rangeId].upperTick),
                lpt.liquidityAmount
            );

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }
    }

    function getEarnedTradeFeeForRange(DataType.LPTState memory _lpt, DataType.PerpStatus memory _range)
        internal
        pure
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        if (_lpt.isCollateral) {
            totalAmount0 = PredyMath.mulDiv(_range.fee0Growth.sub(_lpt.fee0Last), _lpt.liquidityAmount, Constants.ONE);
            totalAmount1 = PredyMath.mulDiv(_range.fee1Growth.sub(_lpt.fee1Last), _lpt.liquidityAmount, Constants.ONE);
        }
    }

    function getEarnedTradeFee(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges
    ) public view returns (uint256 totalFeeAmount0, uint256 totalFeeAmount1) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            bytes32 rangeId = _subVault.lpts[i].rangeId;

            (uint256 tradeFee0, uint256 tradeFee1) = getEarnedTradeFeeForRange(_subVault.lpts[i], ranges[rangeId]);

            totalFeeAmount0 = totalFeeAmount0.add(tradeFee0);
            totalFeeAmount1 = totalFeeAmount1.add(tradeFee1);
        }
    }

    function getEarnedDailyPremium(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges
    ) public view returns (uint256 marginValue) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            bytes32 rangeId = _subVault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (!_subVault.lpts[i].isCollateral) {
                continue;
            }

            marginValue = marginValue.add(
                PredyMath.mulDiv(
                    perpStatus.premiumGrowthForLender.sub(_subVault.lpts[i].premiumGrowthLast),
                    _subVault.lpts[i].liquidityAmount,
                    Constants.ONE
                )
            );
        }
    }

    function getPaidDailyPremium(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges
    ) public view returns (uint256 marginValue) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            bytes32 rangeId = _subVault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (_subVault.lpts[i].isCollateral) {
                continue;
            }

            marginValue = marginValue.add(
                PredyMath.mulDiv(
                    perpStatus.premiumGrowthForBorrower.sub(_subVault.lpts[i].premiumGrowthLast),
                    _subVault.lpts[i].liquidityAmount,
                    Constants.ONE
                )
            );
        }
    }

    function getPremiumAndFee(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) internal view returns (int256 totalFee0, int256 totalFee1) {
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault memory subVault = _subVaults[_vault.subVaults[i]];

            (int256 fee0, int256 fee1) = getPremiumAndFeeOfSubVault(subVault, _ranges, _context);
            (int256 assetFee0, int256 assetFee1, int256 debtFee0, int256 debtFee1) = getTokenInterestOfSubVault(
                subVault,
                _context
            );

            totalFee0 = totalFee0.add(fee0.add(assetFee0).sub(debtFee0));
            totalFee1 = totalFee1.add(fee1.add(assetFee1).sub(debtFee1));
        }
    }

    function getPremiumAndFeeOfSubVault(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) internal view returns (int256 totalFee0, int256 totalFee1) {
        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_subVault, _ranges);

        totalFee0 = totalFee0.add(int256(fee0));
        totalFee1 = totalFee1.add(int256(fee1));

        if (_context.isMarginZero) {
            totalFee0 = totalFee0.add(int256(getEarnedDailyPremium(_subVault, _ranges)));
            totalFee0 = totalFee0.sub(int256(getPaidDailyPremium(_subVault, _ranges)));
        } else {
            totalFee1 = totalFee1.add(int256(getEarnedDailyPremium(_subVault, _ranges)));
            totalFee1 = totalFee1.sub(int256(getPaidDailyPremium(_subVault, _ranges)));
        }
    }

    function getTokenInterestOfSubVault(DataType.SubVault memory _subVault, DataType.Context memory _context)
        internal
        pure
        returns (
            int256 assetFee0,
            int256 assetFee1,
            int256 debtFee0,
            int256 debtFee1
        )
    {
        assetFee0 = int256(_context.tokenState0.getAssetFee(_subVault.balance0));
        assetFee1 = int256(_context.tokenState1.getAssetFee(_subVault.balance1));
        debtFee0 = int256(_context.tokenState0.getDebtFee(_subVault.balance0));
        debtFee1 = int256(_context.tokenState1.getDebtFee(_subVault.balance1));
    }

    function getPositionOfSubVault(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) internal view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](_subVault.lpts.length);

        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            bytes32 rangeId = _subVault.lpts[i].rangeId;
            DataType.PerpStatus memory range = _ranges[rangeId];
            lpts[i] = DataType.LPT(
                _subVault.lpts[i].isCollateral,
                _subVault.lpts[i].liquidityAmount,
                range.lowerTick,
                range.upperTick
            );
        }

        position = DataType.Position(
            _subVault.id,
            _context.tokenState0.getAssetValue(_subVault.balance0),
            _context.tokenState1.getAssetValue(_subVault.balance1),
            _context.tokenState0.getDebtValue(_subVault.balance0),
            _context.tokenState1.getDebtValue(_subVault.balance1),
            lpts
        );
    }

    function getPositions(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) internal view returns (DataType.Position[] memory positions) {
        positions = new DataType.Position[](_vault.subVaults.length);

        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            positions[i] = getPositionOfSubVault(_subVaults[_vault.subVaults[i]], _ranges, _context);
        }
    }

    function getPosition(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) internal view returns (DataType.Position memory position) {
        return PositionLib.concat(VaultLib.getPositions(_vault, _subVaults, _ranges, _context));
    }

    function getPositionCalculatorParams(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) public view returns (PositionCalculator.PositionCalculatorParams memory params) {
        {
            DataType.Position memory position = getPosition(_vault, _subVaults, _ranges, _context);
            params.asset0 = position.asset0;
            params.asset1 = position.asset1;
            params.debt0 = position.debt0;
            params.debt1 = position.debt1;
            params.lpts = position.lpts;
        }

        (params.marginAmount0, params.marginAmount1) = getMarginAmount(_vault, _subVaults, _ranges, _context);
    }
}
