// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../vendors/IUniswapV3PoolOracle.sol";

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

    function getAmountsForLiquidityRoundUp(
        uint160 currentSqrtPrice,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity
    ) internal pure returns (uint256, uint256) {
        return
            getAmountsForLiquidityRoundUp(
                currentSqrtPrice,
                TickMath.getSqrtRatioAtTick(_lower),
                TickMath.getSqrtRatioAtTick(_upper),
                _liquidity
            );
    }

    function getAmount0ForLiquidityRoundUp(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);

        uint256 inter = FullMath.mulDiv(intermediate, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96);

        return FullMath.mulDivRoundingUp(liquidity, FixedPoint96.Q96, inter);
    }

    function getAmount1ForLiquidityRoundUp(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    function getAmountsForLiquidityRoundUp(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidityRoundUp(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidityRoundUp(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidityRoundUp(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidityRoundUp(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }

    function getSqrtRatioAtTick(int24 _tick) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    function callUniswapObserve(IUniswapV3Pool uniswapPool, uint256 ago) internal view returns (uint160, uint256) {
        uint32[] memory secondsAgos = new uint32[](2);

        secondsAgos[0] = uint32(ago);
        secondsAgos[1] = 0;

        (bool success, bytes memory data) = address(uniswapPool).staticcall(
            abi.encodeWithSelector(IUniswapV3PoolOracle.observe.selector, secondsAgos)
        );

        if (!success) {
            if (keccak256(data) != keccak256(abi.encodeWithSignature("Error(string)", "OLD"))) revertBytes(data);

            (, , uint16 index, uint16 cardinality, , , ) = uniswapPool.slot0();

            (uint32 oldestAvailableAge, , , bool initialized) = uniswapPool.observations((index + 1) % cardinality);

            if (!initialized) (oldestAvailableAge, , , ) = uniswapPool.observations(0);

            ago = block.timestamp - oldestAvailableAge;
            secondsAgos[0] = uint32(ago);

            (success, data) = address(uniswapPool).staticcall(
                abi.encodeWithSelector(IUniswapV3PoolOracle.observe.selector, secondsAgos)
            );
            if (!success) revertBytes(data);
        }

        int56[] memory tickCumulatives = abi.decode(data, (int56[]));

        int24 tick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int256(ago)));

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        return (sqrtPriceX96, ago);
    }

    function revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }

        revert("e/empty-error");
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
