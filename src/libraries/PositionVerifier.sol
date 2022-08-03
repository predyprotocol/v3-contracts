// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

library PositionVerifier {
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

    struct Proof {
        bool isDebt;
        bool isMin;
        int24 tick;
    }

    function verifyPosition(
        Position memory position,
        Proof[] memory proofs,
        bool isMarginZero,
        int256 _threshold
    ) internal pure returns (bool) {
        if (position.lpts.length == 0) {
            return false;
        }
        require(position.lpts.length == proofs.length, "0");

        checkOrder(position);

        for (uint256 i = 0; i < proofs.length; i++) {
            if (proofs[i].isDebt) {
                require(!position.lpts[i].isCollateral);
                if (proofs[i].isMin) {
                    require(
                        position.lpts[i].lowerTick <= proofs[i].tick && proofs[i].tick <= position.lpts[i].upperTick,
                        "1"
                    );
                    int256 delta = getDelta(position, proofs[i].tick, isMarginZero);
                    require(-_threshold <= delta && delta <= _threshold, "2");
                    require(getValue(position, TickMath.getSqrtRatioAtTick(proofs[i].tick), isMarginZero) >= 0, "3");
                } else {
                    require(
                        getDelta(position, position.lpts[i].lowerTick, isMarginZero) *
                            getDelta(position, position.lpts[i].upperTick, isMarginZero) >=
                            0,
                        "4"
                    );
                }
            } else {
                require(position.lpts[i].isCollateral);
            }
        }

        if (isMarginZero) {
            require(getLeftSideDelta(position, isMarginZero) >= -_threshold, "5");
            require(getRightSideDelta(position, isMarginZero) <= _threshold, "6");
        } else {
            require(getLeftSideDelta(position, isMarginZero) <= _threshold, "5");
            require(getRightSideDelta(position, isMarginZero) >= -_threshold, "6");
        }

        return true;
    }

    function checkOrder(Position memory position) internal pure returns (int256) {
        int24 tick;

        for (uint256 i = 0; i < position.lpts.length; i++) {
            require(position.lpts[i].lowerTick < position.lpts[i].upperTick);
            require(tick <= position.lpts[i].lowerTick);
            tick = position.lpts[i].upperTick;
        }
    }

    function getAmounts(Position memory position, uint160 sqrtPrice)
        internal
        pure
        returns (int256 totalAmount0, int256 totalAmount1)
    {
        for (uint256 i = 0; i < position.lpts.length; i++) {
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPrice,
                TickMath.getSqrtRatioAtTick(position.lpts[i].lowerTick),
                TickMath.getSqrtRatioAtTick(position.lpts[i].upperTick),
                position.lpts[i].liquidity
            );

            if (position.lpts[i].isCollateral) {
                totalAmount0 += int256(amount0);
                totalAmount1 += int256(amount1);
            } else {
                totalAmount0 -= int256(amount0);
                totalAmount1 -= int256(amount1);
            }
        }

        totalAmount0 += int256(position.collateral0);
        totalAmount1 += int256(position.collateral1);
        totalAmount0 -= int256(position.debt0);
        totalAmount1 -= int256(position.debt1);
    }

    function getValue(
        Position memory position,
        uint160 sqrtPrice,
        bool isMarginZero
    ) internal pure returns (int256) {
        uint256 price = decodeSqrtPriceX96(sqrtPrice);

        (int256 amount0, int256 amount1) = getAmounts(position, sqrtPrice);

        if (isMarginZero) {
            return amount0 + (amount1 * int256(price)) / 1e18;
        } else {
            return (amount0 * int256(price)) / 1e18 + amount1;
        }
    }

    function getLeftSideDelta(Position memory position, bool isMarginZero) internal pure returns (int256) {
        if (position.lpts.length == 0) {
            return getDelta(position, 0, isMarginZero);
        }

        return getDelta(position, position.lpts[0].lowerTick, isMarginZero);
    }

    function getRightSideDelta(Position memory position, bool isMarginZero) internal pure returns (int256) {
        if (position.lpts.length == 0) {
            return getDelta(position, 0, isMarginZero);
        }

        return getDelta(position, position.lpts[0].upperTick, isMarginZero);
    }

    function getDelta(
        Position memory position,
        int24 tick,
        bool isMarginZero
    ) internal pure returns (int256) {
        (int256 amount0, int256 amount1) = getAmounts(position, TickMath.getSqrtRatioAtTick(tick));

        if (isMarginZero) {
            return amount1;
        } else {
            return amount0;
        }
    }

    function decodeSqrtPriceX96(uint256 sqrtPriceX96) private pure returns (uint256 price) {
        uint256 scaler = 1; //10**ERC20(token0).decimals();

        price = (FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**96)) * scaler) / uint256(2**96);

        if (price > 1e36) price = 1e36;
        else if (price == 0) price = 1;
    }

    // generate proof

    function generateProof(Position memory position, bool isMarginZero) internal pure returns (Proof[] memory proofs) {
        proofs = new Proof[](position.lpts.length);

        for (uint256 i = 0; i < position.lpts.length; i++) {
            if (position.lpts[i].isCollateral) {
                proofs[i] = Proof(false, false, 0);
            } else {
                (int256 amount0, int256 amount1) = getAmounts(
                    omitLPT(position, i),
                    uint160(TickMath.getSqrtRatioAtTick(position.lpts[i].lowerTick))
                );

                int24 tick = TickMath.getTickAtSqrtRatio(
                    isMarginZero
                        ? getSqrtPriceForAmount1(
                            uint256(amount1),
                            TickMath.getSqrtRatioAtTick(position.lpts[i].lowerTick),
                            position.lpts[i].liquidity
                        )
                        : getSqrtPriceForAmount0(
                            uint256(amount0),
                            TickMath.getSqrtRatioAtTick(position.lpts[i].upperTick),
                            position.lpts[i].liquidity
                        )
                );

                {
                    int24 a = tick / 10;
                    int24 b = tick % 10;
                    tick = a * 10;
                    if (b >= 5) {
                        tick += 10;
                    }
                }

                bool isMin = position.lpts[i].lowerTick <= tick && tick <= position.lpts[i].upperTick;
                proofs[i] = Proof(true, isMin, tick);
            }
        }

        return proofs;
    }

    function omitLPT(Position memory position, uint256 target) internal pure returns (Position memory) {
        LPT[] memory lpts = new LPT[](position.lpts.length - 1);
        uint256 j = 0;

        for (uint256 i = 0; i < position.lpts.length; i++) {
            if (i == target) continue;
            lpts[j] = position.lpts[i];
            j++;
        }

        return Position(position.collateral0, position.collateral1, position.debt0, position.debt1, lpts);
    }

    function getSqrtPriceForAmount0(
        uint256 amount0,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint160) {
        return
            uint160(
                FullMath.mulDiv(
                    uint256(liquidity) << FixedPoint96.RESOLUTION,
                    sqrtRatioBX96,
                    (amount0 * sqrtRatioBX96 + uint256(liquidity)) << FixedPoint96.RESOLUTION
                )
            );
    }

    function getSqrtPriceForAmount1(
        uint256 amount1,
        uint160 sqrtRatioAX96,
        uint128 liquidity
    ) internal pure returns (uint160) {
        return uint160(FullMath.mulDiv(amount1, FixedPoint96.Q96, liquidity) + sqrtRatioAX96);
    }
}
