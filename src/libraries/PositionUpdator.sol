// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import "./DataType.sol";
import "./BaseToken.sol";
import "./VaultLib.sol";
import "./LPTStateLib.sol";
import "./UniHelper.sol";

library PositionUpdator {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using BaseToken for BaseToken.TokenState;
    using VaultLib for DataType.Vault;
    using LPTStateLib for DataType.PerpStatus;

    uint24 internal constant FEE_TIER = 500;

    /**
     * @notice update position and return required token amounts.
     */
    function updatePosition(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates,
        bool _reduceOnly
    ) external returns (int256 requiredAmount0, int256 requiredAmount1) {
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            DataType.PositionUpdate memory positionUpdate = _positionUpdates[i];

            if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_TOKEN) {
                require(!_reduceOnly, "PU1");
                depositTokens(_vault, _context, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.add(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.add(int256(positionUpdate.param1));
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_TOKEN) {
                withdrawTokens(_vault, _context, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param1));
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_TOKEN) {
                require(!_reduceOnly, "PU1");
                borrowTokens(_vault, _context, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param1));
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_TOKEN) {
                repayTokens(_vault, _context, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param1));
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_LPT) {
                require(!_reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = depositLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_LPT) {
                (uint256 amount0, uint256 amount1) = withdrawLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));

            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_LPT) {
                require(!_reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = borrowLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));

            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_LPT) {

                (uint256 amount0, uint256 amount1) = repayLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));

            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_IN) {
                (int256 amount0, int256 amount1) = swapExactIn(_context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(amount0);
                requiredAmount1 = requiredAmount1.add(amount1);
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_OUT) {
                (int256 amount0, int256 amount1) = swapExactOut(_context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(amount0);
                requiredAmount1 = requiredAmount1.add(amount1);
            }
        }
    }
    
    function depositTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal {
        _context.tokenState0.addCollateral(_vault.balance0, amount0, true);
        _context.tokenState1.addCollateral(_vault.balance1, amount1, true);
    }

    function withdrawTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal {
        _context.tokenState0.removeCollateral(_vault.balance0, amount0, true);
        _context.tokenState1.removeCollateral(_vault.balance1, amount1, true);
    }

    function borrowTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal {
        _context.tokenState0.addDebt(_vault.balance0, amount0);
        _context.tokenState1.addDebt(_vault.balance1, amount1);
    }

    function repayTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal {
        _context.tokenState0.removeDebt(_vault.balance0, amount0);
        _context.tokenState1.removeDebt(_vault.balance1, amount1);
    }

    function depositLPT(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidity(
            getSqrtPrice(IUniswapV3Pool(_context.uniswapPool)),
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            _positionUpdate.liquidity
        );

        uint128 liquidity;
        if(_ranges[rangeId].tokenId > 0) {
            (, liquidity, requiredAmount0, requiredAmount1) =  UniHelper.increaseLiquidity(
                _context,
                _ranges[rangeId].tokenId,
                amount0,
                amount1,
                _positionUpdate.param0,
                _positionUpdate.param1
            );
        } else {
            uint256 tokenId = 0;

            (tokenId, liquidity, requiredAmount0, requiredAmount1) =  UniHelper.mint(
                _context,
                _positionUpdate.lowerTick,
                _positionUpdate.upperTick,
                amount0,
                amount1,
                _positionUpdate.param0,
                _positionUpdate.param1
            );

            _ranges[rangeId].registerNewLPTState(tokenId, _positionUpdate.lowerTick, _positionUpdate.upperTick);
        }


        _vault.depositLPT(_ranges, rangeId, _positionUpdate.liquidity);
    }

    function withdrawLPT(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 withdrawAmount0, uint256 withdrawAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (withdrawAmount0, withdrawAmount1) = decreaseLiquidityFromUni(
            _context,
            _ranges[rangeId],
            _positionUpdate.liquidity,
            _positionUpdate.param0,
            _positionUpdate.param1
        );

        {
            (uint256 fee0, uint256 fee1) = _vault.getEarnedTradeFee(rangeId, _ranges[rangeId]);
            withdrawAmount0 = fee0;
            withdrawAmount1 = fee1;
        }

        if(_context.isMarginZero) {
            withdrawAmount0 = withdrawAmount0.add(_vault.getEarnedDailyPremium(rangeId, _ranges[rangeId]));
        }else {
            withdrawAmount1 = withdrawAmount1.add(_vault.getEarnedDailyPremium(rangeId, _ranges[rangeId]));
        }

        _vault.withdrawLPT(rangeId, _positionUpdate.liquidity);
    }

    function borrowLPT(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (requiredAmount0, requiredAmount1) = decreaseLiquidityFromUni(
            _context,
            _ranges[rangeId],
            _positionUpdate.liquidity,
            _positionUpdate.param0,
            _positionUpdate.param1
        );

        _ranges[rangeId].borrowedLiquidity += _positionUpdate.liquidity;

        _vault.borrowLPT(_ranges, rangeId, _positionUpdate.liquidity);
    }

    function repayLPT(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidity(
            getSqrtPrice(IUniswapV3Pool(_context.uniswapPool)),
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            _positionUpdate.liquidity
        );

        uint128 liquidity;

        (, liquidity, requiredAmount0, requiredAmount1) =  UniHelper.increaseLiquidity(
            _context,
            _ranges[rangeId].tokenId,
            amount0,
            amount1,
            _positionUpdate.param0,
            _positionUpdate.param1
        );

        _ranges[rangeId].borrowedLiquidity -= _positionUpdate.liquidity;

        if(_context.isMarginZero) {
            requiredAmount0 = requiredAmount0.add(_vault.getPaidDailyPremium(rangeId, _ranges[rangeId]));
        }else {
            requiredAmount1 = requiredAmount1.add(_vault.getPaidDailyPremium(rangeId, _ranges[rangeId]));
        }

        _vault.repayLPT(rangeId, _positionUpdate.liquidity);
    }

    function swapExactIn(
        DataType.Context memory _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _positionUpdate.zeroForOne ? _context.token0 : _context.token1,
            tokenOut: _positionUpdate.zeroForOne ? _context.token1 : _context.token0,
            fee: _context.feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _positionUpdate.param0,
            amountOutMinimum: _positionUpdate.param1,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(_context.swapRouter).exactInputSingle(params);

        if(_positionUpdate.zeroForOne) {
            return (int256(_positionUpdate.param0), -int256(amountOut));
        } else {
            return (-int256(amountOut), int256(_positionUpdate.param0));
        }
    }

    function swapExactOut(
        DataType.Context memory _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _positionUpdate.zeroForOne ? _context.token0 : _context.token1,
            tokenOut: _positionUpdate.zeroForOne ? _context.token1 : _context.token0,
            fee: _context.feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _positionUpdate.param0,
            amountInMaximum: _positionUpdate.param1,
            sqrtPriceLimitX96: 0
        });

        uint256 amountIn = ISwapRouter(_context.swapRouter).exactOutputSingle(params);

        if(_positionUpdate.zeroForOne) {
            return (int256(amountIn), -int256(_positionUpdate.param0));
        } else {
            return (-int256(_positionUpdate.param0), int256(amountIn));
        }

    }

    function getSqrtPrice(IUniswapV3Pool _uniswapPool) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = _uniswapPool.slot0();
    }

    function decreaseLiquidityFromUni(
        DataType.Context memory _context,
        DataType.PerpStatus storage _range,
        uint128 _liquidity,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint256 liquidityAmount = getTotalLiquidityAmount(INonfungiblePositionManager(_context.positionManager), _range.tokenId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams(_range.tokenId, _liquidity, _amount0Min, _amount1Min, block.timestamp);

        (amount0, amount1) = INonfungiblePositionManager(_context.positionManager).decreaseLiquidity(params);

        collectTokenAmountsFromUni(_context, _range, amount0, amount1, liquidityAmount);
    }

    function collectTokenAmountsFromUni(
        DataType.Context memory _context,
        DataType.PerpStatus storage _range,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _preLiquidity
    ) internal {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            _range.tokenId,
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        (uint256 a0, uint256 a1) = INonfungiblePositionManager(_context.positionManager).collect(params);

        // Update cumulative trade fee
        _range.fee0Growth += ((a0 - _amount0) * FixedPoint128.Q128) / _preLiquidity;
        _range.fee1Growth += ((a1 - _amount1) * FixedPoint128.Q128) / _preLiquidity;
    }

    function getTotalLiquidityAmount(INonfungiblePositionManager _positionManager, uint256 _tokenId) internal view returns (uint256) {
        (, , , , , , , uint128 liquidity, , , , ) = _positionManager.positions(_tokenId);

        return liquidity;
    }
}