// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";

library UniHelper {
    function increaseLiquidity(
        DataType.Context memory _context,
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amountMax0,
        uint256 _amountMax1
    )
        internal
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams(
                _tokenId,
                _amount0,
                _amount1,
                _amountMax0,
                _amountMax1,
                block.timestamp
            );

        (liquidity, amount0, amount1) = INonfungiblePositionManager(_context.positionManager).increaseLiquidity(params);

        tokenId = _tokenId;
    }


    function mint(
        DataType.Context memory _context,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amountMax0,
        uint256 _amountMax1
    )
        internal
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            _context.token0,
            _context.token1,
            _context.feeTier,
            _lowerTick,
            _upperTick,
            _amount0,
            _amount1,
            _amountMax0,
            _amountMax1,
            address(this),
            block.timestamp
        );
        
        return INonfungiblePositionManager(_context.positionManager).mint(params);
    }

}