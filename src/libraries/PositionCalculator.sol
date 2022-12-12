// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";
import "./PriceHelper.sol";

/**
 * @title PositionCalculator library
 * @notice Implements the base logic calculating Min. Deposit and value of positions.
 */
library PositionCalculator {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    uint256 internal constant Q96 = 0x1000000000000000000000000;
    // sqrt{1.18} = 1.08627804912
    uint160 internal constant UPPER_E8 = 108627805;
    // sqrt{1/1.18} = 0.92057461789
    uint160 internal constant LOWER_E8 = 92057462;

    uint256 internal constant MAX_NUM_OF_LPTS = 16;

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
     * MinDeposit = vaultPositionValue - minValue + Max{0.00006 * Sqrt{DebtValue}, 0.02} * DebtValue
     * @param _params position object
     * @param _sqrtPrice square root price to calculate
     * @param _isMarginZero whether the stable token is token0 or token1
     */
    function calculateMinDeposit(
        PositionCalculatorParams memory _params,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256 minDeposit) {
        require(
            Constants.MIN_SQRT_PRICE <= _sqrtPrice && _sqrtPrice <= Constants.MAX_SQRT_PRICE,
            "Out of sqrtprice range"
        );

        require(_params.lpts.length <= MAX_NUM_OF_LPTS, "Exceeds max num of LPTs");

        int256 vaultPositionValue = calculateValue(_params, _sqrtPrice, _isMarginZero);

        int256 minValue = calculateMinValue(_params, _sqrtPrice, _isMarginZero);

        (, , uint256 debtValue) = calculateCollateralAndDebtValue(_params, _sqrtPrice, _isMarginZero, false);

        minDeposit = int256(calculateRequiredCollateralWithDebt(debtValue).mul(debtValue).div(1e6))
            .add(vaultPositionValue)
            .sub(minValue);

        if (minDeposit < Constants.MIN_MARGIN_AMOUNT && debtValue > 0) {
            minDeposit = Constants.MIN_MARGIN_AMOUNT;
        }
    }

    function calculateRequiredCollateralWithDebt(uint256 _debtValue) internal pure returns (uint256) {
        return
            PredyMath.max(
                Constants.MIN_COLLATERAL_WITH_DEBT_SLOPE.mul(PredyMath.sqrt(_debtValue * 1e6)).div(1e6),
                Constants.BASE_MIN_COLLATERAL_WITH_DEBT
            );
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
     * 1. value of at P*1.18
     * 2. value of at P/1.18
     * 3. values of at P_{min} of LPTs
     */
    function calculateMinValue(
        PositionCalculatorParams memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256 minValue) {
        minValue = type(int256).max;
        uint256 sqrtPriceLower = uint256(LOWER_E8).mul(_sqrtPrice) / 1e8;
        uint256 sqrtPriceUpper = uint256(UPPER_E8).mul(_sqrtPrice) / 1e8;

        require(sqrtPriceLower < type(uint160).max);
        require(sqrtPriceUpper < type(uint160).max);

        require(TickMath.MIN_SQRT_RATIO < _sqrtPrice && _sqrtPrice < TickMath.MAX_SQRT_RATIO, "Out of sqrtprice range");

        if (sqrtPriceLower < TickMath.MIN_SQRT_RATIO) {
            sqrtPriceLower = TickMath.MIN_SQRT_RATIO;
        }

        if (sqrtPriceUpper > TickMath.MAX_SQRT_RATIO) {
            sqrtPriceUpper = TickMath.MAX_SQRT_RATIO;
        }

        {
            // 1. check value of at P*1.18
            int256 value = calculateValue(_position, uint160(sqrtPriceUpper), _isMarginZero);
            if (minValue > value) {
                minValue = value;
            }
        }

        {
            // 2. check value of at P/1.18
            int256 value = calculateValue(_position, uint160(sqrtPriceLower), _isMarginZero);
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
        marginValue = PriceHelper.getValue(_isMarginZero, _sqrtPrice, _position.marginAmount0, _position.marginAmount1);

        (
            uint256 assetAmount0,
            uint256 assetAmount1,
            uint256 debtAmount0,
            uint256 debtAmount1
        ) = calculateCollateralAndDebtAmount(_position, _sqrtPrice, _isMinPrice);

        assetValue = uint256(
            PriceHelper.getValue(_isMarginZero, _sqrtPrice, int256(assetAmount0), int256(assetAmount1))
        );

        debtValue = uint256(PriceHelper.getValue(_isMarginZero, _sqrtPrice, int256(debtAmount0), int256(debtAmount1)));
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
                            uint256(TickMath.getSqrtRatioAtTick(lpt.upperTick)).sub(
                                TickMath.getSqrtRatioAtTick(lpt.lowerTick)
                            )
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

        _newParams.asset0 = _newParams.asset0.add(_position.asset0);
        _newParams.asset1 = _newParams.asset1.add(_position.asset1);
        _newParams.debt0 = _newParams.debt0.add(_position.debt0);
        _newParams.debt1 = _newParams.debt1.add(_position.debt1);

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
