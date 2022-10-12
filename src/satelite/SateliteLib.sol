// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "../libraries/Constants.sol";

library SateliteLib {
    function getProfit(
        uint256 indexPrice,
        uint256 strikePrice,
        int256 _amount,
        bool _isPut
    ) internal pure returns (int256) {
        uint256 instinctValue;

        if (_isPut && strikePrice > indexPrice) {
            instinctValue = strikePrice - indexPrice;
        }

        if (!_isPut && strikePrice < indexPrice) {
            instinctValue = indexPrice - strikePrice;
        }

        return (int256(instinctValue) * _amount) / 1e8;
    }

    function getBaseLiquidity(
        bool _isMarginZero,
        int24 _lower,
        int24 _upper
    ) internal pure returns (uint128) {
        if (_isMarginZero) {
            return
                LiquidityAmounts.getLiquidityForAmount1(
                    TickMath.getSqrtRatioAtTick(_lower),
                    TickMath.getSqrtRatioAtTick(_upper),
                    1e18
                );
        } else {
            return
                LiquidityAmounts.getLiquidityForAmount0(
                    TickMath.getSqrtRatioAtTick(_lower),
                    TickMath.getSqrtRatioAtTick(_upper),
                    1e18
                );
        }
    }

    function getTradePrice(
        bool _isMarginZero,
        uint256 beforeSqrtPrice,
        uint256 afterSqrtPrice
    ) internal pure returns (uint256) {
        if (_isMarginZero) {
            uint256 entryPrice = (1e18 * Constants.Q96) / afterSqrtPrice;

            return (entryPrice * Constants.Q96) / beforeSqrtPrice;
        } else {
            uint256 entryPrice = (afterSqrtPrice * 1e18) / Constants.Q96;

            return (entryPrice * beforeSqrtPrice) / Constants.Q96;
        }
    }
}
