//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

interface IPricingModule {
    function calculatePerpFee(
        uint256 _price,
        uint256 _lowerPrice,
        uint256 _upperPrice,
        uint256 _volatility,
        uint256 _utilizationRatio
    ) external pure returns (uint256);

    function calculateInstantRate(uint256 _price, uint256 _utilizationRatio) external pure returns (uint256);

    function calculateMinCollateral(
        uint256 _lowerPrice,
        uint256 _upperPrice
    ) external pure returns (uint256);
}
