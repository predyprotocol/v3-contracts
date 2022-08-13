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

    function emptyPosition() internal pure returns (DataType.Position memory) {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);
        return DataType.Position(0, 0, 0, 0, lpts);
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

        uint256 i;

        for (i = 0; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if (!lpt.isCollateral) {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.BORROW_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            }
        }

        if (_position.collateral0 > 0 || _position.collateral1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.DEPOSIT_TOKEN,
                false,
                0,
                0,
                0,
                _position.collateral0,
                _position.collateral1
            );
            i++;
        }

        if (_position.debt0 > 0 || _position.debt1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.BORROW_TOKEN,
                false,
                0,
                0,
                0,
                _position.debt0,
                _position.debt1
            );
            i++;
        }

        swapIndex = i;
        i++;

        for (; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if (lpt.isCollateral) {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.DEPOSIT_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            }
        }
    }

    function calculatePositionUpdatesToClose(DataType.Position memory _position)
        internal
        pure
        returns (DataType.PositionUpdate[] memory positionUpdates)
    {
        positionUpdates = new DataType.PositionUpdate[](calculateLengthOfPositionUpdates(_position) + 1);

        uint256 i;

        for (i = 1; i < _position.lpts.length; i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if (lpt.isCollateral) {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.WITHDRAW_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            } else {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.REPAY_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            }
        }

        if (_position.collateral0 > 0 || _position.collateral1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.WITHDRAW_TOKEN,
                false,
                0,
                0,
                0,
                _position.collateral0,
                _position.collateral1
            );
            i++;
        }

        if (_position.debt0 > 0 || _position.debt1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.REPAY_TOKEN,
                false,
                0,
                0,
                0,
                _position.debt0,
                _position.debt1
            );
        }
    }
}
