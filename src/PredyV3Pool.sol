// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract PredyV3Pool {
    struct Tick {
        int256 liquidity;
    }
    uint256[1024] ticks;
    uint256 price;

    function addLiquidity(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external {
        require(_tickId < 1024, "P0");

        ticks[_tickId] += _amount;
    }

    function removeLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount        
    ) external {
        require(_tickId < 1024, "P0");

        ticks[_tickId] -= _amount;
    }

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override returns (uint128 amount0, uint128 amount1) {
    }

    function addPerpOption(
        address recipient,
        int24 tickId,
        uint128 amount,
        bytes calldata data
    ) external {

    }

    function removePerpOption(
        int24 tickId,
        uint128 amount
    ) external {

    }

    /**
     * swap
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        // check ticks
        // swap token0 to token1 or token1 to token0
        // calculate perp option
    }

}
