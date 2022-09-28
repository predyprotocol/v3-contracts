// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
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

    struct PositionCalculatorParams {
        int256 marginAmount0;
        int256 marginAmount1;
        uint256 asset0;
        uint256 asset1;
        uint256 debt0;
        uint256 debt1;
        DataType.LPT[] lpts;
    }

    /**
     * @notice Calculates Min. Deposit for a vault.
     * MinDeposit = vaultPositionValue - minValue + 0.02 * DebtValue
     * @param _params position object
     * @param _sqrtPrice square root price to calculate
     * @param _isMarginZero whether the stable token is token0 or token1
     */
    function calculateMinDeposit(
        PositionCalculatorParams memory _params,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256) {
        int256 vaultPositionValue = calculateValue(_params, _sqrtPrice, _isMarginZero);

        int256 minValue = calculateMinValue(_params, _sqrtPrice, _isMarginZero);

        (, , uint256 debtValue) = calculateCollateralAndDebtValue(_params, _sqrtPrice, _isMarginZero, false);

        return int256(debtValue).div(50).add(vaultPositionValue).sub(minValue);
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
        PositionCalculatorParams memory _position,
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
                uint160 minSqrtPrice = calculateMinSqrtPrice(lpt.upperTick, lpt.lowerTick);

                if (minSqrtPrice < sqrtPriceLower || sqrtPriceUpper < minSqrtPrice) {
                    continue;
                }

                int256 value = calculateValue(_position, minSqrtPrice, _isMarginZero, true);

                if (minValue > value) {
                    minValue = value;
                }
            }
        }
    }

    function calculateValue(
        PositionCalculatorParams memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256 value) {
        return calculateValue(_position, _sqrtPrice, _isMarginZero, false);
    }

    function calculateValue(
        PositionCalculatorParams memory _position,
        uint160 _sqrtPrice,
        bool isMarginZero,
        bool _isMinPrice
    ) internal pure returns (int256 value) {
        (int256 marginValue, uint256 assetValue, uint256 debtValue) = calculateCollateralAndDebtValue(
            _position,
            _sqrtPrice,
            isMarginZero,
            _isMinPrice
        );

        return marginValue + int256(assetValue) - int256(debtValue);
    }

    function calculateCollateralAndDebtValue(
        PositionCalculatorParams memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero,
        bool _isMinPrice
    )
        internal
        pure
        returns (
            int256 marginValue,
            uint256 assetValue,
            uint256 debtValue
        )
    {
        uint256 price = LPTMath.decodeSqrtPriceX96(_isMarginZero, _sqrtPrice);

        if (_isMarginZero) {
            marginValue = _position.marginAmount0.add(_position.marginAmount1.mul(int256(price)).div(1e18));
        } else {
            marginValue = _position.marginAmount0.mul(int256(price)).div(1e18).add(_position.marginAmount1);
        }

        (
            uint256 assetAmount0,
            uint256 assetAmount1,
            uint256 debtAmount0,
            uint256 debtAmount1
        ) = calculateCollateralAndDebtAmount(_position, _sqrtPrice, _isMinPrice);

        if (_isMarginZero) {
            assetValue = assetAmount0.add(assetAmount1.mul(price).div(1e18));
            debtValue = debtAmount0.add(debtAmount1.mul(price).div(1e18));
        } else {
            assetValue = assetAmount0.mul(price).div(1e18).add(assetAmount1);
            debtValue = debtAmount0.mul(price).div(1e18).add(debtAmount1);
        }
    }

    function calculateCollateralAndDebtAmount(
        PositionCalculatorParams memory _position,
        uint160 _sqrtPrice,
        bool _isMinPrice
    )
        internal
        pure
        returns (
            uint256 assetAmount0,
            uint256 assetAmount1,
            uint256 debtAmount0,
            uint256 debtAmount1
        )
    {
        assetAmount0 = _position.asset0;
        assetAmount1 = _position.asset1;
        debtAmount0 = _position.debt0;
        debtAmount1 = _position.debt1;

        for (uint256 i = 0; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];

            uint160 sqrtLowerPrice = TickMath.getSqrtRatioAtTick(lpt.lowerTick);
            uint160 sqrtUpperPrice = TickMath.getSqrtRatioAtTick(lpt.upperTick);

            if (_isMinPrice && !lpt.isCollateral && sqrtLowerPrice <= _sqrtPrice && _sqrtPrice <= sqrtUpperPrice) {
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
                assetAmount0 = assetAmount0.add(amount0);
                assetAmount1 = assetAmount1.add(amount1);
            } else {
                debtAmount0 = debtAmount0.add(amount0);
                debtAmount1 = debtAmount1.add(amount1);
            }
        }
    }

    function add(PositionCalculatorParams memory _params, DataType.Position memory _position)
        internal
        pure
        returns (PositionCalculatorParams memory _newParams)
    {
        uint256 numLPTs = _params.lpts.length + _position.lpts.length;

        DataType.LPT[] memory lpts = new DataType.LPT[](numLPTs);

        _newParams = PositionCalculatorParams(
            _params.marginAmount0,
            _params.marginAmount1,
            _params.asset0,
            _params.asset1,
            _params.debt0,
            _params.debt1,
            lpts
        );

        _newParams.asset0 += _position.asset0;
        _newParams.asset1 += _position.asset1;
        _newParams.debt0 += _position.debt0;
        _newParams.debt1 += _position.debt1;

        uint256 k;

        for (uint256 j = 0; j < _params.lpts.length; j++) {
            _newParams.lpts[k] = _params.lpts[j];
            k++;
        }
        for (uint256 j = 0; j < _position.lpts.length; j++) {
            _newParams.lpts[k] = _position.lpts[j];
            k++;
        }
    }
}
