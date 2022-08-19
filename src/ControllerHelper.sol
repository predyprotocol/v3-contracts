//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "./libraries/DataType.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/PositionLib.sol";
import "./Controller.sol";

contract ControllerHelper is Controller {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    constructor(
        DataType.InitializationParams memory _initializationParams,
        address _positionManager,
        address _factory,
        address _swapRouter
    ) Controller(_initializationParams, _positionManager, _factory, _swapRouter) {}

    function openPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        uint256 _limitPrice,
        uint256 _bufferRatio,
        DataType.TradeOption memory _tradeOption
    ) external returns (uint256 vaultId) {
        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = getPositionUpdatesToOpen(
            _position,
            _limitPrice
        );

        return
            updatePosition(
                _vaultId,
                positionUpdates,
                (buffer0 * _bufferRatio) / 100,
                (buffer1 * _bufferRatio) / 100,
                _tradeOption
            );
    }

    function closePosition(
        uint256 _vaultId,
        uint256 _limitPrice,
        uint256 _swapRatio,
        DataType.TradeOption memory _tradeOption
    ) external returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = getPositionUpdatesToClose(
            getPosition(_vaultId),
            _limitPrice,
            _swapRatio
        );

        return updatePosition(_vaultId, positionUpdates, 0, 0, _tradeOption);
    }

    function liquidate(
        uint256 _vaultId,
        uint256 _limitPrice,
        uint256 _swapRatio
    ) external {
        DataType.PositionUpdate[] memory positionUpdates = getPositionUpdatesToClose(
            getPosition(_vaultId),
            _limitPrice,
            _swapRatio
        );

        liquidate(_vaultId, positionUpdates);
    }

    function getPositionUpdatesToOpen(DataType.Position memory _position, uint256 _limitPrice)
        public
        view
        returns (
            DataType.PositionUpdate[] memory positionUpdates,
            uint256 _buffer0,
            uint256 _buffer1
        )
    {
        uint256 swapIndex;

        (positionUpdates, swapIndex) = PositionLib.calculatePositionUpdatesToOpen(_position);

        (int256 requiredAmount0, int256 requiredAmount1) = PositionLib.getRequiredTokenAmountsToOpen(
            _position,
            getSqrtPrice()
        );

        if (context.isMarginZero) {
            uint256 maxAmount0 = calculateAmount0(uint256(requiredAmount1), _limitPrice);
            if (requiredAmount1 > 0) {
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    true,
                    0,
                    0,
                    0,
                    uint256(requiredAmount1),
                    maxAmount0
                );
            }

            _buffer0 = uint256(int256(maxAmount0).add(requiredAmount0));
            _buffer1 = 0;
        } else {
            uint256 maxAmount1 = calculateAmount1(uint256(requiredAmount0), _limitPrice);
            if (requiredAmount0 > 0) {
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    false,
                    0,
                    0,
                    0,
                    uint256(requiredAmount0),
                    maxAmount1
                );
            }

            _buffer0 = 0;
            _buffer1 = uint256(int256(maxAmount1).add(requiredAmount1));
        }
    }

    function getPositionUpdatesToClose(
        DataType.Position memory _position,
        uint256 _limitPrice,
        uint256 _swapRatio
    ) public view returns (DataType.PositionUpdate[] memory positionUpdates) {
        uint256 swapIndex;

        (positionUpdates, swapIndex) = PositionLib.calculatePositionUpdatesToClose(_position);

        (int256 requiredAmount0, int256 requiredAmount1) = PositionLib.getRequiredTokenAmountsToClose(
            _position,
            getSqrtPrice()
        );

        if (requiredAmount0 < 0) {
            uint256 minAmount1 = calculateAmount1(uint256(-requiredAmount0), _limitPrice);
            positionUpdates[swapIndex] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_IN,
                true,
                0,
                0,
                0,
                (uint256(-requiredAmount0) * _swapRatio) / 100,
                (minAmount1 * _swapRatio) / 100
            );
        } else if (requiredAmount1 < 0) {
            uint256 maxAmount0 = calculateAmount0(uint256(-requiredAmount1), _limitPrice);
            positionUpdates[swapIndex] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_IN,
                false,
                0,
                0,
                0,
                (uint256(-requiredAmount1) * _swapRatio) / 100,
                (maxAmount0 * _swapRatio) / 100
            );
        }
    }

    function calculateRequiredCollateral(DataType.Position memory _position) external view returns (int256) {
        return PositionCalculator.calculateRequiredCollateral(_position, getTWAPSqrtPrice(), context.isMarginZero);
    }

    function calculateAmount0(uint256 _amount1, uint256 _limitPrice) internal view returns (uint256) {
        if (context.isMarginZero) {
            return (_amount1 * _limitPrice) / 1e12;
        } else {
            return (_amount1 * 1e12) / _limitPrice;
        }
    }

    function calculateAmount1(uint256 _amount0, uint256 _limitPrice) internal view returns (uint256) {
        if (context.isMarginZero) {
            return (_amount0 * 1e12) / _limitPrice;
        } else {
            return (_amount0 * _limitPrice) / 1e12;
        }
    }
}
