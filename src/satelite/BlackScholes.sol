// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./AdvancedMath.sol";

/**
 * @notice Option price calculator using Black-Scholes formula
 * B0: spot price must be between 0 and 10^13
 * B1: strike price must be between 0 and 10^13
 * B2: implied volatility must be between 0 and 1000%
 */
library BlackScholes {
    /// @dev sqrt(365 * 86400)
    int256 internal constant SQRT_YEAR_E8 = 5615.69229926 * 10**8;

    /**
     * @notice calculate option price at a IV point
     * @param _spot spot price scaled 1e8
     * @param _strike strike price scaled 1e8
     * @param _maturity maturity in seconds
     * @param _iv IV
     * @param _isPut option type
     * @return premium per amount
     */
    function calculatePrice(
        uint256 _spot,
        uint256 _strike,
        uint256 _maturity,
        uint256 _iv,
        bool _isPut
    ) internal pure returns (uint256 premium) {
        require(_spot > 0 && _spot < 1e13, "B0");
        require(_strike > 0 && _strike < 1e13, "B1");
        require(0 < _iv && _iv < 1000 * 1e6, "B2");

        int256 sqrtMaturity = getSqrtMaturity(_maturity);

        return uint256(calOptionPrice(int256(_spot), int256(_strike), sqrtMaturity, int256(_iv), _isPut));
    }

    function getSqrtMaturity(uint256 _maturity) public pure returns (int256) {
        require(
            _maturity > 0 && _maturity < 31536000,
            "PriceCalculator: maturity must not have expired and less than 1 year"
        );

        return (AdvancedMath.sqrt(int256(_maturity)) * 1e16) / SQRT_YEAR_E8;
    }

    function calOptionPrice(
        int256 _spot,
        int256 _strike,
        int256 _sqrtMaturity,
        int256 _volatility,
        bool _isPut
    ) internal pure returns (int256 price) {
        if (_volatility > 0) {
            int256 spotPerStrikeE4 = int256((_spot * 1e4) / _strike);
            int256 logSigE4 = AdvancedMath.logTaylor(spotPerStrikeE4);

            (int256 d1E4, int256 d2E4) = _calD1D2(logSigE4, _sqrtMaturity, _volatility);
            int256 nd1E8 = AdvancedMath.calStandardNormalCDF(d1E4);
            int256 nd2E8 = AdvancedMath.calStandardNormalCDF(d2E4);
            price = (_spot * nd1E8 - _strike * nd2E8) / 1e8;
        }

        int256 lowestPrice;
        if (_isPut) {
            price = price - _spot + _strike;

            lowestPrice = (_strike > _spot) ? _strike - _spot : int256(0);
        } else {
            lowestPrice = (_spot > _strike) ? _spot - _strike : int256(0);
        }

        if (price < lowestPrice) {
            return lowestPrice;
        }

        return price;
    }

    function _calD1D2(
        int256 _logSigE4,
        int256 _sqrtMaturity,
        int256 _volatilityE8
    ) internal pure returns (int256 d1E4, int256 d2E4) {
        int256 sigE8 = (_volatilityE8 * _sqrtMaturity) / (1e8);
        d1E4 = ((_logSigE4 * 10**8) / sigE8) + (sigE8 / (2 * 10**4));
        d2E4 = d1E4 - (sigE8 / 10**4);
    }
}
