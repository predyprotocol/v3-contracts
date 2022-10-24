// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "../libraries/Constants.sol";
import "../libraries/PredyMath.sol";

library FutureMarketLib {
    struct FutureVault {
        uint256 id;
        address owner;
        int256 positionAmount;
        uint256 entryPrice;
        int256 entryFundingFee;
        uint256 marginAmount;
    }

    function updateEntryPrice(
        int256 _entryPrice,
        int256 _position,
        int256 _tradePrice,
        int256 _positionTrade
    ) internal pure returns (int256 newEntryPrice, int256 profitValue) {
        int256 newPosition = _position + _positionTrade;
        if (_position == 0 || (_position > 0 && _positionTrade > 0) || (_position < 0 && _positionTrade < 0)) {
            newEntryPrice =
                (_entryPrice * int256(PredyMath.abs(_position)) + _tradePrice * int256(PredyMath.abs(_positionTrade))) /
                (int256(PredyMath.abs(_position + _positionTrade)));
        } else if (
            (_position > 0 && _positionTrade < 0 && newPosition > 0) ||
            (_position < 0 && _positionTrade > 0 && newPosition < 0)
        ) {
            newEntryPrice = _entryPrice;
            profitValue = ((-_positionTrade) * (_tradePrice - _entryPrice)) / 1e18;
        } else {
            if (newPosition != 0) {
                newEntryPrice = _tradePrice;
            }

            profitValue = (_position * (_tradePrice - _entryPrice)) / 1e18;
        }
    }

    /**
     * @notice Calculates MinCollateral of vault positions.
     * MinCollateral := Min{Max{0.014 * Sqrt{PositionAmount}, 0.1}, 0.2} * TWAP * PositionAmount
     */
    function calculateMinCollateral(FutureVault memory _futureVault, uint256 _twap) internal pure returns (uint256) {
        uint256 positionAmount = PredyMath.abs(_futureVault.positionAmount);

        uint256 minCollateralRatio = PredyMath.min(
            PredyMath.max((14 * 1e15 * PredyMath.sqrt(positionAmount * 1e18)) / 1e18, 10 * 1e16),
            20 * 1e16
        );

        uint256 minCollateral = (_twap * positionAmount) / 1e18;

        return (minCollateral * minCollateralRatio) / 1e18;
    }
}
