// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";

library PositionLib {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    function getPositionUpdatesToOpen(
        DataType.Position memory _position,
        bool _isQuoteZero,
        uint160 _sqrtPrice
    ) external pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        uint256 swapIndex;

        (positionUpdates, swapIndex) = calculatePositionUpdatesToOpen(_position);

        (int256 requiredAmount0, int256 requiredAmount1) = getRequiredTokenAmountsToOpen(_position, _sqrtPrice);

        if (_isQuoteZero) {
            if (requiredAmount1 > 0) {
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    0,
                    true,
                    0,
                    0,
                    0,
                    uint256(requiredAmount1),
                    0
                );
            } else if (requiredAmount1 < 0) {
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_IN,
                    0,
                    false,
                    0,
                    0,
                    0,
                    uint256(-requiredAmount1),
                    0
                );
            }
        } else {
            if (requiredAmount0 > 0) {
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    0,
                    false,
                    0,
                    0,
                    0,
                    uint256(requiredAmount0),
                    0
                );
            } else if (requiredAmount0 < 0) {
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_IN,
                    0,
                    true,
                    0,
                    0,
                    0,
                    uint256(-requiredAmount0),
                    0
                );
            }
        }
    }

    function getPositionUpdatesToClose(
        DataType.Position[] memory _positions,
        uint256 _swapRatio,
        uint160 _sqrtPrice
    ) external pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        uint256 swapIndex;

        (positionUpdates, swapIndex) = calculatePositionUpdatesToClose(_positions);

        (int256 requiredAmount0, int256 requiredAmount1) = getRequiredTokenAmountsToClose(_positions, _sqrtPrice);

        if (requiredAmount0 < 0) {
            positionUpdates[swapIndex] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_IN,
                0,
                true,
                0,
                0,
                0,
                (uint256(-requiredAmount0) * _swapRatio) / 100,
                0
            );
        } else if (requiredAmount1 < 0) {
            positionUpdates[swapIndex] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_IN,
                0,
                false,
                0,
                0,
                0,
                (uint256(-requiredAmount1) * _swapRatio) / 100,
                0
            );
        }
    }

    function concat(DataType.Position[] memory _positions, DataType.Position memory _position)
        internal
        pure
        returns (DataType.Position memory)
    {
        DataType.Position[] memory positions = new DataType.Position[](_positions.length + 1);
        for (uint256 i = 0; i < _positions.length; i++) {
            positions[i] = _positions[i];
        }

        positions[_positions.length] = _position;

        return concat(positions);
    }

    function concat(DataType.Position[] memory _positions) internal pure returns (DataType.Position memory _position) {
        uint256 numLPTs;
        for (uint256 i = 0; i < _positions.length; i++) {
            numLPTs += _positions[i].lpts.length;
        }

        DataType.LPT[] memory lpts = new DataType.LPT[](numLPTs);

        _position = DataType.Position(0, 0, 0, 0, 0, lpts);

        uint256 k;

        for (uint256 i = 0; i < _positions.length; i++) {
            _position.collateral0 += _positions[i].collateral0;
            _position.collateral1 += _positions[i].collateral1;
            _position.debt0 += _positions[i].debt0;
            _position.debt1 += _positions[i].debt1;

            for (uint256 j = 0; j < _positions[i].lpts.length; j++) {
                _position.lpts[k] = _positions[i].lpts[j];
                k++;
            }
        }
    }

    function emptyPosition() internal pure returns (DataType.Position memory) {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        return DataType.Position(0, 0, 0, 0, 0, lpts);
    }

    /**
     * @notice Calculates required token amounts to open position.
     * @param _destPosition position to open
     * @param _sqrtPrice square root price to calculate
     */
    function getRequiredTokenAmountsToOpen(DataType.Position memory _destPosition, uint160 _sqrtPrice)
        internal
        pure
        returns (int256, int256)
    {
        return getRequiredTokenAmounts(emptyPosition(), _destPosition, _sqrtPrice);
    }

    /**
     * @notice Calculates required token amounts to close position.
     * @param _srcPosition position to close
     * @param _sqrtPrice square root price to calculate
     */
    function getRequiredTokenAmountsToClose(DataType.Position memory _srcPosition, uint160 _sqrtPrice)
        internal
        pure
        returns (int256, int256)
    {
        return getRequiredTokenAmounts(_srcPosition, emptyPosition(), _sqrtPrice);
    }

    function getRequiredTokenAmountsToClose(DataType.Position[] memory _srcPositions, uint160 _sqrtPrice)
        internal
        pure
        returns (int256 requiredAmount0, int256 requiredAmount1)
    {
        for (uint256 i = 0; i < _srcPositions.length; i++) {
            (int256 a0, int256 a1) = getRequiredTokenAmounts(_srcPositions[i], emptyPosition(), _sqrtPrice);
            requiredAmount0 += a0;
            requiredAmount1 += a1;
        }
    }

    /**
     * @notice Calculates required token amounts to update position.
     * @param _srcPosition position to update
     * @param _destPosition desired position
     * @param _sqrtPrice square root price to calculate
     */
    function getRequiredTokenAmounts(
        DataType.Position memory _srcPosition,
        DataType.Position memory _destPosition,
        uint160 _sqrtPrice
    ) internal pure returns (int256 requiredAmount0, int256 requiredAmount1) {
        requiredAmount0 = requiredAmount0.sub(int256(_srcPosition.collateral0));
        requiredAmount1 = requiredAmount1.sub(int256(_srcPosition.collateral1));
        requiredAmount0 = requiredAmount0.add(int256(_srcPosition.debt0));
        requiredAmount1 = requiredAmount1.add(int256(_srcPosition.debt1));

        requiredAmount0 = requiredAmount0.add(int256(_destPosition.collateral0));
        requiredAmount1 = requiredAmount1.add(int256(_destPosition.collateral1));
        requiredAmount0 = requiredAmount0.sub(int256(_destPosition.debt0));
        requiredAmount1 = requiredAmount1.sub(int256(_destPosition.debt1));

        for (uint256 i = 0; i < _srcPosition.lpts.length; i++) {
            DataType.LPT memory lpt = _srcPosition.lpts[i];

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                TickMath.getSqrtRatioAtTick(lpt.lowerTick),
                TickMath.getSqrtRatioAtTick(lpt.upperTick),
                lpt.liquidity
            );

            if (lpt.isCollateral) {
                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            } else {
                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            }
        }

        for (uint256 i = 0; i < _destPosition.lpts.length; i++) {
            DataType.LPT memory lpt = _destPosition.lpts[i];

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _sqrtPrice,
                TickMath.getSqrtRatioAtTick(lpt.lowerTick),
                TickMath.getSqrtRatioAtTick(lpt.upperTick),
                lpt.liquidity
            );

            if (lpt.isCollateral) {
                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            } else {
                requiredAmount0 = requiredAmount0.sub(int256(amount0));
                requiredAmount1 = requiredAmount1.sub(int256(amount1));
            }
        }
    }

    function calculateLengthOfPositionUpdates(DataType.Position[] memory _positions)
        internal
        pure
        returns (uint256 length)
    {
        for (uint256 i = 0; i < _positions.length; i++) {
            length += calculateLengthOfPositionUpdates(_positions[i]);
        }
    }

    function calculateLengthOfPositionUpdates(DataType.Position memory _position)
        internal
        pure
        returns (uint256 length)
    {
        length = _position.lpts.length;

        if (_position.collateral0 > 0 || _position.collateral1 > 0) {
            length += 1;
        }

        if (_position.debt0 > 0 || _position.debt1 > 0) {
            length += 1;
        }
    }

    function calculatePositionUpdatesToOpen(DataType.Position memory _position)
        internal
        pure
        returns (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex)
    {
        positionUpdates = new DataType.PositionUpdate[](calculateLengthOfPositionUpdates(_position) + 1);

        uint256 index = 0;

        for (uint256 i = 0; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if (!lpt.isCollateral) {
                positionUpdates[index] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.BORROW_LPT,
                    _position.subVaultIndex,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
                index++;
            }
        }

        if (_position.collateral0 > 0 || _position.collateral1 > 0) {
            positionUpdates[index] = DataType.PositionUpdate(
                DataType.PositionUpdateType.DEPOSIT_TOKEN,
                _position.subVaultIndex,
                false,
                0,
                0,
                0,
                _position.collateral0,
                _position.collateral1
            );
            index++;
        }

        if (_position.debt0 > 0 || _position.debt1 > 0) {
            positionUpdates[index] = DataType.PositionUpdate(
                DataType.PositionUpdateType.BORROW_TOKEN,
                _position.subVaultIndex,
                false,
                0,
                0,
                0,
                _position.debt0,
                _position.debt1
            );
            index++;
        }

        swapIndex = index;
        index++;

        for (uint256 i; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if (lpt.isCollateral) {
                positionUpdates[index] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.DEPOSIT_LPT,
                    _position.subVaultIndex,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
                index++;
            }
        }
    }

    function calculatePositionUpdatesToClose(DataType.Position[] memory _positions)
        internal
        pure
        returns (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex)
    {
        positionUpdates = new DataType.PositionUpdate[](calculateLengthOfPositionUpdates(_positions) + 1);

        uint256 index = 0;

        for (uint256 i = 0; i < _positions.length; i++) {
            for (uint256 j = 0; j < _positions[i].lpts.length; j++) {
                DataType.LPT memory lpt = _positions[i].lpts[j];
                if (lpt.isCollateral) {
                    positionUpdates[index] = DataType.PositionUpdate(
                        DataType.PositionUpdateType.WITHDRAW_LPT,
                        _positions[i].subVaultIndex,
                        false,
                        lpt.liquidity,
                        lpt.lowerTick,
                        lpt.upperTick,
                        0,
                        0
                    );
                    index++;
                }
            }
        }

        swapIndex = index;
        index++;

        for (uint256 i = 0; i < _positions.length; i++) {
            for (uint256 j = 0; j < _positions[i].lpts.length; j++) {
                DataType.LPT memory lpt = _positions[i].lpts[j];
                if (!lpt.isCollateral) {
                    positionUpdates[index] = DataType.PositionUpdate(
                        DataType.PositionUpdateType.REPAY_LPT,
                        _positions[i].subVaultIndex,
                        false,
                        lpt.liquidity,
                        lpt.lowerTick,
                        lpt.upperTick,
                        0,
                        0
                    );
                    index++;
                }
            }
        }

        for (uint256 i = 0; i < _positions.length; i++) {
            if (_positions[i].collateral0 > 0 || _positions[i].collateral1 > 0) {
                positionUpdates[index] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.WITHDRAW_TOKEN,
                    _positions[i].subVaultIndex,
                    false,
                    0,
                    0,
                    0,
                    _positions[i].collateral0,
                    _positions[i].collateral1
                );
                index++;
            }
        }

        for (uint256 i = 0; i < _positions.length; i++) {
            if (_positions[i].debt0 > 0 || _positions[i].debt1 > 0) {
                positionUpdates[index] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.REPAY_TOKEN,
                    _positions[i].subVaultIndex,
                    false,
                    0,
                    0,
                    0,
                    _positions[i].debt0,
                    _positions[i].debt1
                );
            }
        }
    }
}
