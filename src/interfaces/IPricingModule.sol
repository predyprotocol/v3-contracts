//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IPricingModule {
    function takeSnapshotForRange(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) external;

    function calculateDailyPremium(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) external pure returns (uint256);

    function calculateMinCollateral(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) external pure returns (uint256);

    function calculateInterestRate(uint256 _utilizationRatio) external view returns (uint256);
}
