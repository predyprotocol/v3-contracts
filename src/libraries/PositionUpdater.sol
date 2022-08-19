// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import "./DataType.sol";
import "./BaseToken.sol";
import "./VaultLib.sol";
import "./LPTStateLib.sol";
import "./UniHelper.sol";

/*
 * Error Codes
 * PU1: reduce only
 * PU2: L must be lower
 * PU3: L must be greater
 */
library PositionUpdater {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using BaseToken for BaseToken.TokenState;
    using VaultLib for DataType.Vault;
    using LPTStateLib for DataType.PerpStatus;

    event TokenDeposited(uint256 indexed vaultId, uint256 amount0, uint256 amount1);
    event TokenWithdrawn(uint256 indexed vaultId, uint256 amount0, uint256 amount1);
    event TokenBorrowed(uint256 indexed vaultId, uint256 amount0, uint256 amount1);
    event TokenRepaid(uint256 indexed vaultId, uint256 amount0, uint256 amount1);
    event LPTDeposited(uint256 indexed vaultId, int24 lowerTick, int24 upperTick, uint128 liquidity);
    event LPTWithdrawn(uint256 indexed vaultId, int24 lowerTick, int24 upperTick, uint128 liquidity);
    event LPTBorrowed(uint256 indexed vaultId, int24 lowerTick, int24 upperTick, uint128 liquidity);
    event LPTRepaid(uint256 indexed vaultId, int24 lowerTick, int24 upperTick, uint128 liquidity);
    event TokenSwap(uint256 indexed vaultId, bool zeroForOne, uint256 srcAmount, uint256 destAmount);

    event FeeCollected(uint256 indexed vaultId, int256 feeAmount0, int256 feeAmount1);

    /**
     * @notice update position and return required token amounts.
     */
    function updatePosition(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates,
        DataType.TradeOption memory _tradeOption
    ) external returns (int256 requiredAmount0, int256 requiredAmount1) {
        collectFeeAndPremium(_context, _vault, _ranges);

        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            DataType.PositionUpdate memory positionUpdate = _positionUpdates[i];

            if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_TOKEN) {
                require(!_tradeOption.reduceOnly, "PU1");
                depositTokens(_vault, _context, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.add(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.add(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_TOKEN) {
                (uint256 amount0, uint256 amount1) = withdrawTokens(
                    _vault,
                    _context,
                    positionUpdate.param0,
                    positionUpdate.param1
                );

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_TOKEN) {
                require(!_tradeOption.reduceOnly, "PU1");
                borrowTokens(_vault, _context, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_TOKEN) {
                (uint256 amount0, uint256 amount1) = repayTokens(
                    _vault,
                    _context,
                    positionUpdate.param0,
                    positionUpdate.param1
                );

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_LPT) {
                require(!_tradeOption.reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = depositLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_LPT) {
                (uint256 amount0, uint256 amount1) = withdrawLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_LPT) {
                require(!_tradeOption.reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = borrowLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_LPT) {
                (uint256 amount0, uint256 amount1) = repayLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_IN) {
                (int256 amount0, int256 amount1) = swapExactIn(_vault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(amount0);
                requiredAmount1 = requiredAmount1.add(amount1);
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_OUT) {
                (int256 amount0, int256 amount1) = swapExactOut(_vault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(amount0);
                requiredAmount1 = requiredAmount1.add(amount1);
            }
        }

        if (_tradeOption.swapAnyway) {
            DataType.PositionUpdate memory positionUpdate = swapAnyway(_context, requiredAmount0, requiredAmount1);
            int256 amount0;
            int256 amount1;

            if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_IN) {
                (amount0, amount1) = swapExactIn(_vault, _context, positionUpdate);
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_OUT) {
                (amount0, amount1) = swapExactOut(_vault, _context, positionUpdate);
            }

            requiredAmount0 = requiredAmount0.add(amount0);
            requiredAmount1 = requiredAmount1.add(amount1);
        }
    }

    function swapAnyway(
        DataType.Context storage _context,
        int256 requiredAmount0,
        int256 requiredAmount1
    ) internal view returns (DataType.PositionUpdate memory) {
        address tokenIn;
        address tokenOut;
        bool zeroForOne;
        bool isExactIn;
        uint256 amountIn;
        uint256 amountOut;

        if (requiredAmount0 > 0 && requiredAmount1 > 0) {
            return DataType.PositionUpdate(DataType.PositionUpdateType.NOOP, false, 0, 0, 0, 0, 0);
        }

        if (requiredAmount0 < 0 && requiredAmount1 < 0) {
            // exact in
            isExactIn = true;

            if (_context.isMarginZero) {
                zeroForOne = false;
                tokenIn = _context.token1;
                tokenOut = _context.token0;
                amountIn = uint256(-requiredAmount1);
                amountOut = 0;
            } else {
                zeroForOne = true;
                tokenIn = _context.token0;
                tokenOut = _context.token1;
                amountIn = uint256(-requiredAmount0);
                amountOut = 0;
            }
        }

        if (requiredAmount0 > 0 && requiredAmount1 < 0) {
            zeroForOne = false;

            if (_context.isMarginZero) {
                // exact in
                isExactIn = true;
                tokenIn = _context.token1;
                tokenOut = _context.token0;
                amountIn = uint256(-requiredAmount1);
                amountOut = uint256(requiredAmount0);
            } else {
                // exact out
                isExactIn = false;
                tokenIn = _context.token1;
                tokenOut = _context.token0;
                amountOut = uint256(requiredAmount0);
                amountIn = uint256(-requiredAmount1);
            }
        }

        if (requiredAmount0 < 0 && requiredAmount1 > 0) {
            zeroForOne = true;

            if (_context.isMarginZero) {
                // exact out
                isExactIn = false;
                tokenIn = _context.token0;
                tokenOut = _context.token1;
                amountOut = uint256(requiredAmount1);
                amountIn = uint256(-requiredAmount0);
            } else {
                // exact in
                isExactIn = true;
                tokenIn = _context.token0;
                tokenOut = _context.token1;
                amountIn = uint256(-requiredAmount0);
                amountOut = uint256(requiredAmount1);
            }
        }

        if (isExactIn) {
            return
                DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_IN,
                    zeroForOne,
                    0,
                    0,
                    0,
                    amountIn,
                    amountOut
                );

            /*
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: _context.feeTier,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOut,
                sqrtPriceLimitX96: 0
            });

            amountOut = ISwapRouter(_context.swapRouter).exactInputSingle(params);
            */
        } else {
            return
                DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    zeroForOne,
                    0,
                    0,
                    0,
                    amountOut,
                    amountIn
                );

            /*
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: _context.feeTier,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountIn,
                sqrtPriceLimitX96: 0
            });

            amountIn = ISwapRouter(_context.swapRouter).exactOutputSingle(params);
            */
        }

        /*
        emit TokenSwap(_vault.vaultId, tokenIn == _context.token0, amountIn, amountOut);

        if(tokenIn == _context.token0) {
            return (requiredAmount0 + int256(amountIn), requiredAmount1 - int256(amountOut));
        } else {
            return (requiredAmount0 - int256(amountOut), requiredAmount1 + int256(amountIn));
        }
        */
    }

    function depositTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal {
        _context.tokenState0.addCollateral(_vault.balance0, amount0, true);
        _context.tokenState1.addCollateral(_vault.balance1, amount1, true);

        emit TokenDeposited(_vault.vaultId, amount0, amount1);
    }

    function withdrawTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 withdrawAmount0, uint256 withdrawAmount1) {
        withdrawAmount0 = _context.tokenState0.removeCollateral(_vault.balance0, amount0, true);
        withdrawAmount1 = _context.tokenState1.removeCollateral(_vault.balance1, amount1, true);

        emit TokenWithdrawn(_vault.vaultId, withdrawAmount0, withdrawAmount1);
    }

    function borrowTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal {
        _context.tokenState0.addDebt(_vault.balance0, amount0);
        _context.tokenState1.addDebt(_vault.balance1, amount1);

        emit TokenBorrowed(_vault.vaultId, amount0, amount1);
    }

    function repayTokens(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        requiredAmount0 = _context.tokenState0.removeDebt(_vault.balance0, amount0);
        requiredAmount1 = _context.tokenState1.removeDebt(_vault.balance1, amount1);

        emit TokenRepaid(_vault.vaultId, requiredAmount0, requiredAmount1);
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

        // liquidity amount actually deposited
        uint128 finalLiquidityAmount;

        if (_ranges[rangeId].tokenId > 0) {
            (, finalLiquidityAmount, requiredAmount0, requiredAmount1) = UniHelper.increaseLiquidity(
                _context,
                _ranges[rangeId].tokenId,
                amount0,
                amount1,
                _positionUpdate.param0,
                _positionUpdate.param1
            );
        } else {
            uint256 tokenId = 0;

            (tokenId, finalLiquidityAmount, requiredAmount0, requiredAmount1) = UniHelper.mint(
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

        require(finalLiquidityAmount <= _positionUpdate.liquidity, "PU3");

        _vault.depositLPT(_ranges, rangeId, finalLiquidityAmount);

        emit LPTDeposited(_vault.vaultId, _positionUpdate.lowerTick, _positionUpdate.upperTick, finalLiquidityAmount);
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

        _vault.withdrawLPT(rangeId, _positionUpdate.liquidity);

        emit LPTWithdrawn(
            _vault.vaultId,
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            _positionUpdate.liquidity
        );
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

        emit LPTBorrowed(
            _vault.vaultId,
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            _positionUpdate.liquidity
        );
    }

    function repayLPT(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidityRoundUp(
            getSqrtPrice(IUniswapV3Pool(_context.uniswapPool)),
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            _positionUpdate.liquidity
        );

        // liquidity amount actually deposited
        uint128 finalLiquidityAmount;

        (, finalLiquidityAmount, requiredAmount0, requiredAmount1) = UniHelper.increaseLiquidity(
            _context,
            _ranges[rangeId].tokenId,
            amount0,
            amount1,
            _positionUpdate.param0,
            _positionUpdate.param1
        );

        require(finalLiquidityAmount >= _positionUpdate.liquidity, "PU2");

        _ranges[rangeId].borrowedLiquidity = _ranges[rangeId]
            .borrowedLiquidity
            .toUint256()
            .sub(_positionUpdate.liquidity)
            .toUint128();

        _vault.repayLPT(rangeId, _positionUpdate.liquidity);

        emit LPTRepaid(_vault.vaultId, _positionUpdate.lowerTick, _positionUpdate.upperTick, _positionUpdate.liquidity);
    }

    function swapExactIn(
        DataType.Vault memory _vault,
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

        emit TokenSwap(_vault.vaultId, _positionUpdate.zeroForOne, _positionUpdate.param0, amountOut);

        if (_positionUpdate.zeroForOne) {
            return (int256(_positionUpdate.param0), -int256(amountOut));
        } else {
            return (-int256(amountOut), int256(_positionUpdate.param0));
        }
    }

    function swapExactOut(
        DataType.Vault memory _vault,
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

        emit TokenSwap(_vault.vaultId, _positionUpdate.zeroForOne, amountIn, _positionUpdate.param0);

        if (_positionUpdate.zeroForOne) {
            return (int256(amountIn), -int256(_positionUpdate.param0));
        } else {
            return (-int256(_positionUpdate.param0), int256(amountIn));
        }
    }

    function getSqrtPrice(IUniswapV3Pool _uniswapPool) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = _uniswapPool.slot0();
    }

    /**
     * @notice Collects trade fee and premium.
     */
    function collectFeeAndPremium(
        DataType.Context storage _context,
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) public returns (int256 feeAmount0, int256 feeAmount1) {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            collectTradeFeeFromUni(_context, _ranges[_vault.lpts[i].rangeId]);
        }

        {
            (uint256 fee0, uint256 fee1) = _vault.getEarnedTradeFee(_ranges);
            uint256 earnedPremium = _vault.getEarnedDailyPremium(_ranges);
            uint256 paidPremium = _vault.getPaidDailyPremium(_ranges);

            feeAmount0 += int256(fee0);
            feeAmount1 += int256(fee1);

            if (_context.isMarginZero) {
                feeAmount0 += int256(earnedPremium) - int256(paidPremium);
            } else {
                feeAmount1 += int256(earnedPremium) - int256(paidPremium);
            }
        }

        if (feeAmount0 > 0 && feeAmount1 > 0) {
            depositTokens(_vault, _context, uint256(feeAmount0), uint256(feeAmount1));
        } else if (feeAmount0 > 0) {
            depositTokens(_vault, _context, uint256(feeAmount0), 0);
        } else if (feeAmount1 > 0) {
            depositTokens(_vault, _context, 0, uint256(feeAmount1));
        }

        if (feeAmount0 < 0) {
            borrowTokens(_vault, _context, uint256(-feeAmount0), 0);
        }
        if (feeAmount1 < 0) {
            borrowTokens(_vault, _context, 0, uint256(-feeAmount1));
        }

        // update entry price
        updateFeeEntry(_vault, _ranges);

        // emit event
        if (feeAmount0 != 0 || feeAmount1 != 0) {
            emit FeeCollected(_vault.vaultId, feeAmount0, feeAmount1);
        }
    }

    function updateFeeEntry(DataType.Vault storage _vault, mapping(bytes32 => DataType.PerpStatus) storage _ranges)
        internal
    {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            DataType.LPTState storage lptState = _vault.lpts[i];

            if (lptState.isCollateral) {
                lptState.premiumGrowthLast = _ranges[lptState.rangeId].premiumGrowthForLender;
                lptState.fee0Last = _ranges[lptState.rangeId].fee0Growth;
                lptState.fee1Last = _ranges[lptState.rangeId].fee1Growth;
            } else {
                lptState.premiumGrowthLast = _ranges[lptState.rangeId].premiumGrowthForBorrower;
            }
        }
    }

    function decreaseLiquidityFromUni(
        DataType.Context memory _context,
        DataType.PerpStatus storage _range,
        uint128 _liquidity,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams(_range.tokenId, _liquidity, _amount0Min, _amount1Min, block.timestamp);

        (amount0, amount1) = INonfungiblePositionManager(_context.positionManager).decreaseLiquidity(params);

        collectTokenAmountsFromUni(_context, _range, amount0.toUint128(), amount1.toUint128());
    }

    function collectTokenAmountsFromUni(
        DataType.Context memory _context,
        DataType.PerpStatus storage _range,
        uint128 _amount0,
        uint128 _amount1
    ) internal {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            _range.tokenId,
            address(this),
            _amount0,
            _amount1
        );

        (uint256 a0, uint256 a1) = INonfungiblePositionManager(_context.positionManager).collect(params);

        require(_amount0 == a0 && _amount1 == a1);
    }

    function collectTradeFeeFromUni(DataType.Context memory _context, DataType.PerpStatus storage _range) internal {
        uint256 liquidityAmount = getTotalLiquidityAmount(
            INonfungiblePositionManager(_context.positionManager),
            _range.tokenId
        );

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            _range.tokenId,
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        (uint256 a0, uint256 a1) = INonfungiblePositionManager(_context.positionManager).collect(params);

        // Update cumulative trade fee
        _range.fee0Growth += (a0 * FixedPoint128.Q128) / liquidityAmount;
        _range.fee1Growth += (a1 * FixedPoint128.Q128) / liquidityAmount;
    }

    function getTotalLiquidityAmount(INonfungiblePositionManager _positionManager, uint256 _tokenId)
        internal
        view
        returns (uint256)
    {
        (, , , , , , , uint128 liquidity, , , , ) = _positionManager.positions(_tokenId);

        return liquidity;
    }
}
