// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

library LPTMath {
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
