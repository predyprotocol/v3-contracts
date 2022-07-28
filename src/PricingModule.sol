//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

import "./libraries/Sqrt.sol";
import "forge-std/console2.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";

contract PricingModule {
    uint256 constant ONE = 1e12;
    uint256 constant PI_E8 = 3.1415926535 * 1e12;

    constructor() {}

    /**
     * Calculates daily premium for range per liquidity
     */
    function calculatePerpFee(
        bool _isMarginZero,
        uint256 _price,
        uint160 _lowerSqrtPrice,
        uint160 _upperSqrtPrice,
        uint256 _volatility
    ) public view returns (uint256) {
        require(_volatility > 0, "PM0");

        uint256 value;

        if (_isMarginZero) {
            value = calculatePerpValue(
                _price,
                (1e12 * _lowerSqrtPrice) / (2**96),
                (1e12 * _upperSqrtPrice) / (2**96),
                _volatility
            );
        } else {
            value = calculatePerpValue(
                _price,
                ((2**96) * 1e12) / _upperSqrtPrice,
                ((2**96) * 1e12) / _lowerSqrtPrice,
                _volatility
            );
        }

        return convertSizeToLiq(_isMarginZero, _lowerSqrtPrice, _upperSqrtPrice, 1e18, value);
    }

    function calculatePerpValue(
        uint256 _price,
        uint160 _lowerSqrtPrice,
        uint160 _upperSqrtPrice,
        uint256 _volatility
    ) public view returns (uint256) {
        uint256 r = (_upperSqrtPrice * ONE) / _lowerSqrtPrice;
        uint256 k = _upperSqrtPrice * _lowerSqrtPrice;

        uint256 r2 = calculateR2(calculateT(r, _volatility) + ONE, _volatility);

        uint256 v1 = calculateValue(_price, k, r);
        uint256 v2 = calculateValue(_price, k, r2);

        return v1 > v2 ? v1 - v2 : 0;
    }

    function calculateT(uint256 _r, uint256 _volatility) internal pure returns (uint256) {
        uint256 sqrtR = Sqrt.sqrt(_r * ONE);
        uint256 a = ((sqrtR - ONE) * ONE) / (sqrtR + ONE);
        return (2 * 365 * PI_E8 * a * a) / (_volatility * _volatility);
    }

    function calculateR2(uint256 _t, uint256 _volatility) internal pure returns (uint256) {
        uint256 a = (_volatility * Sqrt.sqrt((_t * ONE * ONE) / (365 * 2 * PI_E8))) / ONE;

        uint256 b = (ONE * (ONE + a)) / (ONE - a);

        return (b * b) / ONE;
    }

    function calculateValue(
        uint256 _price,
        uint256 _k,
        uint256 _r
    ) internal view returns (uint256) {
        return ((2 * Sqrt.sqrt((_price * _k * _r) / ONE) - _price - _k) * ONE) / (_r - ONE);
    }

    /**
     * Calculates daily interest rate for range per liquidity
     */
    function calculateInstantRate(uint256 _price, uint256 _utilizationRatio) external pure returns (uint256) {
        // TODO
        return 500;
    }

    /**
     * Calculates min. collateral per liquidity
     *
     */
    function calculateMinCollateral(
        bool _isMarginZero,
        uint160 _lowerSqrtPrice,
        uint160 _upperSqrtPrice
    ) external view returns (uint256 minCollateral) {
        // TODO
        uint256 atmPrice;

        if (_isMarginZero) {
            uint256 l = ((2**96) * _lowerSqrtPrice) / 1e12;
            uint256 u = ((2**96) * _upperSqrtPrice) / 1e12;
            atmPrice = l * u;
        } else {
            uint256 l = ((2**96) * 1e12) / _upperSqrtPrice;
            uint256 u = ((2**96) * 1e12) / _lowerSqrtPrice;
            atmPrice = l * u;
        }

        minCollateral = calculatePerpFee(_isMarginZero, atmPrice, _lowerSqrtPrice, _upperSqrtPrice, 2 * 1e12);
    }

    function convertSizeToLiq(
        bool _isMarginZero,
        uint160 lowerSqrtPrice,
        uint160 upperSqrtPrice,
        uint256 _amount,
        uint256 _value
    ) public view returns (uint256) {
        uint160 liquidity;
        if (_isMarginZero) {
            // amount / (sqrt(upper) - sqrt(lower))
            liquidity = LiquidityAmounts.getLiquidityForAmount1(lowerSqrtPrice, upperSqrtPrice, _amount);
        } else {
            // amount * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
            liquidity = LiquidityAmounts.getLiquidityForAmount0(lowerSqrtPrice, upperSqrtPrice, _amount);
        }

        return (_value * _amount) / liquidity;
    }
}
