// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

library LPTMath {
    function getLiquidityAndAmountToDeposit(
        bool isMarginZero,
        uint256 requestedAmount,
        uint160 currentSqrtPrice,
        int24 lower,
        int24 upper
    )
        internal
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (isMarginZero) {
            return
                getLiquidityAndAmount(
                    0,
                    requestedAmount,
                    TickMath.getSqrtRatioAtTick(upper),
                    currentSqrtPrice,
                    lower,
                    upper
                );
        } else {
            return
                getLiquidityAndAmount(
                    requestedAmount,
                    0,
                    TickMath.getSqrtRatioAtTick(lower),
                    currentSqrtPrice,
                    lower,
                    upper
                );
        }
    }

    function getLiquidityAndAmountToBorrow(
        bool isMarginZero,
        uint256 requestedAmount,
        int24 tick,
        int24 lower,
        int24 upper
    )
        internal
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (isMarginZero) {
            return
                getLiquidityAndAmount(
                    0,
                    requestedAmount,
                    TickMath.getSqrtRatioAtTick(upper),
                    TickMath.getSqrtRatioAtTick(tick),
                    lower,
                    upper
                );
        } else {
            return
                getLiquidityAndAmount(
                    requestedAmount,
                    0,
                    TickMath.getSqrtRatioAtTick(lower),
                    TickMath.getSqrtRatioAtTick(tick),
                    lower,
                    upper
                );
        }
    }

    function getLiquidityAndAmount(
        uint256 requestedAmount0,
        uint256 requestedAmount1,
        uint160 sqrtPrice1,
        uint160 sqrtPrice2,
        int24 lower,
        int24 upper
    )
        internal
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (liquidity) = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice1,
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            requestedAmount0,
            requestedAmount1
        );

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPrice2,
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            liquidity
        );
    }

    function getLiquidityForAmounts(
        uint160 currentSqrtPrice,
        int24 _lower,
        int24 _upper,
        uint256 _amount0,
        uint256 _amount1
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmounts(
                currentSqrtPrice,
                TickMath.getSqrtRatioAtTick(_lower),
                TickMath.getSqrtRatioAtTick(_upper),
                _amount0,
                _amount1
            );
    }

    function getAmountsForLiquidity(
        uint160 currentSqrtPrice,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                currentSqrtPrice,
                TickMath.getSqrtRatioAtTick(_lower),
                TickMath.getSqrtRatioAtTick(_upper),
                _liquidity
            );
    }

    function getSqrtRatioAtTick(int24 _tick) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    /**
     * if isMarginZero is true, calculates token1 price by token0.
     * if isMarginZero is false, calculates token0 price by token1.
     * @dev underlying token's decimal must be 1e18.
     */
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
