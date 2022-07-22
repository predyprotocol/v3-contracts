//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

contract PricingModule {
    constructor() {}

    /**
     * daily premium for range per liquidity
     */
    function calculatePerpFee(
        uint256 _price,
        uint256 _lowerPrice,
        uint256 _upperPrice,
        uint256 _volatility,
        uint256 _utilizationRatio
    ) external pure returns (uint256) {
        // TODO
        return 5000;
    }

    /**
     * daily interest rate for range per liquidity
     */
    function calculateInstantRate(uint256 _price, uint256 _utilizationRatio) external pure returns (uint256) {
        // TODO
        return 500;
    }


    function calculateMinCollateral(
        uint256 _lowerPrice,
        uint256 _upperPrice
    ) external pure returns (uint256) {
        // TODO
        return 1000000;
    }
}
