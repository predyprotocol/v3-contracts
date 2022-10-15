// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/libraries/PositionKey.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./DataType.sol";

library LPTStateLib {
    using SafeMath for uint256;

    /**
     * @notice register new LPT
     */
    function registerNewLPTState(
        DataType.PerpStatus storage _range,
        int24 _lowerTick,
        int24 _upperTick
    ) internal {
        _range.lowerTick = _lowerTick;
        _range.upperTick = _upperTick;
        _range.lastTouchedTimestamp = block.timestamp;
    }

    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }

    function getPerpStatus(address _controllerAddress, address _uniswapPool, DataType.PerpStatus memory _perpState)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            getTotalLiquidityAmount(_controllerAddress, _uniswapPool, _perpState),
            _perpState.borrowedLiquidity,
            getPerpUR(_controllerAddress, _uniswapPool, _perpState)
        );
    }

    function getPerpUR(address _controllerAddress, address _uniswapPool, DataType.PerpStatus memory _perpState) internal view returns (uint256) {
        return PredyMath.mulDiv(_perpState.borrowedLiquidity, 1e18, getTotalLiquidityAmount(_controllerAddress, _uniswapPool, _perpState));
    }

    function getAvailableLiquidityAmount(address _controllerAddress, address _uniswapPool, DataType.PerpStatus memory _perpState)
        internal
        view
        returns (uint256)
    {
        bytes32 positionKey = PositionKey.compute(_controllerAddress, _perpState.lowerTick, _perpState.upperTick);

        (uint128 liquidity, , , , ) = IUniswapV3Pool(_uniswapPool).positions(positionKey);

        return liquidity;
    }

    function getTotalLiquidityAmount(address _controllerAddress, address _uniswapPool, DataType.PerpStatus memory _perpState)
        internal
        view
        returns (uint256)
    {
        return getAvailableLiquidityAmount(_controllerAddress, _uniswapPool, _perpState) + _perpState.borrowedLiquidity;
    }
}
