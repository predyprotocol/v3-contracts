// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
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
    using SafeCast for uint256;

    function depositLPT(
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            if (_vault.lpts[i].rangeId == _rangeId && _vault.lpts[i].isCollateral) {
                _vault.lpts[i].liquidityAmount = _vault.lpts[i].liquidityAmount.add(_liquidityAmount).toUint128();

                return;
            }
        }

        _vault.lpts.push(
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
        DataType.Vault storage _vault,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            if (_vault.lpts[i].rangeId == _rangeId && _vault.lpts[i].isCollateral) {
                _vault.lpts[i].liquidityAmount = _vault.lpts[i].liquidityAmount.sub(_liquidityAmount).toUint128();

                if (_vault.lpts[i].liquidityAmount == 0) {
                    _vault.lpts[i] = _vault.lpts[_vault.lpts.length - 1];
                    _vault.lpts.pop();
                }
                return;
            }
        }
    }

    function borrowLPT(
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage ranges,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            if (_vault.lpts[i].rangeId == _rangeId && !_vault.lpts[i].isCollateral) {
                _vault.lpts[i].liquidityAmount = _vault.lpts[i].liquidityAmount.add(_liquidityAmount).toUint128();
                return;
            }
        }

        _vault.lpts.push(
            DataType.LPTState(false, _rangeId, _liquidityAmount, ranges[_rangeId].premiumGrowthForBorrower, 0, 0)
        );
    }

    function repayLPT(
        DataType.Vault storage _vault,
        bytes32 _rangeId,
        uint128 _liquidityAmount
    ) external {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            if (_vault.lpts[i].rangeId == _rangeId && !_vault.lpts[i].isCollateral) {
                _vault.lpts[i].liquidityAmount = _vault.lpts[i].liquidityAmount.sub(_liquidityAmount).toUint128();
                console.log(2, _vault.lpts[i].liquidityAmount, _liquidityAmount);

                if (_vault.lpts[i].liquidityAmount == 0) {
                    _vault.lpts[i] = _vault.lpts[_vault.lpts.length - 1];
                    _vault.lpts.pop();
                }
                return;
            }
        }
    }

    function getCollateralPositionValue(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) external view returns (uint256) {
        (uint256 totalAmount0, uint256 totalAmount1) = getCollateralPositionAmounts(_vault, _ranges, _context);

        {
            (uint256 amount0, uint256 amount1) = getLPTPositionAmounts(_vault, _ranges, _sqrtPrice, true);

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }

        uint256 price = LPTMath.decodeSqrtPriceX96(_context.isMarginZero, _sqrtPrice);

        if (_context.isMarginZero) {
            return (PredyMath.mulDiv(totalAmount1, price, 1e18).add(totalAmount0));
        } else {
            return (PredyMath.mulDiv(totalAmount0, price, 1e18).add(totalAmount1));
        }
    }

    function getDebtPositionValue(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context,
        uint160 _sqrtPrice
    ) external view returns (uint256) {
        (uint256 totalAmount0, uint256 totalAmount1) = getDebtPositionAmounts(_vault, _ranges, _context);

        {
            (uint256 amount0, uint256 amount1) = getLPTPositionAmounts(_vault, _ranges, _sqrtPrice, false);

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }

        uint256 price = LPTMath.decodeSqrtPriceX96(_context.isMarginZero, _sqrtPrice);

        if (_context.isMarginZero) {
            return (PredyMath.mulDiv(totalAmount1, price, 1e18).add(totalAmount0));
        } else {
            return (PredyMath.mulDiv(totalAmount0, price, 1e18).add(totalAmount1));
        }
    }

    /**
     * @notice latest collateral amounts
     */
    function getCollateralPositionAmounts(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) public view returns (uint256 totalAmount0, uint256 totalAmount1) {
        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_vault, _ranges);
        totalAmount0 = totalAmount0.add(fee0);
        totalAmount1 = totalAmount1.add(fee1);

        totalAmount0 = totalAmount0.add(BaseToken.getCollateralValue(_context.tokenState0, _vault.balance0));
        totalAmount1 = totalAmount1.add(BaseToken.getCollateralValue(_context.tokenState1, _vault.balance1));

        uint256 earnedPremium = getEarnedDailyPremium(_vault, _ranges);

        if (_context.isMarginZero) {
            totalAmount0 = totalAmount0.add(earnedPremium);
        } else {
            totalAmount1 = totalAmount1.add(earnedPremium);
        }
    }

    function getDebtPositionAmounts(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) public view returns (uint256 totalAmount0, uint256 totalAmount1) {
        totalAmount0 = totalAmount0.add(BaseToken.getDebtValue(_context.tokenState0, _vault.balance0));
        totalAmount1 = totalAmount1.add(BaseToken.getDebtValue(_context.tokenState1, _vault.balance1));

        uint256 paidPremium = getPaidDailyPremium(_vault, _ranges);

        if (_context.isMarginZero) {
            totalAmount0 = totalAmount0.add(paidPremium);
        } else {
            totalAmount1 = totalAmount1.add(paidPremium);
        }
    }

    function getLPTPositionAmounts(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint160 _sqrtPrice,
        bool _isCollateral
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            if (_isCollateral != _vault.lpts[i].isCollateral) {
                continue;
            }

            (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidity(
                _sqrtPrice,
                _ranges[_vault.lpts[i].rangeId].lowerTick,
                _ranges[_vault.lpts[i].rangeId].upperTick,
                _vault.lpts[i].liquidityAmount
            );

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }
    }

    function getEarnedTradeFee(DataType.Vault memory vault, mapping(bytes32 => DataType.PerpStatus) storage ranges)
        public
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        for (uint256 i = 0; i < vault.lpts.length; i++) {
            if (!vault.lpts[i].isCollateral) {
                continue;
            }
            bytes32 rangeId = vault.lpts[i].rangeId;
            totalAmount0 = PredyMath.mulDiv(
                (ranges[rangeId].fee0Growth.sub(vault.lpts[i].fee0Last)),
                vault.lpts[i].liquidityAmount,
                FixedPoint128.Q128
            );
            totalAmount1 = PredyMath.mulDiv(
                (ranges[rangeId].fee1Growth.sub(vault.lpts[i].fee1Last)),
                vault.lpts[i].liquidityAmount,
                FixedPoint128.Q128
            );
        }
    }

    function getEarnedDailyPremium(DataType.Vault memory _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges)
        public
        view
        returns (uint256 marginValue)
    {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            bytes32 rangeId = _vault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (_vault.lpts[i].isCollateral) {
                marginValue = marginValue.add(
                    PredyMath.mulDiv(
                        (perpStatus.premiumGrowthForLender.sub(_vault.lpts[i].premiumGrowthLast)),
                        _vault.lpts[i].liquidityAmount,
                        1e18
                    )
                );
            }
        }
    }

    function getPaidDailyPremium(DataType.Vault memory _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges)
        public
        view
        returns (uint256 marginValue)
    {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            bytes32 rangeId = _vault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (!_vault.lpts[i].isCollateral) {
                marginValue = marginValue.add(
                    PredyMath.mulDiv(
                        (perpStatus.premiumGrowthForBorrower.sub(_vault.lpts[i].premiumGrowthLast)),
                        _vault.lpts[i].liquidityAmount,
                        1e18
                    )
                );
            }
        }
    }

    function getPosition(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context memory _context
    ) public view returns (DataType.Position memory position) {
        DataType.LPT[] memory lpts = new DataType.LPT[](_vault.lpts.length);

        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            bytes32 rangeId = _vault.lpts[i].rangeId;
            DataType.PerpStatus memory range = _ranges[rangeId];
            lpts[i] = DataType.LPT(
                _vault.lpts[i].isCollateral,
                _vault.lpts[i].liquidityAmount,
                range.lowerTick,
                range.upperTick
            );
        }

        (uint256 collateralAmount0, uint256 collateralAmount1) = getCollateralPositionAmounts(
            _vault,
            _ranges,
            _context
        );
        (uint256 debtAmount0, uint256 debtAmount1) = getDebtPositionAmounts(_vault, _ranges, _context);

        // console.log(1, collateralAmount0, collateralAmount1);
        // console.log(1, debtAmount0, debtAmount1);

        position = DataType.Position(collateralAmount0, collateralAmount1, debtAmount0, debtAmount1, lpts);
    }
}
