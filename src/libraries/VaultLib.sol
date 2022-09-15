// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "./PredyMath.sol";
import "./Constants.sol";
import "./LPTMath.sol";
import "./BaseToken.sol";
import "./DataType.sol";
import "./PositionCalculator.sol";
import "./PositionLib.sol";

/**
 * Error Codes
 * V0: no permission
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
     * @param _subVaultIndex index of sub-vault in the vault to add
     */
    function addSubVault(
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context storage _context,
        uint256 _subVaultIndex
    ) internal returns (DataType.SubVault storage) {
        if (_subVaultIndex == _vault.subVaults.length) {
            uint256 subVaultId = _context.nextSubVaultId;

            _context.nextSubVaultId += 1;

            _vault.subVaults.push(subVaultId);

            emit SubVaultCreated(_vault.vaultId, _subVaultIndex, subVaultId);

            _subVaults[subVaultId].id = subVaultId;

            return _subVaults[subVaultId];
        } else if (_subVaultIndex < _vault.subVaults.length) {
            uint256 subVaultId = _vault.subVaults[_subVaultIndex];

            return _subVaults[subVaultId];
        } else {
            revert("V0");
        }
    }

    /**
     * @notice remove sub-vault from the vault
     * @param _vault vault object
     * @param _subVaultIndex index of sub-vault in the vault to remove
     */
    function removeSubVault(DataType.Vault storage _vault, uint256 _subVaultIndex) internal {
        uint256 subVaultId = _vault.subVaults[_subVaultIndex];

        _vault.subVaults[_subVaultIndex] = _vault.subVaults[_vault.subVaults.length - 1];
        _vault.subVaults.pop();

        emit SubVaultRemoved(_vault.vaultId, _subVaultIndex, subVaultId);
    }

    function depositLPT(
        DataType.SubVault storage _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && _subVault.lpts[i].isCollateral) {
                _subVault.lpts[i].liquidityAmount = _subVault.lpts[i].liquidityAmount.add(_liquidityAmount).toUint128();

                return;
            }
        }

        _subVault.lpts.push(
            DataType.LPTState(
                true,
                _rangeId,
                _liquidityAmount,
                ranges[_rangeId].premiumGrowthForLender,
                ranges[_rangeId].fee0Growth,
                ranges[_rangeId].fee1Growth
            )
        );
    }

    function withdrawLPT(
        DataType.SubVault storage _subVault,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && _subVault.lpts[i].isCollateral) {
                _subVault.lpts[i].liquidityAmount = _subVault.lpts[i].liquidityAmount.sub(_liquidityAmount).toUint128();

                if (_subVault.lpts[i].liquidityAmount == 0) {
                    _subVault.lpts[i] = _subVault.lpts[_subVault.lpts.length - 1];
                    _subVault.lpts.pop();
                }

                return;
            }
        }
    }

    function borrowLPT(
        DataType.SubVault storage _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && !_subVault.lpts[i].isCollateral) {
                _subVault.lpts[i].liquidityAmount = _subVault.lpts[i].liquidityAmount.add(_liquidityAmount).toUint128();
                return;
            }
        }

        _subVault.lpts.push(
            DataType.LPTState(false, _rangeId, _liquidityAmount, ranges[_rangeId].premiumGrowthForBorrower, 0, 0)
        );
    }

    function repayLPT(
        DataType.SubVault storage _subVault,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) internal {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && !_subVault.lpts[i].isCollateral) {
                _subVault.lpts[i].liquidityAmount = _subVault.lpts[i].liquidityAmount.sub(_liquidityAmount).toUint128();

                if (_subVault.lpts[i].liquidityAmount == 0) {
                    _subVault.lpts[i] = _subVault.lpts[_subVault.lpts.length - 1];
                    _subVault.lpts.pop();
                }

                return;
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
            DataType.VaultStatusAmount memory statusAmount = getVaultStatusAmount(
                _subVaults[_vault.subVaults[i]],
                _ranges,
                _context,
                _sqrtPrice
            );
            DataType.VaultStatusValue memory statusValue = getVaultStatusValue(
                statusAmount,
                _sqrtPrice,
                _context.isMarginZero
            );

            subVaultsStatus[i] = DataType.SubVaultStatus(statusValue, statusAmount);
        }

        return
            DataType.VaultStatus(
                getPositionValue(
                    VaultLib.getPosition(_vault, _subVaults, _ranges, _context),
                    _sqrtPrice,
                    _context.isMarginZero
                ),
                getMarginValue(_vault, _subVaults, _ranges, _context, _sqrtPrice),
                PositionCalculator.calculateMinCollateral(
                    PositionLib.concat(getPositions(_vault, _subVaults, _ranges, _context)),
                    _sqrtPrice,
                    _context.isMarginZero
                ),
                subVaultsStatus
            );
    }

    function getMarginValue(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) internal view returns (int256) {
        uint256 price = LPTMath.decodeSqrtPriceX96(_context.isMarginZero, _sqrtPrice);

        (int256 fee0, int256 fee1) = getPremiumAndFee(_vault, _subVaults, _ranges, _context);

        int256 marginAmount0 = int256(_vault.marginAmount0) + fee0;
        int256 marginAmount1 = int256(_vault.marginAmount1) + fee1;

        if (_context.isMarginZero) {
            return marginAmount0.add(calculateUnderlyingValue(marginAmount1, price));
        } else {
            return marginAmount1.add(calculateUnderlyingValue(marginAmount0, price));
        }
    }

    function getPositionValue(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256) {
        return PositionCalculator.calculateValue(_position, _sqrtPrice, _isMarginZero, false);
    }

    function getVaultValue(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        DataType.Position memory _position,
        uint160 _sqrtPrice
    ) internal view returns (int256) {
        return
            getMarginValue(_vault, _subVaults, _ranges, _context, _sqrtPrice) +
            PositionCalculator.calculateValue(_position, _sqrtPrice, _context.isMarginZero, false);
    }

    function calculateUnderlyingValue(int256 _amount, uint256 _price) internal pure returns (int256) {
        if (_amount >= 0) {
            return _amount.mul(int256(_price)).div(1e18).div(2);
        } else {
            return _amount.mul(int256(_price)).div(1e18).mul(2);
        }
    }

    function getVaultStatusValue(
        DataType.VaultStatusAmount memory statusAmount,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (DataType.VaultStatusValue memory) {
        uint256 price = LPTMath.decodeSqrtPriceX96(_isMarginZero, _sqrtPrice);

        int256 premium = int256(statusAmount.receivedPremium).sub(int256(statusAmount.paidpremium));

        if (_isMarginZero) {
            return
                DataType.VaultStatusValue(
                    PredyMath.mulDiv(statusAmount.collateralAmount1, price, 1e18).add(statusAmount.collateralAmount0),
                    PredyMath.mulDiv(statusAmount.debtAmount1, price, 1e18).add(statusAmount.debtAmount0),
                    int256(
                        PredyMath.mulDiv(statusAmount.receivedTradeAmount1, price, 1e18).add(
                            statusAmount.receivedTradeAmount0
                        )
                    ).add(premium)
                );
        } else {
            return
                DataType.VaultStatusValue(
                    PredyMath.mulDiv(statusAmount.collateralAmount0, price, 1e18).add(statusAmount.collateralAmount1),
                    PredyMath.mulDiv(statusAmount.debtAmount0, price, 1e18).add(statusAmount.debtAmount1),
                    int256(
                        PredyMath.mulDiv(statusAmount.receivedTradeAmount0, price, 1e18).add(
                            statusAmount.receivedTradeAmount1
                        )
                    ).add(premium)
                );
        }
    }

    function getVaultStatusAmount(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) internal view returns (DataType.VaultStatusAmount memory) {
        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_subVault, _ranges);

        (uint256 collateralAmount0, uint256 collateralAmount1) = getCollateralPositionAmounts(
            _subVault,
            _ranges,
            _context,
            _sqrtPrice
        );
        (uint256 debtAmount0, uint256 debtAmount1) = getDebtPositionAmounts(_subVault, _ranges, _context, _sqrtPrice);

        return
            DataType.VaultStatusAmount(
                collateralAmount0,
                collateralAmount1,
                debtAmount0,
                debtAmount1,
                fee0,
                fee1,
                getEarnedDailyPremium(_subVault, _ranges),
                getPaidDailyPremium(_subVault, _ranges)
            );
    }

    function isDebtZero(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context memory _context
    ) external view returns (bool) {
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            if (!isDebtZeroInSubVault(_subVaults[_vault.subVaults[i]], _context)) {
                return false;
            }
        }

        return true;
    }

    function isDebtZeroInSubVault(DataType.SubVault memory _subVault, DataType.Context memory _context)
        internal
        pure
        returns (bool)
    {
        if (_subVault.isCompound) {
            if (
                _context.tokenState0.getDebtValue(_subVault.balance0) != 0 ||
                _context.tokenState1.getDebtValue(_subVault.balance1) != 0
            ) {
                return false;
            }
        } else {
            if (_subVault.debtAmount0 != 0 || _subVault.debtAmount1 != 0) {
                return false;
            }
        }

        if (_subVault.lpts.length > 0) {
            return false;
        }

        return true;
    }

    /**
     * @notice latest collateral amounts
     */
    function getCollateralPositionAmounts(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        if (_subVault.isCompound) {
            totalAmount0 = totalAmount0.add(_context.tokenState0.getCollateralValue(_subVault.balance0));
            totalAmount1 = totalAmount1.add(_context.tokenState1.getCollateralValue(_subVault.balance1));
        } else {
            totalAmount0 = totalAmount0.add(_subVault.collateralAmount0);
            totalAmount1 = totalAmount1.add(_subVault.collateralAmount1);
        }

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
        if (_subVault.isCompound) {
            totalAmount0 = totalAmount0.add(_context.tokenState0.getDebtValue(_subVault.balance0));
            totalAmount1 = totalAmount1.add(_context.tokenState1.getDebtValue(_subVault.balance1));
        } else {
            totalAmount0 = totalAmount0.add(_subVault.debtAmount0);
            totalAmount1 = totalAmount1.add(_subVault.debtAmount1);
        }

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
            if (_isCollateral != _subVault.lpts[i].isCollateral) {
                continue;
            }

            (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidity(
                _sqrtPrice,
                _ranges[_subVault.lpts[i].rangeId].lowerTick,
                _ranges[_subVault.lpts[i].rangeId].upperTick,
                _subVault.lpts[i].liquidityAmount
            );

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }
    }

    function getEarnedTradeFee(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges
    ) public view returns (uint256 totalAmount0, uint256 totalAmount1) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (!_subVault.lpts[i].isCollateral) {
                continue;
            }

            bytes32 rangeId = _subVault.lpts[i].rangeId;

            totalAmount0 = totalAmount0.add(
                PredyMath.mulDiv(
                    (ranges[rangeId].fee0Growth.sub(_subVault.lpts[i].fee0Last)),
                    _subVault.lpts[i].liquidityAmount,
                    Constants.ONE
                )
            );
            totalAmount1 = totalAmount1.add(
                PredyMath.mulDiv(
                    (ranges[rangeId].fee1Growth.sub(_subVault.lpts[i].fee1Last)),
                    _subVault.lpts[i].liquidityAmount,
                    Constants.ONE
                )
            );
        }
    }

    function getEarnedDailyPremium(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges
    ) public view returns (uint256 marginValue) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            bytes32 rangeId = _subVault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (_subVault.lpts[i].isCollateral) {
                marginValue = marginValue.add(
                    PredyMath.mulDiv(
                        (perpStatus.premiumGrowthForLender.sub(_subVault.lpts[i].premiumGrowthLast)),
                        _subVault.lpts[i].liquidityAmount,
                        Constants.ONE
                    )
                );
            }
        }
    }

    function getPaidDailyPremium(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges
    ) public view returns (uint256 marginValue) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            bytes32 rangeId = _subVault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (!_subVault.lpts[i].isCollateral) {
                marginValue = marginValue.add(
                    PredyMath.mulDiv(
                        (perpStatus.premiumGrowthForBorrower.sub(_subVault.lpts[i].premiumGrowthLast)),
                        _subVault.lpts[i].liquidityAmount,
                        Constants.ONE
                    )
                );
            }
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
            (
                int256 collateralFee0,
                int256 collateralFee1,
                int256 debtFee0,
                int256 debtFee1
            ) = getTokenInterestOfSubVault(subVault, _context);

            totalFee0 = totalFee0.add(fee0.add(collateralFee0).sub(debtFee0));
            totalFee1 = totalFee1.add(fee1.add(collateralFee1).sub(debtFee1));
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
            int256 collateralFee0,
            int256 collateralFee1,
            int256 debtFee0,
            int256 debtFee1
        )
    {
        if (!_subVault.isCompound) {
            collateralFee0 = int256(_context.tokenState0.getCollateralValue(_subVault.balance0)).sub(
                int256(_subVault.collateralAmount0)
            );
            collateralFee1 = int256(_context.tokenState1.getCollateralValue(_subVault.balance1)).sub(
                int256(_subVault.collateralAmount1)
            );
            debtFee0 = int256(_context.tokenState0.getDebtValue(_subVault.balance0)).sub(int256(_subVault.debtAmount0));
            debtFee1 = int256(_context.tokenState1.getDebtValue(_subVault.balance1)).sub(int256(_subVault.debtAmount1));
        }
    }

    function getPositionOfSubVault(
        uint256 _subVaultIndex,
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

        if (_subVault.isCompound) {
            position = DataType.Position(
                _subVaultIndex,
                _context.tokenState0.getCollateralValue(_subVault.balance0),
                _context.tokenState1.getCollateralValue(_subVault.balance1),
                _context.tokenState0.getDebtValue(_subVault.balance0),
                _context.tokenState1.getDebtValue(_subVault.balance1),
                lpts
            );
        } else {
            position = DataType.Position(
                _subVaultIndex,
                _subVault.collateralAmount0,
                _subVault.collateralAmount1,
                _subVault.debtAmount0,
                _subVault.debtAmount1,
                lpts
            );
        }
    }

    function getPositions(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) internal view returns (DataType.Position[] memory positions) {
        positions = new DataType.Position[](_vault.subVaults.length);

        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            positions[i] = getPositionOfSubVault(i, _subVaults[_vault.subVaults[i]], _ranges, _context);
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
}
