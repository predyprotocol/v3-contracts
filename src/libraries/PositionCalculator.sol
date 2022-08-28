// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";

library PositionCalculator {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    uint256 internal constant Q96 = 0x1000000000000000000000000;
    // sqrt{1.25} = 1.11803398875
    uint160 internal constant UPPER_E8 = 111803399;
    // sqrt{1/1.25} = 0.894427191
    uint160 internal constant LOWER_E8 = 89442719;

    /**
     * @notice Calculates required collateral for a position.
     * RequiredCollateral = 0.01*DebtValue - minValue
     * @param _position position object
     * @param _sqrtPrice square root price to calculate
     * @param _isMarginZero whether the stable token is token0 or token1
     */
    function calculateRequiredCollateral(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256) {
        int256 minValue = calculateMinValue(_position, _sqrtPrice, _isMarginZero);

        (, uint256 debtValue) = calculateCollateralAndDebtValue(_position, _sqrtPrice, _isMarginZero);

        return int256(debtValue) / 100 - minValue;
    }

    /**
     * @notice Calculates min price (a * b)^(1/4)
     */
    function calculateMinSqrtPrice(int24 _lowerTick, int24 _upperTick) internal pure returns (uint160) {
        return uint160(TickMath.getSqrtRatioAtTick((_lowerTick + _upperTick) / 2));
    }

    function calculateMinValue(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256 minValue) {
        minValue = type(int256).max;
        uint160 sqrtPriceLower = (LOWER_E8 * _sqrtPrice) / 1e8;
        uint160 sqrtPriceUpper = (UPPER_E8 * _sqrtPrice) / 1e8;

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

        {
            int256 value = calculateValue(_position, sqrtPriceUpper, _isMarginZero);
            if (minValue > value) {
                minValue = value;
            }
        }

        {
            int256 value = calculateValue(_position, sqrtPriceLower, _isMarginZero);
            if (minValue > value) {
                minValue = value;
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
                debtAmount1 +=
                    (lpt.liquidity *
                        (TickMath.getSqrtRatioAtTick(lpt.upperTick) - TickMath.getSqrtRatioAtTick(lpt.lowerTick))) /
                    Q96;
                continue;
            }

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                sqrtLowerPrice,
                sqrtUpperPrice,
                lpt.liquidity
            );

            if (lpt.isCollateral) {
                collateralAmount0 += (amount0);
                collateralAmount1 += (amount1);
            } else {
                debtAmount0 += (amount0);
                debtAmount1 += (amount1);
            }
        }

        uint256 price = decodeSqrtPriceX96(isMarginZero, _sqrtPrice);

        if (isMarginZero) {
            collateralValue = collateralAmount0 + (collateralAmount1 * price) / 1e18;
            debtValue = debtAmount0 + (debtAmount1 * price) / 1e18;
        } else {
            collateralValue = (collateralAmount0 * price) / 1e18 + collateralAmount1;
            debtValue = (debtAmount0 * price) / 1e18 + debtAmount1;
        }
    }

    function decodeSqrtPriceX96(bool isMarginZero, uint256 sqrtPriceX96) internal pure returns (uint256 price) {
        uint256 scaler = 1e18; //10**ERC20(token0).decimals();

        if (isMarginZero) {
            price = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**(96 * 2)) / (scaler));
            if (price == 0) return 1e36;
            price = 1e36 / price;
        } else {
            price = (FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**96)) * scaler) / uint256(2**96);
        }

        if (price > 1e36) price = 1e36;
        else if (price == 0) price = 1;
    }
}
