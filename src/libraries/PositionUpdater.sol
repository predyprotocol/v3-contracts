// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/libraries/PositionKey.sol";
import "./BaseToken.sol";
import "./Constants.sol";
import "./DataType.sol";
import "./VaultLib.sol";
import "./InterestCalculator.sol";
import "./LPTStateLib.sol";
import "./UniHelper.sol";

/*
 * Error Codes
 * PU1: reduce only
 * PU2: margin must not be negative
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
    event TokenWithdrawn(uint256 indexed subVaultId, uint256 amount0, uint256 amount1);
    event TokenBorrowed(uint256 indexed subVaultId, uint256 amount0, uint256 amount1);
    event TokenRepaid(uint256 indexed subVaultId, uint256 amount0, uint256 amount1);
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
        uint256 amount1
    );
    event LPTBorrowed(uint256 indexed subVaultId, bytes32 rangeId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event LPTRepaid(uint256 indexed subVaultId, bytes32 rangeId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event FeeUpdated(uint256 indexed subVaultId, int256 fee0, int256 fee1);
    event TokenSwap(
        uint256 indexed vaultId,
        uint256 subVaultId,
        bool zeroForOne,
        uint256 srcAmount,
        uint256 destAmount
    );
    event MarginUpdated(uint256 indexed vaultId, int256 marginAmount0, int256 marginAmount1);
    event PositionUpdated(uint256 vaultId, DataType.PositionUpdateResult positionUpdateResult, bytes metadata);
    event FeeGrowthUpdated(int24 lowerTick, int24 upperTick, uint256 fee0Growth, uint256 fee1Growth);

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
    ) external returns (DataType.PositionUpdateResult memory result) {
        result.feeAmounts = collectFee(_context, _vault, _subVaults, _ranges);
        result.requiredAmounts.amount0 = result.feeAmounts.amount0;
        result.requiredAmounts.amount1 = result.feeAmounts.amount1;

        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            DataType.PositionUpdate memory positionUpdate = _positionUpdates[i];

            // create new sub-vault if needed
            DataType.SubVault storage subVault = _vault.addSubVault(_subVaults, _context, positionUpdate.subVaultIndex);

            if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_TOKEN) {
                require(!_tradeOption.isLiquidationCall, "PU1");

                depositTokens(subVault, _context, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.add(int256(positionUpdate.param0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.add(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_TOKEN) {
                (uint256 amount0, uint256 amount1) = withdrawTokens(subVault, _context, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.sub(int256(amount0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_TOKEN) {
                require(!_tradeOption.isLiquidationCall, "PU1");

                borrowTokens(subVault, _context, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.sub(int256(positionUpdate.param0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.sub(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_TOKEN) {
                (uint256 amount0, uint256 amount1) = repayTokens(subVault, _context, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.add(int256(amount0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_LPT) {
                require(!_tradeOption.isLiquidationCall, "PU1");

                (uint256 amount0, uint256 amount1) = depositLPT(subVault, _context, _ranges, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.add(int256(amount0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_LPT) {
                (uint256 amount0, uint256 amount1) = withdrawLPT(subVault, _context, _ranges, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.sub(int256(amount0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_LPT) {
                require(!_tradeOption.isLiquidationCall, "PU1");

                (uint256 amount0, uint256 amount1) = borrowLPT(subVault, _context, _ranges, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.sub(int256(amount0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_LPT) {
                (uint256 amount0, uint256 amount1) = repayLPT(subVault, _context, _ranges, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.add(int256(amount0));
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_IN) {
                (int256 amount0, int256 amount1) = swapExactIn(_vault, _context, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.add(amount0);
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.add(amount1);

                result.swapAmounts.amount0 = result.swapAmounts.amount0.add(amount0);
                result.swapAmounts.amount1 = result.swapAmounts.amount1.add(amount1);
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_OUT) {
                (int256 amount0, int256 amount1) = swapExactOut(_vault, _context, positionUpdate);

                result.requiredAmounts.amount0 = result.requiredAmounts.amount0.add(amount0);
                result.requiredAmounts.amount1 = result.requiredAmounts.amount1.add(amount1);

                result.swapAmounts.amount0 = result.swapAmounts.amount0.add(amount0);
                result.swapAmounts.amount1 = result.swapAmounts.amount1.add(amount1);
            }
        }

        if (_tradeOption.swapAnyway) {
            DataType.PositionUpdate memory positionUpdate = swapAnyway(
                result.requiredAmounts.amount0,
                result.requiredAmounts.amount1,
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

            result.requiredAmounts.amount0 = result.requiredAmounts.amount0.add(amount0);
            result.requiredAmounts.amount1 = result.requiredAmounts.amount1.add(amount1);

            result.swapAmounts.amount0 = result.swapAmounts.amount0.add(amount0);
            result.swapAmounts.amount1 = result.swapAmounts.amount1.add(amount1);
        }

        {
            // calculate position amounts
            result.positionAmounts.amount0 = result.requiredAmounts.amount0.sub(result.swapAmounts.amount0).sub(
                result.feeAmounts.amount0
            );
            result.positionAmounts.amount1 = result.requiredAmounts.amount1.sub(result.swapAmounts.amount1).sub(
                result.feeAmounts.amount1
            );
        }

        (result.requiredAmounts.amount0, result.requiredAmounts.amount1) = updateMargin(_vault, _tradeOption, result);

        if (!_tradeOption.isLiquidationCall) {
            require(_vault.marginAmount0 >= 0 && _vault.marginAmount1 >= 0, "PU2");
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

        emit PositionUpdated(_vault.vaultId, result, _tradeOption.metadata);
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

    /**
     * @notice Updates margin amounts to open position, close position, deposit and withdraw.
     * If isLiquidationCall is true, margin amounts can be negative value.
     * margin mode:
     * - MARGIN_USE means margin amount will be updated.
     * - MARGIN_STAY means margin amount will be never updated.
     */
    function updateMargin(
        DataType.Vault storage _vault,
        DataType.TradeOption memory _tradeOption,
        DataType.PositionUpdateResult memory result
    ) internal returns (int256 newRequiredAmount0, int256 newRequiredAmount1) {
        int256 deltaMarginAmount0;
        int256 deltaMarginAmount1;

        if (_tradeOption.marginMode0 == Constants.MARGIN_USE) {
            deltaMarginAmount0 = _tradeOption.deltaMarginAmount0.sub(result.requiredAmounts.amount0);

            if (!_tradeOption.isLiquidationCall && _vault.marginAmount0.add(deltaMarginAmount0) < 0) {
                deltaMarginAmount0 = _vault.marginAmount0.mul(-1);
            }

            _vault.marginAmount0 = _vault.marginAmount0.add(deltaMarginAmount0);

            newRequiredAmount0 = deltaMarginAmount0.add(result.requiredAmounts.amount0);

            require(_tradeOption.deltaMarginAmount0 != 0 || newRequiredAmount0 == 0, "PU2");
        } else {
            newRequiredAmount0 = result.requiredAmounts.amount0;
        }

        if (_tradeOption.marginMode1 == Constants.MARGIN_USE) {
            deltaMarginAmount1 = _tradeOption.deltaMarginAmount1.sub(result.requiredAmounts.amount1);

            if (!_tradeOption.isLiquidationCall && _vault.marginAmount1.add(deltaMarginAmount1) < 0) {
                deltaMarginAmount1 = _vault.marginAmount1.mul(-1);
            }

            _vault.marginAmount1 = _vault.marginAmount1.add(deltaMarginAmount1);

            newRequiredAmount1 = deltaMarginAmount1.add(result.requiredAmounts.amount1);

            require(_tradeOption.deltaMarginAmount1 != 0 || newRequiredAmount1 == 0, "PU2");
        } else {
            newRequiredAmount1 = result.requiredAmounts.amount1;
        }

        // emit event if needed
        if (deltaMarginAmount0 != 0 || deltaMarginAmount1 != 0) {
            emit MarginUpdated(_vault.vaultId, deltaMarginAmount0, deltaMarginAmount1);
        }
    }

    function depositTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal {
        require(_positionUpdate.param0 > 0 || _positionUpdate.param1 > 0);
        _context.tokenState0.addAsset(_subVault.balance0, _positionUpdate.param0, _positionUpdate.zeroForOne);
        _context.tokenState1.addAsset(_subVault.balance1, _positionUpdate.param1, _positionUpdate.zeroForOne);

        emit TokenDeposited(_subVault.id, _positionUpdate.param0, _positionUpdate.param1);
    }

    function withdrawTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 withdrawAmount0, uint256 withdrawAmount1) {
        require(_positionUpdate.param0 > 0 || _positionUpdate.param1 > 0);

        withdrawAmount0 = _context.tokenState0.removeAsset(_subVault.balance0, _positionUpdate.param0);
        withdrawAmount1 = _context.tokenState1.removeAsset(_subVault.balance1, _positionUpdate.param1);

        emit TokenWithdrawn(_subVault.id, withdrawAmount0, withdrawAmount1);
    }

    function borrowTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal {
        require(_positionUpdate.param0 > 0 || _positionUpdate.param1 > 0);

        _context.tokenState0.addDebt(_subVault.balance0, _positionUpdate.param0, _positionUpdate.zeroForOne);
        _context.tokenState1.addDebt(_subVault.balance1, _positionUpdate.param1, _positionUpdate.zeroForOne);

        emit TokenBorrowed(_subVault.id, _positionUpdate.param0, _positionUpdate.param1);
    }

    function repayTokens(
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        require(_positionUpdate.param0 > 0 || _positionUpdate.param1 > 0);

        requiredAmount0 = _context.tokenState0.removeDebt(_subVault.balance0, _positionUpdate.param0);
        requiredAmount1 = _context.tokenState1.removeDebt(_subVault.balance1, _positionUpdate.param1);

        emit TokenRepaid(_subVault.id, requiredAmount0, requiredAmount1);
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
    ) internal returns (uint256 withdrawnAmount0, uint256 withdrawnAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        uint128 liquidityAmount = _subVault.withdrawLPT(rangeId, _positionUpdate.liquidity);

        (withdrawnAmount0, withdrawnAmount1) = decreaseLiquidityFromUni(_context, _ranges[rangeId], liquidityAmount);

        emit LPTWithdrawn(_subVault.id, rangeId, liquidityAmount, withdrawnAmount0, withdrawnAmount1);
    }

    function borrowLPT(
        DataType.SubVault storage _subVault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 borrowedAmount0, uint256 borrowedAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (borrowedAmount0, borrowedAmount1) = decreaseLiquidityFromUni(
            _context,
            _ranges[rangeId],
            _positionUpdate.liquidity
        );

        _ranges[rangeId].borrowedLiquidity = _ranges[rangeId]
            .borrowedLiquidity
            .add(_positionUpdate.liquidity)
            .toUint128();

        _subVault.borrowLPT(_ranges[rangeId], rangeId, _positionUpdate.liquidity);

        emit LPTBorrowed(_subVault.id, rangeId, _positionUpdate.liquidity, borrowedAmount0, borrowedAmount1);
    }

    function repayLPT(
        DataType.SubVault storage _subVault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        uint128 liquidity = _subVault.repayLPT(rangeId, _positionUpdate.liquidity);

        (requiredAmount0, requiredAmount1) = IUniswapV3Pool(_context.uniswapPool).mint(
            address(this),
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            liquidity,
            ""
        );

        _ranges[rangeId].borrowedLiquidity = _ranges[rangeId].borrowedLiquidity.toUint256().sub(liquidity).toUint128();

        emit LPTRepaid(_subVault.id, rangeId, liquidity, requiredAmount0, requiredAmount1);
    }

    function swapExactIn(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {
        uint256 amountOut;

        {
            (int256 amount0, int256 amount1) = IUniswapV3Pool(_context.uniswapPool).swap(
                address(this),
                _positionUpdate.zeroForOne,
                int256(_positionUpdate.param0),
                (_positionUpdate.zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                ""
            );

            if (_positionUpdate.zeroForOne) {
                amountOut = (-amount1).toUint256();
            } else {
                amountOut = (-amount0).toUint256();
            }
        }

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
        uint256 amountIn;

        {
            (int256 amount0, int256 amount1) = IUniswapV3Pool(_context.uniswapPool).swap(
                address(this),
                _positionUpdate.zeroForOne,
                -int256(_positionUpdate.param0),
                (_positionUpdate.zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                ""
            );

            if (_positionUpdate.zeroForOne) {
                amountIn = amount0.toUint256();
            } else {
                amountIn = amount1.toUint256();
            }
        }

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

    /**
     * @notice Decreases liquidity from Uniswap pool.
     */
    function decreaseLiquidityFromUni(
        DataType.Context memory _context,
        DataType.PerpStatus storage _range,
        uint128 _liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = IUniswapV3Pool(_context.uniswapPool).burn(_range.lowerTick, _range.upperTick, _liquidity);

        // collect burned token amounts
        IUniswapV3Pool(_context.uniswapPool).collect(
            address(this),
            _range.lowerTick,
            _range.upperTick,
            amount0.toUint128(),
            amount1.toUint128()
        );
    }

    /**
     * @notice Collects trade fee and updates fee growth.
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
                updateFeeGrowthForRange(_context, _ranges[subVault.lpts[j].rangeId]);
            }
        }

        // calculate trade fee for ranges that trader would open
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdates[i].lowerTick, _positionUpdates[i].upperTick);

            updateFeeGrowthForRange(_context, _ranges[rangeId]);
        }
    }

    function updateFeeGrowthForRange(DataType.Context memory _context, DataType.PerpStatus storage _range) public {
        if (_range.lastTouchedTimestamp == 0) {
            return;
        }

        uint256 totalLiquidity = LPTStateLib.getTotalLiquidityAmount(address(this), _context.uniswapPool, _range);

        if (totalLiquidity == 0) {
            emit FeeGrowthUpdated(_range.lowerTick, _range.upperTick, _range.fee0Growth, _range.fee1Growth);

            return;
        }

        {
            // Skip fee collection if utilization ratio is 100%
            uint256 availableLiquidity = LPTStateLib.getAvailableLiquidityAmount(
                address(this),
                _context.uniswapPool,
                _range
            );

            if (availableLiquidity == 0) {
                return;
            }
        }

        // burn 0 amount of LPT to collect trade fee from Uniswap pool.
        IUniswapV3Pool(_context.uniswapPool).burn(_range.lowerTick, _range.upperTick, 0);

        // collect trade fee
        (uint256 collect0, uint256 collect1) = IUniswapV3Pool(_context.uniswapPool).collect(
            address(this),
            _range.lowerTick,
            _range.upperTick,
            type(uint128).max,
            type(uint128).max
        );

        _range.fee0Growth = _range.fee0Growth.add(PredyMath.mulDiv(collect0, Constants.ONE, totalLiquidity));
        _range.fee1Growth = _range.fee1Growth.add(PredyMath.mulDiv(collect1, Constants.ONE, totalLiquidity));

        emit FeeGrowthUpdated(_range.lowerTick, _range.upperTick, _range.fee0Growth, _range.fee1Growth);
    }

    function collectFee(
        DataType.Context memory _context,
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) internal returns (DataType.TokenAmounts memory requiredAmounts) {
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault storage subVault = _subVaults[_vault.subVaults[i]];

            (int256 requiredAmount0, int256 requiredAmount1) = collectFeeOfSubVault(_context, subVault, _ranges);

            requiredAmounts.amount0 = requiredAmounts.amount0.add(requiredAmount0);
            requiredAmounts.amount1 = requiredAmounts.amount1.add(requiredAmount1);
        }
    }

    function collectFeeOfSubVault(
        DataType.Context memory _context,
        DataType.SubVault storage _subVault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {
        int256 totalFee0;
        int256 totalFee1;

        {
            (int256 fee0, int256 fee1) = VaultLib.getPremiumAndFeeOfSubVault(_subVault, _ranges, _context);
            (int256 assetFee0, int256 assetFee1, int256 debtFee0, int256 debtFee1) = VaultLib
                .getTokenInterestOfSubVault(_subVault, _context);

            totalFee0 = fee0.add(assetFee0).sub(debtFee0);
            totalFee1 = fee1.add(assetFee1).sub(debtFee1);
        }

        _context.tokenState0.refreshFee(_subVault.balance0);
        _context.tokenState1.refreshFee(_subVault.balance1);

        for (uint256 i = 0; i < _subVault.lpts.length; i++) {
            DataType.LPTState storage lpt = _subVault.lpts[i];

            if (lpt.isCollateral) {
                lpt.premiumGrowthLast = _ranges[lpt.rangeId].premiumGrowthForLender;
                lpt.fee0Last = _ranges[lpt.rangeId].fee0Growth;
                lpt.fee1Last = _ranges[lpt.rangeId].fee1Growth;
            } else {
                lpt.premiumGrowthLast = _ranges[lpt.rangeId].premiumGrowthForBorrower;
            }
        }

        requiredAmount0 = totalFee0.mul(-1);
        requiredAmount1 = totalFee1.mul(-1);

        emit FeeUpdated(_subVault.id, totalFee0, totalFee1);
    }
}
