//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./vendors/IUniswapV3PoolOracle.sol";
import "./libraries/LPTMath.sol";

contract LPTMathModule {

    constructor() {}

    function getLiquidityAndAmountToDeposit(
        bool isMarginZero,
        uint256 requestedAmount,
        uint160 currentSqrtPrice,
        int24 lower,
        int24 upper
    )
        external
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        return LPTMath.getLiquidityAndAmountToDeposit(isMarginZero, requestedAmount, currentSqrtPrice, lower, upper);
    }    

    function getLiquidityAndAmountToBorrow(
        bool isMarginZero,
        uint256 requestedAmount,
        int24 tick,
        int24 lower,
        int24 upper
    )
        external
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        return LPTMath.getLiquidityAndAmountToBorrow(isMarginZero, requestedAmount, tick, lower, upper);
    }

    function getAmountsForLiquidity(uint160 currentSqrtPrice, int24 _lower, int24 _upper, uint128 _liquidity)
        external
        pure
        returns (uint256, uint256)
    {
        return LPTMath.getAmountsForLiquidity(currentSqrtPrice, _lower, _upper, _liquidity);
    }

    function decodeSqrtPriceX96(bool isMarginZero, uint256 sqrtPriceX96) external pure returns (uint256 price) {
        return LPTMath.decodeSqrtPriceX96(isMarginZero, sqrtPriceX96);
    }


    function callUniswapObserve(IUniswapV3Pool uniswapPool, uint256 ago) external view returns (uint160, uint256) {
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
}
