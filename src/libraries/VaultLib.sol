// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "./PredyMath.sol";
import "../Constants.sol";
import "./LPTMath.sol";
import "./BaseToken.sol";
import "./DataType.sol";

import "forge-std/console.sol";

library VaultLib {
    using SafeMath for uint256;
    using SafeMath for uint128;
    using SignedSafeMath for int256;
    using SafeCast for uint256;

    function depositLPT(
        DataType.SubVault storage _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && _subVault.lpts[i].isCollateral) {
                _subVault.lpts[i].premiumGrowthLast = updateEntryPrice(
                    _subVault.lpts[i].premiumGrowthLast,
                    _subVault.lpts[i].liquidityAmount,
                    ranges[_rangeId].premiumGrowthForLender,
                    _liquidityAmount
                );

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
        bool _isMarginZero,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external returns (uint256 fee0, uint256 fee1) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && _subVault.lpts[i].isCollateral) {
                fee0 = calculateProfit(
                    _subVault.lpts[i].fee0Last,
                    ranges[_rangeId].fee0Growth,
                    _liquidityAmount,
                    FixedPoint128.Q128
                );

                fee1 = calculateProfit(
                    _subVault.lpts[i].fee1Last,
                    ranges[_rangeId].fee1Growth,
                    _liquidityAmount,
                    FixedPoint128.Q128
                );

                {
                    uint256 profit = calculateProfit(
                        _subVault.lpts[i].premiumGrowthLast,
                        ranges[_rangeId].premiumGrowthForLender,
                        _liquidityAmount,
                        1e18
                    );

                    if (_isMarginZero) {
                        fee0 += profit;
                    } else {
                        fee1 += profit;
                    }
                }

                _subVault.lpts[i].liquidityAmount = _subVault.lpts[i].liquidityAmount.sub(_liquidityAmount).toUint128();

                if (_subVault.lpts[i].liquidityAmount == 0) {
                    _subVault.lpts[i] = _subVault.lpts[_subVault.lpts.length - 1];
                    _subVault.lpts.pop();
                }
            }
        }
    }

    function borrowLPT(
        DataType.SubVault storage _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && !_subVault.lpts[i].isCollateral) {
                _subVault.lpts[i].premiumGrowthLast = updateEntryPrice(
                    _subVault.lpts[i].premiumGrowthLast,
                    _subVault.lpts[i].liquidityAmount,
                    ranges[_rangeId].premiumGrowthForBorrower,
                    _liquidityAmount
                );

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
        bool _isMarginZero,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external returns (uint256 fee0, uint256 fee1) {
        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            if (_subVault.lpts[i].rangeId == _rangeId && !_subVault.lpts[i].isCollateral) {
                {
                    uint256 profit = calculateProfit(
                        _subVault.lpts[i].premiumGrowthLast,
                        ranges[_rangeId].premiumGrowthForBorrower,
                        _liquidityAmount,
                        1e18
                    );

                    if (_isMarginZero) {
                        fee0 += profit;
                    } else {
                        fee1 += profit;
                    }
                }

                _subVault.lpts[i].liquidityAmount = _subVault.lpts[i].liquidityAmount.sub(_liquidityAmount).toUint128();

                if (_subVault.lpts[i].liquidityAmount == 0) {
                    _subVault.lpts[i] = _subVault.lpts[_subVault.lpts.length - 1];
                    _subVault.lpts.pop();
                }
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
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) external view returns (DataType.VaultStatus memory) {
        DataType.SubVaultStatus[] memory subVaults = new DataType.SubVaultStatus[](_vault.numSubVaults);

        for (uint256 i = 0; i < _vault.numSubVaults; i++) {
            DataType.VaultStatusAmount memory statusAmount = getVaultStatusAmount(
                _vault.subVaults[i],
                _ranges,
                _context,
                _sqrtPrice
            );
            DataType.VaultStatusValue memory statusValue = getVaultStatusValue(
                statusAmount,
                _sqrtPrice,
                _context.isMarginZero
            );

            subVaults[i] = DataType.SubVaultStatus(statusValue, statusAmount);
        }

        return DataType.VaultStatus(getMarginValue(_vault, _context, _sqrtPrice), subVaults);
    }

    function getMarginValue(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) public view returns (uint256) {
        uint256 price = LPTMath.decodeSqrtPriceX96(_context.isMarginZero, _sqrtPrice);

        if (_context.isMarginZero) {
            return PredyMath.mulDiv(_vault.marginAmount1, price, 1e18).add(_vault.marginAmount0);
        } else {
            return PredyMath.mulDiv(_vault.marginAmount0, price, 1e18).add(_vault.marginAmount1);
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

    function getDebtPositionValue(
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) external view returns (uint256 debtValue) {
        uint256 price = LPTMath.decodeSqrtPriceX96(_context.isMarginZero, _sqrtPrice);

        for (uint256 i = 0; i < _vault.numSubVaults; i++) {
            debtValue += getDebtPositionValue(_vault.subVaults[i], _ranges, _context, _sqrtPrice, price);
        }
    }

    function getDebtPositionValue(
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice,
        uint256 _price
    ) internal view returns (uint256) {
        (uint256 totalAmount0, uint256 totalAmount1) = getDebtPositionAmounts(_subVault, _ranges, _context, _sqrtPrice);

        uint256 paidPremium = getPaidDailyPremium(_subVault, _ranges);

        if (_context.isMarginZero) {
            return (PredyMath.mulDiv(totalAmount1, _price, 1e18).add(totalAmount0).sub(paidPremium));
        } else {
            return (PredyMath.mulDiv(totalAmount0, _price, 1e18).add(totalAmount1).sub(paidPremium));
        }
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
        totalAmount0 = totalAmount0.add(BaseToken.getCollateralValue(_context.tokenState0, _subVault.balance0));
        totalAmount1 = totalAmount1.add(BaseToken.getCollateralValue(_context.tokenState1, _subVault.balance1));

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
        totalAmount0 = totalAmount0.add(BaseToken.getDebtValue(_context.tokenState0, _subVault.balance0));
        totalAmount1 = totalAmount1.add(BaseToken.getDebtValue(_context.tokenState1, _subVault.balance1));

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
            totalAmount0 = PredyMath.mulDiv(
                (ranges[rangeId].fee0Growth.sub(_subVault.lpts[i].fee0Last)),
                _subVault.lpts[i].liquidityAmount,
                FixedPoint128.Q128
            );
            totalAmount1 = PredyMath.mulDiv(
                (ranges[rangeId].fee1Growth.sub(_subVault.lpts[i].fee1Last)),
                _subVault.lpts[i].liquidityAmount,
                FixedPoint128.Q128
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
                        1e18
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
                        1e18
                    )
                );
            }
        }
    }

    function getPositionOfSubVault(
        uint256 _subVaultIndex,
        DataType.SubVault memory _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) public view returns (DataType.Position memory position) {
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

        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_subVault, _ranges);
        (uint256 debtAmount0, uint256 debtAmount1) = (
            BaseToken.getDebtValue(_context.tokenState0, _subVault.balance0),
            BaseToken.getDebtValue(_context.tokenState1, _subVault.balance1)
        );

        if (_context.isMarginZero) {
            fee0 = fee0.add(getEarnedDailyPremium(_subVault, _ranges));
            debtAmount0 = debtAmount0.add(getPaidDailyPremium(_subVault, _ranges));
        } else {
            fee1 = fee1.add(getEarnedDailyPremium(_subVault, _ranges));
            debtAmount1 = debtAmount1.add(getPaidDailyPremium(_subVault, _ranges));
        }

        position = DataType.Position(
            _subVaultIndex,
            BaseToken.getCollateralValue(_context.tokenState0, _subVault.balance0).add(fee0),
            BaseToken.getCollateralValue(_context.tokenState1, _subVault.balance1).add(fee1),
            debtAmount0,
            debtAmount1,
            lpts
        );
    }

    function getPositions(
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) public view returns (DataType.Position[] memory positions) {
        positions = new DataType.Position[](_vault.numSubVaults);

        for (uint256 i = 0; i < _vault.numSubVaults; i++) {
            positions[i] = getPositionOfSubVault(i, _vault.subVaults[i], _ranges, _context);
        }
    }
}
