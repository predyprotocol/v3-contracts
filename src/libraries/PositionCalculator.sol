// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";
import "./LPTMath.sol";

library PositionCalculator {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    uint256 internal constant Q96 = 0x1000000000000000000000000;
    // sqrt{1.24} = 1.11355287257
    uint160 internal constant UPPER_E8 = 111355287;
    // sqrt{1/1.24} = 0.89802651013
    uint160 internal constant LOWER_E8 = 89802651;

    /**
     * @notice Calculates Min. Collateral for a position.
     * MinCollateral = 0.01 * DebtValue - minValue + positionValue
     * @param _position position object
     * @param _sqrtPrice square root price to calculate
     * @param _isMarginZero whether the stable token is token0 or token1
     */
    function calculateMinCollateral(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) external pure returns (int256) {
        int256 positionValue = calculateValue(_position, _sqrtPrice, _isMarginZero);

        int256 minValue = calculateMinValue(_position, _sqrtPrice, _isMarginZero);

        (, uint256 debtValue) = calculateCollateralAndDebtValue(_position, _sqrtPrice, _isMarginZero);

        return int256(debtValue).div(100).sub(minValue).add(positionValue);
    }

    /**
     * @notice Calculates square root of min price (a * b)^(1/4)
     * P_{min}^(1/2) = (a * b)^(1/4)
     */
    function calculateMinSqrtPrice(int24 _lowerTick, int24 _upperTick) internal pure returns (uint160) {
        return uint160(TickMath.getSqrtRatioAtTick((_lowerTick + _upperTick) / 2));
    }

    /**
     * @notice Calculates minValue.
     * MinValue is minimal value of following values.
     * 1. value of at P*1.24
     * 2. value of at P/1.24
     * 3. values of at P_{min} of LPTs
     */
    function calculateMinValue(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256 minValue) {
        minValue = type(int256).max;
        uint160 sqrtPriceLower = (LOWER_E8 * _sqrtPrice) / 1e8;
        uint160 sqrtPriceUpper = (UPPER_E8 * _sqrtPrice) / 1e8;

        require(TickMath.MIN_SQRT_RATIO < _sqrtPrice && _sqrtPrice < TickMath.MAX_SQRT_RATIO, "PC0");

        if (sqrtPriceLower < TickMath.MIN_SQRT_RATIO) {
            sqrtPriceLower = TickMath.MIN_SQRT_RATIO;
        }

        if (sqrtPriceUpper > TickMath.MAX_SQRT_RATIO) {
            sqrtPriceUpper = TickMath.MAX_SQRT_RATIO;
        }

        {
            // 1. check value of at P*1.24
            int256 value = calculateValue(_position, sqrtPriceUpper, _isMarginZero);
            if (minValue > value) {
                minValue = value;
            }
        }

        {
            // 2. check value of at P/1.24
            int256 value = calculateValue(_position, sqrtPriceLower, _isMarginZero);
            if (minValue > value) {
                minValue = value;
            }
        }

        // 3. check values of at P_{min} of LPTs
        for (uint256 i = 0; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];

            if (!lpt.isCollateral) {
                uint160 sqrtPrice = calculateMinSqrtPrice(lpt.upperTick, lpt.lowerTick);

                if (sqrtPrice < sqrtPriceLower || sqrtPriceUpper < sqrtPrice) {
                    continue;
                }

                int256 value = calculateValue(_position, sqrtPrice, _isMarginZero);

                if (minValue > value) {
                    minValue = value;
                }
            }
        }
    }

    function calculateValue(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        bool isMarginZero
    ) internal pure returns (int256 value) {
        (uint256 collateralValue, uint256 debtValue) = calculateCollateralAndDebtValue(
            _position,
            _sqrtPrice,
            isMarginZero
        );

        return int256(collateralValue) - int256(debtValue);
    }

    function calculateCollateralAndDebtValue(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        bool isMarginZero
    ) internal pure returns (uint256 collateralValue, uint256 debtValue) {
        uint256 collateralAmount0 = _position.collateral0;
        uint256 collateralAmount1 = _position.collateral1;
        uint256 debtAmount0 = _position.debt0;
        uint256 debtAmount1 = _position.debt1;

        for (uint256 i = 0; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];

            uint160 sqrtLowerPrice = TickMath.getSqrtRatioAtTick(lpt.lowerTick);
            uint160 sqrtUpperPrice = TickMath.getSqrtRatioAtTick(lpt.upperTick);

            if (!lpt.isCollateral && sqrtLowerPrice <= _sqrtPrice && _sqrtPrice <= sqrtUpperPrice) {
                debtAmount1 = debtAmount1.add(
                    (
                        uint256(lpt.liquidity).mul(
                            TickMath.getSqrtRatioAtTick(lpt.upperTick) - TickMath.getSqrtRatioAtTick(lpt.lowerTick)
                        )
                    ).div(Q96)
                );
                continue;
            }

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                sqrtLowerPrice,
                sqrtUpperPrice,
                lpt.liquidity
            );

            if (lpt.isCollateral) {
                collateralAmount0 = collateralAmount0.add(amount0);
                collateralAmount1 = collateralAmount1.add(amount1);
            } else {
                debtAmount0 = debtAmount0.add(amount0);
                debtAmount1 = debtAmount1.add(amount1);
            }
        }

        uint256 price = LPTMath.decodeSqrtPriceX96(isMarginZero, _sqrtPrice);

        if (isMarginZero) {
            collateralValue = collateralAmount0.add(collateralAmount1.mul(price).div(1e18));
            debtValue = debtAmount0.add(debtAmount1.mul(price).div(1e18));
        } else {
            collateralValue = collateralAmount0.mul(price).div(1e18).add(collateralAmount1);
            debtValue = debtAmount0.mul(price).div(1e18).add(debtAmount1);
        }
    }
}
