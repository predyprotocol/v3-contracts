// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/libraries/PositionKey.sol";
import "./BaseToken.sol";
import "./Constants.sol";
import "./DataType.sol";
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
    using SafeMath for uint128;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using SafeCast for int256;
    using BaseToken for BaseToken.TokenState;
    using VaultLib for DataType.Vault;
    using VaultLib for DataType.SubVault;
    using LPTStateLib for DataType.PerpStatus;

    event TokenDeposited(uint256 indexed subVaultId, uint256 amount0, uint256 amount1);
    event TokenWithdrawn(uint256 indexed subVaultId, uint256 amount0, uint256 amount1, int256 fee0, int256 fee1);
    event TokenBorrowed(uint256 indexed subVaultId, uint256 amount0, uint256 amount1);
    event TokenRepaid(uint256 indexed subVaultId, uint256 amount0, uint256 amount1, int256 fee0, int256 fee1);
    event LPTDeposited(
        uint256 indexed subVaultId,
        bytes32 rangeId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    event LPTWithdrawn(
        uint256 indexed subVaultId,
        bytes32 rangeId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        int256 fee0,
        int256 fee1
    );
    event LPTBorrowed(uint256 indexed subVaultId, bytes32 rangeId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event LPTRepaid(
        uint256 indexed subVaultId,
        bytes32 rangeId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        int256 fee0,
        int256 fee1
    );
    event TokenSwap(
        uint256 indexed vaultId,
        uint256 subVaultId,
        bool zeroForOne,
        uint256 srcAmount,
        uint256 destAmount
    );
    event MarginUpdated(uint256 indexed vaultId, int256 marginAmount0, int256 marginAmount1);

    /**
     * @notice update position and return required token amounts.
     */
    function updatePosition(
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates,
        DataType.TradeOption memory _tradeOption
    ) external returns (int256 requiredAmount0, int256 requiredAmount1) {
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            DataType.PositionUpdate memory positionUpdate = _positionUpdates[i];

            // create new sub-vault if needed
            DataType.SubVault storage subVault = _vault.addSubVault(_subVaults, _context, positionUpdate.subVaultIndex);

            if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_TOKEN) {
                require(!_tradeOption.reduceOnly, "PU1");

                depositTokens(subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.add(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_TOKEN) {
                (uint256 amount0, uint256 amount1) = withdrawTokens(subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_TOKEN) {
                require(!_tradeOption.reduceOnly, "PU1");
                borrowTokens(subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_TOKEN) {
                (uint256 amount0, uint256 amount1) = repayTokens(subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_LPT) {
                require(!_tradeOption.reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = depositLPT(subVault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_LPT) {
                (uint256 amount0, uint256 amount1) = withdrawLPT(subVault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_LPT) {
                require(!_tradeOption.reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = borrowLPT(subVault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_LPT) {
                (uint256 amount0, uint256 amount1) = repayLPT(subVault, _context, _ranges, positionUpdate);

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
            DataType.PositionUpdate memory positionUpdate = swapAnyway(
                requiredAmount0,
                requiredAmount1,
                _tradeOption.isQuoteZero,
                _context.feeTier
            );
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

        {
            // Deposits or withdraw margin
            // targetMarginAmount0 and targetMarginAmount1 determine the margin target.
            // -1 means that the margin is no changed.
            // -2 means that make requiredAmounts 0 by using margin amount.
            int256 deltaMarginAmount0;
            int256 deltaMarginAmount1;

            if (_tradeOption.targetMarginAmount0 >= 0) {
                // update margin amount of token0 to target margin amount
                deltaMarginAmount0 = _tradeOption.targetMarginAmount0.sub(int256(_vault.marginAmount0));

                _vault.marginAmount0 = uint256(_tradeOption.targetMarginAmount0);

                requiredAmount0 = requiredAmount0.add(deltaMarginAmount0);
            } else if (_tradeOption.targetMarginAmount0 == Constants.MARGIN_USE) {
                // use margin of token0 to make required amount 0
                deltaMarginAmount0 = requiredAmount0.mul(-1);

                _vault.marginAmount0 = PredyMath.addDelta(_vault.marginAmount0, deltaMarginAmount0);

                requiredAmount0 = 0;
            }

            if (_tradeOption.targetMarginAmount1 >= 0) {
                // update margin amount of token1 to target margin amount
                deltaMarginAmount1 = _tradeOption.targetMarginAmount1.sub(int256(_vault.marginAmount1));

                _vault.marginAmount1 = uint256(_tradeOption.targetMarginAmount1);

                requiredAmount1 = requiredAmount1.add(deltaMarginAmount1);
            } else if (_tradeOption.targetMarginAmount1 == Constants.MARGIN_USE) {
                // use margin of token1 to make required amount 0
                deltaMarginAmount1 = requiredAmount1.mul(-1);

                _vault.marginAmount1 = PredyMath.addDelta(_vault.marginAmount1, deltaMarginAmount1);

                requiredAmount1 = 0;
            }

            // emit event if needed
            if (deltaMarginAmount0 != 0 || deltaMarginAmount1 != 0) {
                emit MarginUpdated(_vault.vaultId, deltaMarginAmount0, deltaMarginAmount1);
            }
        }

        // remove empty sub-vaults
        if (_vault.subVaults.length > 0) {
            uint256 length = _vault.subVaults.length;
            for (uint256 i = 0; i < length; i++) {
                uint256 index = length - i - 1;
                DataType.SubVault memory subVault = _subVaults[_vault.subVaults[index]];

                if (
                    subVault.balance0.assetAmount == 0 &&
                    subVault.balance0.debtAmount == 0 &&
                    subVault.balance1.assetAmount == 0 &&
                    subVault.balance1.debtAmount == 0 &&
                    subVault.lpts.length == 0
                ) {
                    _vault.removeSubVault(index);
                }
            }
        }
    }

    function swapAnyway(
        int256 requiredAmount0,
        int256 requiredAmount1,
        bool _isQuoteZero,
        uint24 _feeTier
    ) internal pure returns (DataType.PositionUpdate memory) {
        bool zeroForOne;
        bool isExactIn;
        uint256 amountIn;
        uint256 amountOut;

        if (_isQuoteZero) {
            if (requiredAmount1 > 0) {
                zeroForOne = true;
                isExactIn = false;
                amountOut = uint256(requiredAmount1);
            } else if (requiredAmount1 < 0) {
                zeroForOne = false;
                isExactIn = true;
                amountIn = uint256(-requiredAmount1);
            }
        } else {
            if (requiredAmount0 > 0) {
                zeroForOne = false;
                isExactIn = false;
                amountOut = uint256(requiredAmount0);
            } else if (requiredAmount0 < 0) {
                zeroForOne = true;
                isExactIn = true;
                amountIn = uint256(-requiredAmount0);
            }
        }

        if (isExactIn && amountIn > 0) {
            return
                DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_IN,
                    0,
                    zeroForOne,
                    _feeTier,
                    0,
                    0,
                    amountIn,
                    0
                );
        } else if (!isExactIn && amountOut > 0) {
            return
                DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    0,
                    zeroForOne,
                    _feeTier,
                    0,
                    0,
                    amountOut,
                    0
                );
        } else {
            return DataType.PositionUpdate(DataType.PositionUpdateType.NOOP, 0, false, 0, 0, 0, 0, 0);
        }
    }

    function depositTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal {
        _context.tokenState0.addAsset(_subVault.balance0, _positionUpdate.param0, _positionUpdate.zeroForOne);
        _context.tokenState1.addAsset(_subVault.balance1, _positionUpdate.param1, _positionUpdate.zeroForOne);

        emit TokenDeposited(_subVault.id, _positionUpdate.param0, _positionUpdate.param1);
    }

    function withdrawTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 withdrawAmount0, uint256 withdrawAmount1) {
        uint256 assetFee0;
        uint256 assetFee1;

        (withdrawAmount0, assetFee0) = _context.tokenState0.removeAsset(_subVault.balance0, _positionUpdate.param0);
        (withdrawAmount1, assetFee1) = _context.tokenState1.removeAsset(_subVault.balance1, _positionUpdate.param1);

        emit TokenWithdrawn(_subVault.id, withdrawAmount0, withdrawAmount1, int256(assetFee0), int256(assetFee1));

        withdrawAmount0 = withdrawAmount0.add(assetFee0);
        withdrawAmount1 = withdrawAmount1.add(assetFee1);
    }

    function borrowTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal {
        _context.tokenState0.addDebt(_subVault.balance0, _positionUpdate.param0, _positionUpdate.zeroForOne);
        _context.tokenState1.addDebt(_subVault.balance1, _positionUpdate.param1, _positionUpdate.zeroForOne);

        emit TokenBorrowed(_subVault.id, _positionUpdate.param0, _positionUpdate.param1);
    }

    function repayTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        uint256 debtFee0;
        uint256 debtFee1;

        (requiredAmount0, debtFee0) = _context.tokenState0.removeDebt(_subVault.balance0, _positionUpdate.param0);
        (requiredAmount1, debtFee1) = _context.tokenState1.removeDebt(_subVault.balance1, _positionUpdate.param1);

        emit TokenRepaid(_subVault.id, requiredAmount0, requiredAmount1, -int256(debtFee0), -int256(debtFee1));

        requiredAmount0 = requiredAmount0.add(debtFee0);
        requiredAmount1 = requiredAmount1.add(debtFee1);
    }

    function depositLPT(
        DataType.SubVault storage _subVault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (requiredAmount0, requiredAmount1) = IUniswapV3Pool(_context.uniswapPool).mint(
            address(this),
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            _positionUpdate.liquidity,
            ""
        );

        if (_ranges[rangeId].lastTouchedTimestamp == 0) {
            _ranges[rangeId].registerNewLPTState(_positionUpdate.lowerTick, _positionUpdate.upperTick);
        }

        _subVault.depositLPT(_ranges[rangeId], rangeId, _positionUpdate.liquidity);

        emit LPTDeposited(_subVault.id, rangeId, _positionUpdate.liquidity, requiredAmount0, requiredAmount1);
    }

    function withdrawLPT(
        DataType.SubVault storage _subVault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 withdrawAmount0, uint256 withdrawAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (uint256 fee0, uint256 fee1, uint128 liquidityAmount) = _subVault.withdrawLPT(
            _ranges[rangeId],
            rangeId,
            _positionUpdate.liquidity,
            _context.isMarginZero
        );

        (withdrawAmount0, withdrawAmount1) = decreaseLiquidityFromUni(_context, _ranges[rangeId], liquidityAmount);

        emit LPTWithdrawn(
            _subVault.id,
            rangeId,
            liquidityAmount,
            withdrawAmount0,
            withdrawAmount1,
            int256(fee0),
            int256(fee1)
        );

        withdrawAmount0 = withdrawAmount0.add(fee0);
        withdrawAmount1 = withdrawAmount1.add(fee1);
    }

    function borrowLPT(
        DataType.SubVault storage _subVault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (requiredAmount0, requiredAmount1) = decreaseLiquidityFromUni(
            _context,
            _ranges[rangeId],
            _positionUpdate.liquidity
        );

        _ranges[rangeId].borrowedLiquidity = _ranges[rangeId]
            .borrowedLiquidity
            .add(_positionUpdate.liquidity)
            .toUint128();

        _subVault.borrowLPT(_ranges[rangeId], rangeId, _positionUpdate.liquidity);

        emit LPTBorrowed(_subVault.id, rangeId, _positionUpdate.liquidity, requiredAmount0, requiredAmount1);
    }

    function repayLPT(
        DataType.SubVault storage _subVault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (uint256 fee0, uint256 fee1, uint128 liquidity) = _subVault.repayLPT(
            _ranges[rangeId],
            rangeId,
            _positionUpdate.liquidity,
            _context.isMarginZero
        );

        (requiredAmount0, requiredAmount1) = IUniswapV3Pool(_context.uniswapPool).mint(
            address(this),
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            liquidity,
            ""
        );

        _ranges[rangeId].borrowedLiquidity = _ranges[rangeId].borrowedLiquidity.toUint256().sub(liquidity).toUint128();

        {
            emit LPTRepaid(
                _subVault.id,
                rangeId,
                liquidity,
                requiredAmount0,
                requiredAmount1,
                -int256(fee0),
                -int256(fee1)
            );

            requiredAmount0 = requiredAmount0.add(fee0);
            requiredAmount1 = requiredAmount1.add(fee1);
        }
    }

    function swapExactIn(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _positionUpdate.zeroForOne ? _context.token0 : _context.token1,
            tokenOut: _positionUpdate.zeroForOne ? _context.token1 : _context.token0,
            fee: uint24(_positionUpdate.liquidity),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _positionUpdate.param0,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(_context.swapRouter).exactInputSingle(params);

        emit TokenSwap(
            _vault.vaultId,
            _vault.subVaults[_positionUpdate.subVaultIndex],
            _positionUpdate.zeroForOne,
            _positionUpdate.param0,
            amountOut
        );

        if (_positionUpdate.zeroForOne) {
            return (int256(_positionUpdate.param0), -int256(amountOut));
        } else {
            return (-int256(amountOut), int256(_positionUpdate.param0));
        }
    }

    function swapExactOut(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _positionUpdate.zeroForOne ? _context.token0 : _context.token1,
            tokenOut: _positionUpdate.zeroForOne ? _context.token1 : _context.token0,
            fee: uint24(_positionUpdate.liquidity),
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _positionUpdate.param0,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        uint256 amountIn = ISwapRouter(_context.swapRouter).exactOutputSingle(params);

        emit TokenSwap(
            _vault.vaultId,
            _vault.subVaults[_positionUpdate.subVaultIndex],
            _positionUpdate.zeroForOne,
            amountIn,
            _positionUpdate.param0
        );

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
    function updateFeeGrowth(
        DataType.Context memory _context,
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates
    ) external {
        // calculate trade fee for ranges that the vault has
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault memory subVault = _subVaults[_vault.subVaults[i]];

            for (uint256 j = 0; j < subVault.lpts.length; j++) {
                collectTradeFeeFromUni(_context, _ranges[subVault.lpts[j].rangeId]);
            }
        }

        // calculate trade fee for ranges that trader would open
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdates[i].lowerTick, _positionUpdates[i].upperTick);

            // if range is not initialized, skip calculation.
            if (_ranges[rangeId].lastTouchedTimestamp == 0) {
                continue;
            }

            collectTradeFeeFromUni(_context, _ranges[rangeId]);
        }
    }

    function decreaseLiquidityFromUni(
        DataType.Context memory _context,
        DataType.PerpStatus storage _range,
        uint128 _liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = IUniswapV3Pool(_context.uniswapPool).burn(_range.lowerTick, _range.upperTick, _liquidity);

        collectTokenAmountsFromUni(_context, _range);
    }

    function collectTokenAmountsFromUni(DataType.Context memory _context, DataType.PerpStatus storage _range) internal {
        IUniswapV3Pool(_context.uniswapPool).collect(
            address(this),
            _range.lowerTick,
            _range.upperTick,
            type(uint128).max,
            type(uint128).max
        );
    }

    function collectTradeFeeFromUni(DataType.Context memory _context, DataType.PerpStatus storage _range) internal {
        // Update cumulative trade fee
        (uint256 fee0Growth, uint256 fee1Growth) = getFeeGrowth(
            IUniswapV3Pool(_context.uniswapPool),
            _range.lowerTick,
            _range.upperTick
        );

        _range.fee0Growth = PredyMath.mulDiv(fee0Growth, Constants.ONE, FixedPoint128.Q128);
        _range.fee1Growth = PredyMath.mulDiv(fee1Growth, Constants.ONE, FixedPoint128.Q128);
    }

    function getFeeGrowth(
        IUniswapV3Pool _uniswapPool,
        int24 _tickLower,
        int24 _tickUpper
    ) internal view returns (uint256, uint256) {
        bytes32 positionKey = PositionKey.compute(address(this), _tickLower, _tickUpper);

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = _uniswapPool.positions(
            positionKey
        );

        return (feeGrowthInside0LastX128, feeGrowthInside1LastX128);
    }
}
