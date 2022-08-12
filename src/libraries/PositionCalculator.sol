// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";
import "forge-std/console2.sol";

library PositionCalculator {
    uint256 internal constant Q96 = 0x1000000000000000000000000;

    struct LPT {
        bool isCollateral;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
    }

    struct Position {
        uint256 collateral0;
        uint256 collateral1;
        uint256 debt0;
        uint256 debt1;
        LPT[] lpts;
    }

    function emptyPosition() internal pure returns (DataType.Position memory) {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        return DataType.Position(0, 0, 0, 0, lpts);
    }

    function getRequiredTokenAmounts(
        Position memory _srcPosition,
        Position memory _destPosition
    ) internal pure returns (int256, int256) {
        return (0, 0);
    }

    function calculateRequiredCollateral(
        Position memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256) {
        int256 minValue = calculateMinValue(_position, _sqrtPrice, _isMarginZero);

        (uint256 collateralValue, ) = calculateCollateralAndDebtValue(_position, _sqrtPrice, _isMarginZero);

        return int256(collateralValue) / 10000 - minValue;
    }

    function calculateMinValue(
        Position memory _position,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) internal pure returns (int256 minValue) {
        minValue = type(int256).max;
        uint160 sqrtPriceLower = 86*_sqrtPrice/100;
        uint160 sqrtPriceUpper = 112*_sqrtPrice/100;

        for(uint256 i = 0;i < _position.lpts.length;i++) {
            LPT memory lpt = _position.lpts[i];
            
            if(!lpt.isCollateral) {
                uint160 sqrtPrice = uint160(TickMath.getSqrtRatioAtTick((lpt.upperTick + lpt.lowerTick) / 2));

                if(sqrtPrice < sqrtPriceLower || sqrtPriceUpper < sqrtPrice) {
                    continue;
                }


                int256 value = calculateValue(_position, sqrtPrice, _isMarginZero);

                if(minValue > value) {
                    minValue = value;
                }
            }
        }

        {
            int256 value = calculateValue(_position, sqrtPriceUpper, _isMarginZero);
            if(minValue > value) {
                minValue = value;
            }
        }

        {
            int256 value = calculateValue(_position, sqrtPriceLower, _isMarginZero);
            if(minValue > value) {
                minValue = value;
            }
        }
    }

    function calculateValue(Position memory _position, uint160 _sqrtPrice, bool isMarginZero)
        internal
        pure
        returns (int256 value)
    {
        (uint256 collateralValue, uint256 debtValue) = calculateCollateralAndDebtValue(_position, _sqrtPrice, isMarginZero);

        return int256(collateralValue) - int256(debtValue);
    }

    function calculateCollateralAndDebtValue(Position memory _position, uint160 _sqrtPrice, bool isMarginZero)
        internal
        pure
        returns (uint256 collateralValue, uint256 debtValue)
    {

        uint256 collateralAmount0 = _position.collateral0;
        uint256 collateralAmount1 = _position.collateral1;
        uint256 debtAmount0 = _position.debt0;
        uint256 debtAmount1 = _position.debt1;

        for (uint256 i = 0; i < _position.lpts.length; i++) {
            LPT memory lpt = _position.lpts[i];

            uint160 sqrtLowerPrice = TickMath.getSqrtRatioAtTick(lpt.lowerTick);
            uint160 sqrtUpperPrice = TickMath.getSqrtRatioAtTick(lpt.upperTick);

            if(!lpt.isCollateral && sqrtLowerPrice <= _sqrtPrice && _sqrtPrice <= sqrtUpperPrice) {
                debtValue = lpt.liquidity * (TickMath.getSqrtRatioAtTick(lpt.upperTick) - TickMath.getSqrtRatioAtTick(lpt.lowerTick)) / Q96;
                continue;
            }

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                sqrtLowerPrice,
                sqrtUpperPrice,
                lpt.liquidity
            );

            if(lpt.isCollateral) {
                collateralAmount0 += (amount0);
                collateralAmount1 += (amount1);
            } else {
                debtAmount0 += (amount0);
                debtAmount1 += (amount1);
            }
        }

        uint256 price = decodeSqrtPriceX96(isMarginZero, _sqrtPrice);

        if (isMarginZero) {
            collateralValue = collateralAmount0 + (collateralAmount1 * price) / 1e18;
            debtValue = debtAmount0 + (debtAmount1 * price) / 1e18;
        } else {
            collateralValue = (collateralAmount0 * price) / 1e18 + collateralAmount1;
            debtValue = (debtAmount0 * price) / 1e18 + debtAmount1;
        }
    }

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