// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
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

    event TokenDeposited(uint256 indexed vaultId, uint256 subVaultIndex, uint256 amount0, uint256 amount1);
    event TokenWithdrawn(uint256 indexed vaultId, uint256 subVaultIndex, uint256 amount0, uint256 amount1);
    event TokenBorrowed(uint256 indexed vaultId, uint256 subVaultIndex, uint256 amount0, uint256 amount1);
    event TokenRepaid(uint256 indexed vaultId, uint256 subVaultIndex, uint256 amount0, uint256 amount1);
    event LPTDeposited(uint256 indexed vaultId, uint256 subVaultIndex, bytes32 rangeId, uint128 liquidity);
    event LPTWithdrawn(uint256 indexed vaultId, uint256 subVaultIndex, bytes32 rangeId, uint128 liquidity);
    event LPTBorrowed(uint256 indexed vaultId, uint256 subVaultIndex, bytes32 rangeId, uint128 liquidity);
    event LPTRepaid(uint256 indexed vaultId, uint256 subVaultIndex, bytes32 rangeId, uint128 liquidity);
    event TokenSwap(uint256 indexed vaultId, bool zeroForOne, uint256 srcAmount, uint256 destAmount);
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
        if(_tradeOption.targetMarginAmount0 == -2 || _tradeOption.targetMarginAmount1 == -2) {
            (requiredAmount0, requiredAmount1) = updateFeeEntry(_vault, _subVaults, _ranges, _context);
        }

        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            DataType.PositionUpdate memory positionUpdate = _positionUpdates[i];

            // create new sub-vault if needed
            DataType.SubVault storage subVault = _vault.addSubVault(_subVaults, _context, positionUpdate.subVaultIndex);

            if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_TOKEN) {
                require(!_tradeOption.reduceOnly, "PU1");

                depositTokens(_vault, subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.add(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_TOKEN) {
                (uint256 amount0, uint256 amount1) = withdrawTokens(_vault, subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_TOKEN) {
                require(!_tradeOption.reduceOnly, "PU1");
                borrowTokens(_vault, subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_TOKEN) {
                (uint256 amount0, uint256 amount1) = repayTokens(_vault, subVault, _context, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_LPT) {
                require(!_tradeOption.reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = depositLPT(
                    _vault.vaultId,
                    subVault,
                    _context,
                    _ranges,
                    positionUpdate
                );

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_LPT) {
                (uint256 amount0, uint256 amount1) = withdrawLPT(_vault, subVault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_LPT) {
                require(!_tradeOption.reduceOnly, "PU1");
                (uint256 amount0, uint256 amount1) = borrowLPT(
                    _vault.vaultId,
                    subVault,
                    _context,
                    _ranges,
                    positionUpdate
                );

                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else if (positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_LPT) {
                (uint256 amount0, uint256 amount1) = repayLPT(
                    _vault.vaultId,
                    subVault,
                    _context,
                    _ranges,
                    positionUpdate
                );

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
                _tradeOption.isQuoteZero
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
            } else if (_tradeOption.targetMarginAmount0 == -2) {
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
            } else if (_tradeOption.targetMarginAmount1 == -2) {
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
                    subVault.collateralAmount0 == 0 &&
                    subVault.debtAmount0 == 0 &&
                    subVault.collateralAmount1 == 0 &&
                    subVault.debtAmount1 == 0 &&
                    subVault.balance0.collateralAmount == 0 &&
                    subVault.balance0.debtAmount == 0 &&
                    subVault.balance1.collateralAmount == 0 &&
                    subVault.balance1.debtAmount == 0 &&
                    subVault.lpts.length == 0
                ) {
                    _vault.removeSubVault(index);
                } else {
                    break;
                }
            }
        }
    }

    function swapAnyway(
        int256 requiredAmount0,
        int256 requiredAmount1,
        bool _isQuoteZero
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
                DataType.PositionUpdate(DataType.PositionUpdateType.SWAP_EXACT_IN, 0, zeroForOne, 0, 0, 0, amountIn, 0);
        } else if (!isExactIn && amountOut > 0) {
            return
                DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    0,
                    zeroForOne,
                    0,
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
        DataType.Vault storage _vault,
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal {
        _subVault.isCompound = _positionUpdate.zeroForOne;

        if (!_subVault.isCompound) {
            _subVault.collateralAmount0 = _subVault.collateralAmount0.add(_positionUpdate.param0);
            _subVault.collateralAmount1 = _subVault.collateralAmount1.add(_positionUpdate.param1);
        }

        _context.tokenState0.addCollateral(_subVault.balance0, _positionUpdate.param0);
        _context.tokenState1.addCollateral(_subVault.balance1, _positionUpdate.param1);

        emit TokenDeposited(
            _vault.vaultId,
            _positionUpdate.subVaultIndex,
            _positionUpdate.param0,
            _positionUpdate.param1
        );
    }

    function withdrawTokens(
        DataType.Vault storage _vault,
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 withdrawAmount0, uint256 withdrawAmount1) {
        if (!_subVault.isCompound) {
            _subVault.collateralAmount0 = _subVault.collateralAmount0.sub(_positionUpdate.param0);
            _subVault.collateralAmount1 = _subVault.collateralAmount1.sub(_positionUpdate.param1);
        }

        withdrawAmount0 = _context.tokenState0.removeCollateral(_subVault.balance0, _positionUpdate.param0);
        withdrawAmount1 = _context.tokenState1.removeCollateral(_subVault.balance1, _positionUpdate.param1);

        emit TokenWithdrawn(
            _vault.vaultId,
            _positionUpdate.subVaultIndex,
            _positionUpdate.param0,
            _positionUpdate.param1
        );
    }

    function borrowTokens(
        DataType.Vault storage _vault,
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal {
        _subVault.isCompound = _positionUpdate.zeroForOne;

        if (!_subVault.isCompound) {
            _subVault.debtAmount0 = _subVault.debtAmount0.add(_positionUpdate.param0);
            _subVault.debtAmount1 = _subVault.debtAmount1.add(_positionUpdate.param1);
        }

        _context.tokenState0.addDebt(_subVault.balance0, _positionUpdate.param0);
        _context.tokenState1.addDebt(_subVault.balance1, _positionUpdate.param1);

        emit TokenBorrowed(
            _vault.vaultId,
            _positionUpdate.subVaultIndex,
            _positionUpdate.param0,
            _positionUpdate.param1
        );
    }

    function repayTokens(
        DataType.Vault storage _vault,
        DataType.SubVault storage _subVault,
        DataType.Context storage _context,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        if (!_subVault.isCompound) {
            _subVault.debtAmount0 = _subVault.debtAmount0.sub(_positionUpdate.param0);
            _subVault.debtAmount1 = _subVault.debtAmount1.sub(_positionUpdate.param1);
        }

        requiredAmount0 = _context.tokenState0.removeDebt(_subVault.balance0, _positionUpdate.param0);
        requiredAmount1 = _context.tokenState1.removeDebt(_subVault.balance1, _positionUpdate.param1);

        emit TokenRepaid(_vault.vaultId, _positionUpdate.subVaultIndex, _positionUpdate.param0, _positionUpdate.param1);
    }

    function depositLPT(
        uint256 _vaultId,
        DataType.SubVault storage _subVault,
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

        _subVault.depositLPT(_ranges, rangeId, finalLiquidityAmount);

        emit LPTDeposited(_vaultId, _positionUpdate.subVaultIndex, rangeId, finalLiquidityAmount);
    }

    function withdrawLPT(
        DataType.Vault storage _vault,
        DataType.SubVault storage _subVault,
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

        _subVault.withdrawLPT(rangeId, _positionUpdate.liquidity);

        emit LPTWithdrawn(_vault.vaultId, _positionUpdate.subVaultIndex, rangeId, _positionUpdate.liquidity);
    }

    function borrowLPT(
        uint256 _vaultId,
        DataType.SubVault storage _subVault,
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

        _ranges[rangeId].borrowedLiquidity = _ranges[rangeId]
            .borrowedLiquidity
            .add(_positionUpdate.liquidity)
            .toUint128();

        _subVault.borrowLPT(_ranges, rangeId, _positionUpdate.liquidity);

        emit LPTBorrowed(_vaultId, _positionUpdate.subVaultIndex, rangeId, _positionUpdate.liquidity);
    }

    function repayLPT(
        uint256 _vaultId,
        DataType.SubVault storage _subVault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        {
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
        }

        _ranges[rangeId].borrowedLiquidity = _ranges[rangeId]
            .borrowedLiquidity
            .toUint256()
            .sub(_positionUpdate.liquidity)
            .toUint128();

        _subVault.repayLPT(rangeId, _positionUpdate.liquidity);

        emit LPTRepaid(_vaultId, _positionUpdate.subVaultIndex, rangeId, _positionUpdate.liquidity);
    }

    function swapExactIn(
        DataType.Vault storage _vault,
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
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        try ISwapRouter(_context.swapRouter).exactInputSingle(params) returns (uint256 amountOut) {
            emit TokenSwap(_vault.vaultId, _positionUpdate.zeroForOne, _positionUpdate.param0, amountOut);

            if (_positionUpdate.zeroForOne) {
                return (int256(_positionUpdate.param0), -int256(amountOut));
            } else {
                return (-int256(amountOut), int256(_positionUpdate.param0));
            }
        } catch (bytes memory reason) {
            if (keccak256(reason) == keccak256(abi.encodeWithSignature("Error(string)", "AS"))) {
                return (0, 0);
            } else {
                revert(string(reason));
            }
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
            fee: _context.feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _positionUpdate.param0,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        try ISwapRouter(_context.swapRouter).exactOutputSingle(params) returns (uint256 amountIn) {
            emit TokenSwap(_vault.vaultId, _positionUpdate.zeroForOne, amountIn, _positionUpdate.param0);

            if (_positionUpdate.zeroForOne) {
                return (int256(amountIn), -int256(_positionUpdate.param0));
            } else {
                return (-int256(_positionUpdate.param0), int256(amountIn));
            }
        } catch (bytes memory reason) {
            if (keccak256(reason) == keccak256(abi.encodeWithSignature("Error(string)", "AS"))) {
                return (0, 0);
            } else {
                revert(string(reason));
            }
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
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) external {
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault memory subVault = _subVaults[_vault.subVaults[i]];

            for (uint256 j = 0; j < subVault.lpts.length; j++) {
                collectTradeFeeFromUni(_context, _ranges[subVault.lpts[j].rangeId]);
            }
        }
    }

    function updateFeeEntry(
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context storage _context
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {
        (int256 fee0, int256 fee1) = VaultLib.getPremiumAndFee(_vault, _subVaults, _ranges, _context);

        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault storage subVault = _subVaults[_vault.subVaults[i]];

            for (uint256 j = 0; j < subVault.lpts.length; j++) {
                DataType.LPTState storage lpt = subVault.lpts[j];

                if (lpt.isCollateral) {
                    lpt.premiumGrowthLast = _ranges[lpt.rangeId].premiumGrowthForLender;
                } else {
                    lpt.premiumGrowthLast = _ranges[lpt.rangeId].premiumGrowthForBorrower;
                }

                lpt.fee0Last = _ranges[lpt.rangeId].fee0Growth;
                lpt.fee1Last = _ranges[lpt.rangeId].fee1Growth;
            }

            if (!subVault.isCompound) {
                (int256 collateralFee0, int256 collateralFee1, int256 debtFee0, int256 debtFee1) = VaultLib
                    .getTokenInterestOfSubVault(subVault, _context);

                _context.tokenState0.removeCollateral(subVault.balance0, collateralFee0.toUint256());
                _context.tokenState1.removeCollateral(subVault.balance1, collateralFee1.toUint256());
                _context.tokenState0.removeDebt(subVault.balance0, debtFee0.toUint256());
                _context.tokenState1.removeDebt(subVault.balance1, debtFee1.toUint256());
            }
        }

        requiredAmount0 = -fee0;
        requiredAmount1 = -fee1;
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
        _range.fee0Growth = _range.fee0Growth.add(PredyMath.mulDiv(a0, Constants.ONE, liquidityAmount));
        _range.fee1Growth = _range.fee1Growth.add(PredyMath.mulDiv(a1, Constants.ONE, liquidityAmount));
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
