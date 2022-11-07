//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";
import "../vendors/IPyth.sol";
import "./DataType.sol";
import "./UniHelper.sol";

library PriceHelper {
    // assuming USDC
    uint256 internal constant MARGIN_SCALER = 1e6;

    // assuming ETH, BTC
    uint256 internal constant UNDERLYING_SCALER = 1e18;

    uint256 internal constant PRICE_SCALER = 1e2;

    uint256 internal constant MAX_PRICE = PRICE_SCALER * 1e36;

    address internal constant PYTH_CONTRACT_ADDRESS = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;

    /**
     * @notice Gets the square root of underlying index price.
     * If the chainlink price feed address is set, use Chainlink price, otherwise use Uniswap TWAP.
     * @param _context Predy pool's context object
     * @return price The square root of underlying index price.
     */
    function getSqrtIndexPrice(DataType.Context memory _context) internal view returns (uint160) {
        if (_context.chainlinkPriceFeed != address(0)) {
            return
                uint160(
                    encodeSqrtPriceX96(_context.isMarginZero, getChainlinkLatestAnswer(_context.chainlinkPriceFeed))
                );
        } else if (_context.pythPriceFeedId != bytes32(0)) {
            return uint160(encodeSqrtPriceX96(_context.isMarginZero, getPythLatestPrice(_context.pythPriceFeedId)));
        } else {
            return uint160(UniHelper.getSqrtTWAP(_context.uniswapPool));
        }
    }

    /**
     * @notice Gets underlying price scaled by 1e18
     * @param _priceFeedAddress Chainlink's price feed address
     * @return price underlying price scaled by 1e18
     */
    function getChainlinkLatestAnswer(address _priceFeedAddress) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeedAddress);

        (, int256 answer, , , ) = priceFeed.latestRoundData();

        require(answer > 0, "PH0");

        return (uint256(answer) * MARGIN_SCALER * PRICE_SCALER) / 1e8;
    }

    function getPythLatestPrice(bytes32 _priceFeedId) internal view returns (uint256) {
        IPyth priceFeed = IPyth(PYTH_CONTRACT_ADDRESS);

        PythStructs.Price memory price = priceFeed.getEmaPriceUnsafe(_priceFeedId);

        require(price.price > 0, "PH0");

        return (uint256(price.price) * MARGIN_SCALER * PRICE_SCALER) / 1e8;
    }

    /**
     * @notice Calculates sqrtPrice from the price.
     * @param _isMarginZero true if token0 is margin asset, false if token 1 is margin asset.
     * @param _price price scaled by (MARGIN_SCALER + PRICE_SCALER)
     * @return sqrtPriceX96 Uniswap pool's sqrt price.
     */
    function encodeSqrtPriceX96(bool _isMarginZero, uint256 _price) internal pure returns (uint256 sqrtPriceX96) {
        if (_isMarginZero) {
            _price = MAX_PRICE / _price;

            return PredyMath.sqrt(FullMath.mulDiv(_price, uint256(2**(96 * 2)), UNDERLYING_SCALER));
        } else {
            return
                PredyMath.sqrt(
                    (FullMath.mulDiv(_price, uint256(2**96) * uint256(2**96), UNDERLYING_SCALER * PRICE_SCALER))
                );
        }
    }

    /**
     * @notice Calculates position value at sqrtPrice by margin token.
     * @param _isMarginZero true if token0 is margin asset, false if token 1 is margin asset.
     * @param _sqrtPriceX96 Uniswap pool's sqrt price.
     * @param _amount0 The amount of token0
     * @param _amount1 The amount of token1
     * @return value of token0 and token1 scaled by MARGIN_SCALER
     */
    function getValue(
        bool _isMarginZero,
        uint256 _sqrtPriceX96,
        int256 _amount0,
        int256 _amount1
    ) internal pure returns (int256) {
        uint256 price;

        if (_isMarginZero) {
            price = FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, uint256(2**(96 * 2)) / UNDERLYING_SCALER);

            if (price == 0) {
                price = 1;
            }

            return _amount0 + (_amount1 * 1e18) / int256(price);
        } else {
            price = FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, uint256(2**96));

            return (_amount0 * int256(price)) / int256(2**96) + _amount1;
        }
    }

    /**
     * if isMarginZero is true, calculates token1 price by token0.
     * if isMarginZero is false, calculates token0 price by token1.
     * @dev underlying token's decimal must be 1e18.
     * @param _isMarginZero true if token0 is margin asset, false if token 1 is margin asset.
     * @param _sqrtPriceX96 Uniswap pool's sqrt price.
     * @return price The price scaled by (MARGIN_SCALER + PRICE_SCALER)
     */
    function decodeSqrtPriceX96(bool _isMarginZero, uint256 _sqrtPriceX96) internal pure returns (uint256 price) {
        if (_isMarginZero) {
            price = FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, uint256(2**(96 * 2)) / UNDERLYING_SCALER);
            if (price == 0) return MAX_PRICE;
            price = MAX_PRICE / price;
        } else {
            price =
                (FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, uint256(2**96)) * UNDERLYING_SCALER * PRICE_SCALER) /
                uint256(2**96);
        }

        if (price > MAX_PRICE) price = MAX_PRICE;
        else if (price == 0) price = 1;
    }
}
