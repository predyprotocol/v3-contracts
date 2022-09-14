// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "./DataType.sol";

library LPTStateLib {
    using SafeMath for uint256;

    /**
     * @notice register new LPT
     */
    function registerNewLPTState(
        DataType.PerpStatus storage _range,
        uint256 _tokenId,
        int24 _lowerTick,
        int24 _upperTick
    ) internal {
        _range.tokenId = _tokenId;
        _range.lowerTick = _lowerTick;
        _range.upperTick = _upperTick;
        _range.lastTouchedTimestamp = block.timestamp;
    }

    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }

    function getPerpStatus(DataType.Context memory _context, DataType.PerpStatus storage _perpState)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            getTotalLiquidityAmount(_context, _perpState),
            _perpState.borrowedLiquidity,
            getPerpUR(_context, _perpState)
        );
    }

    function getPerpUR(DataType.Context memory _context, DataType.PerpStatus storage _perpState)
        internal
        view
        returns (uint256)
    {
        return PredyMath.mulDiv(_perpState.borrowedLiquidity, 1e18, getTotalLiquidityAmount(_context, _perpState));
    }

    function getAvailableLiquidityAmount(DataType.Context memory _context, DataType.PerpStatus memory _perpState)
        internal
        view
        returns (uint256)
    {
        (, , , , , , , uint128 liquidity, , , , ) = INonfungiblePositionManager(_context.positionManager).positions(
            _perpState.tokenId
        );

        return liquidity;
    }

    function getTotalLiquidityAmount(DataType.Context memory _context, DataType.PerpStatus memory _perpState)
        internal
        view
        returns (uint256)
    {
        return getAvailableLiquidityAmount(_context, _perpState) + _perpState.borrowedLiquidity;
    }
}
