//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";
import "./DataType.sol";
import "./UniHelper.sol";

library PriceHelper {
    function getSqrtIndexPrice(DataType.Context memory _context) internal view returns (uint160) {
        if (_context.chainlinkPriceFeed == address(0)) {
            return uint160(UniHelper.getSqrtTWAP(_context.uniswapPool));
        } else {
            return
                uint160(
                    encodeSqrtPriceX96(_context.isMarginZero, getChainlinkLatestAnswer(_context.chainlinkPriceFeed))
                );
        }
    }

    /**
     * @notice get underlying price scaled by 1e6
     */
    function getChainlinkLatestAnswer(address _priceFeedAddress) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeedAddress);

        (, int256 answer, , , ) = priceFeed.latestRoundData();

        require(answer > 0, "P0");

        return uint256(answer) / 1e2;
    }

    function encodeSqrtPriceX96(bool isMarginZero, uint256 _price) internal pure returns (uint256 sqrtPriceX96) {
        uint256 scaler = 1e18;

        if (isMarginZero) {
            _price = 1e36 / _price;

            return PredyMath.sqrt(FullMath.mulDiv(_price, uint256(2**(96 * 2)), scaler));
        } else {
            return PredyMath.sqrt((FullMath.mulDiv(_price, uint256(2**96) * uint256(2**96), scaler)));
        }
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
