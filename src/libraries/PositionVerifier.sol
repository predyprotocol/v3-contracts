// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "v3-periphery/libraries/LiquidityAmounts.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

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

    function verifyPosition(Position memory position, Proof[] memory proofs) internal view returns(bool) {
        require(position.lpts.length == proofs.length, "0");

        checkOrder(position);

        for(uint256 i = 0;i < proofs.length;i++) {
            if(proofs[i].isDebt) {
                require(!position.lpts[i].isCollateral);
                if(proofs[i].isMin) {
                    require(
                        position.lpts[i].lowerTick <= proofs[i].tick && proofs[i].tick <= position.lpts[i].upperTick, "1");
                    require(getDelta(position, proofs[i].tick) == 0, "2");
                    require(getValue(position, TickMath.getSqrtRatioAtTick(proofs[i].tick)) >= 0, "3");
                } else {
                    require(getDelta(position, position.lpts[i].lowerTick) * getDelta(position, position.lpts[i].upperTick) >= 0, "4");
                }
            } else {
                require(position.lpts[i].isCollateral);
            }
        }

        require(getLeftSideDelta(position) <= 0, "5");
        require(getRightSideDelta(position) >= 0, "6");

        return true;
    }

    function checkOrder(Position memory position) internal pure returns(int256) {
        int24 tick;

        for(uint256 i = 0;i < position.lpts.length;i++) {
            require(position.lpts[i].lowerTick < position.lpts[i].upperTick);
            require(tick <= position.lpts[i].lowerTick);
            tick = position.lpts[i].upperTick;
        }
    }

    function getAmounts(Position memory position, uint160 sqrtPrice) internal view returns(int256 totalAmount0, int256 totalAmount1) {
        for(uint256 i = 0;i < position.lpts.length;i++) {
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPrice,
                TickMath.getSqrtRatioAtTick(position.lpts[i].lowerTick),
                TickMath.getSqrtRatioAtTick(position.lpts[i].upperTick),
                position.lpts[i].liquidity
            );

            if(position.lpts[i].isCollateral) {
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

    function getValue(Position memory position, uint160 sqrtPrice) internal view returns(int256) {
        uint256 price = decodeSqrtPriceX96(sqrtPrice);

        (int256 amount0, int256 amount1) = getAmounts(position, sqrtPrice);

        return amount0 * int256(price) / 1e18 + amount1;
    }

    function getLeftSideDelta(Position memory position) internal view returns(int256) {
        if(position.lpts.length == 0) {
            return getDelta(position, 0);
        }
        
        return getDelta(position, position.lpts[0].lowerTick);
    }

    function getRightSideDelta(Position memory position) internal view returns(int256) {
        if(position.lpts.length == 0) {
            return getDelta(position, 0);
        }

        return getDelta(position, position.lpts[0].upperTick);
    }


    function getDelta(Position memory position, int24 tick) internal view returns(int256) {
        (int256 amount0, ) = getAmounts(position, TickMath.getSqrtRatioAtTick(tick));

        // console.log(amount0);

        return amount0;
    }

    function decodeSqrtPriceX96(uint256 sqrtPriceX96) private view returns (uint256 price) {
        uint256 scaler = 1; //10**ERC20(token0).decimals();

        price = (FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, uint256(2**96)) * scaler) / uint256(2**96);

        if (price > 1e36) price = 1e36;
        else if (price == 0) price = 1;
    }

}
