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
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    ) external returns (uint256 vaultId) {
        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = getPositionUpdatesToOpen(
            _position,
            _openPositionOptions.price,
            _openPositionOptions.slippageTorelance,
            _tradeOption.isQuoteZero
        );

        buffer0 = (buffer0 * _openPositionOptions.bufferRatio) / 100;
        buffer1 = (buffer1 * _openPositionOptions.bufferRatio) / 100;

        require(
            _openPositionOptions.maximumBufferAmount0 == 0 || _openPositionOptions.maximumBufferAmount0 >= buffer0,
            "CH0"
        );
        require(
            _openPositionOptions.maximumBufferAmount1 == 0 || _openPositionOptions.maximumBufferAmount1 >= buffer1,
            "CH1"
        );

        vaultId = updatePosition(
            _vaultId,
            positionUpdates,
            buffer0,
            buffer1,
            _tradeOption,
            _openPositionOptions.metadata
        );

        checkPrice(_openPositionOptions.price, _openPositionOptions.slippageTorelance);
    }

    function closePosition(
        uint256 _vaultId,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) external returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = getPositionUpdatesToClose(
            getPosition(_vaultId),
            _closePositionOptions.price,
            _closePositionOptions.slippageTorelance,
            _closePositionOptions.swapRatio
        );

        vaultId = updatePosition(_vaultId, positionUpdates, 0, 0, _tradeOption, _closePositionOptions.metadata);

        checkPrice(_closePositionOptions.price, _closePositionOptions.slippageTorelance);
    }

    function liquidate(uint256 _vaultId, DataType.LiquidationOption memory _liquidationOption) external {
        DataType.PositionUpdate[] memory positionUpdates = getPositionUpdatesToClose(
            getPosition(_vaultId),
            _liquidationOption.price,
            _liquidationOption.slippageTorelance,
            _liquidationOption.swapRatio
        );

        liquidate(_vaultId, positionUpdates, _liquidationOption.swapAnyway);

        checkPrice(_liquidationOption.price, _liquidationOption.slippageTorelance);
    }

    function checkPrice(uint256 _price, uint256 _slippageTorelance) internal view {
        uint256 price = getPrice();

        require(
            (_price * (1e4 - _slippageTorelance)) / 1e4 <= price &&
                price <= (_price * (1e4 + _slippageTorelance)) / 1e4,
            "CH2"
        );
    }

    function getPositionUpdatesToOpen(
        DataType.Position memory _position,
        uint256 _price,
        uint256 _slippageTorelance,
        bool _isQuoteZero
    )
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

        if (_isQuoteZero) {
            if (requiredAmount1 > 0) {
                uint256 maxAmount0 = calculateMaxAmount0(uint256(requiredAmount1), _price, _slippageTorelance);
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_OUT,
                    true,
                    0,
                    0,
                    0,
                    uint256(requiredAmount1),
                    maxAmount0
                );

                _buffer0 = uint256(int256(maxAmount0).add(requiredAmount0));
                _buffer1 = 0;
            } else if (requiredAmount1 < 0) {
                uint256 minAmount0 = calculateMinAmount0(uint256(-requiredAmount1), _price, _slippageTorelance);
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_IN,
                    false,
                    0,
                    0,
                    0,
                    uint256(-requiredAmount1),
                    minAmount0
                );
                if (requiredAmount0 > int256(minAmount0)) {
                    _buffer0 = uint256(requiredAmount0.sub(int256(minAmount0)));
                }
                _buffer1 = 0;
            } else {
                _buffer0 = uint256(requiredAmount0);
                _buffer1 = 0;
            }
        } else {
            uint256 maxAmount1 = calculateMaxAmount1(uint256(requiredAmount0), _price, _slippageTorelance);
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
                _buffer0 = 0;
                _buffer1 = uint256(int256(maxAmount1).add(requiredAmount1));
            } else if (requiredAmount0 < 0) {
                uint256 minAmount1 = calculateMinAmount1(uint256(-requiredAmount0), _price, _slippageTorelance);
                positionUpdates[swapIndex] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.SWAP_EXACT_IN,
                    true,
                    0,
                    0,
                    0,
                    uint256(-requiredAmount0),
                    minAmount1
                );
                _buffer0 = 0;
                if (requiredAmount1 > int256(minAmount1)) {
                    _buffer1 = uint256(requiredAmount1.sub(int256(minAmount1)));
                }
            } else {
                _buffer0 = 0;
                _buffer1 = uint256(requiredAmount1);
            }
        }
    }

    function getPositionUpdatesToClose(
        DataType.Position memory _position,
        uint256 _price,
        uint256 _slippageTorelance,
        uint256 _swapRatio
    ) public view returns (DataType.PositionUpdate[] memory positionUpdates) {
        uint256 swapIndex;

        (positionUpdates, swapIndex) = PositionLib.calculatePositionUpdatesToClose(_position);

        (int256 requiredAmount0, int256 requiredAmount1) = PositionLib.getRequiredTokenAmountsToClose(
            _position,
            getSqrtPrice()
        );

        if (requiredAmount0 < 0) {
            uint256 minAmount1 = calculateMinAmount1(uint256(-requiredAmount0), _price, _slippageTorelance);
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
            uint256 minAmount0 = calculateMinAmount0(uint256(-requiredAmount1), _price, _slippageTorelance);
            positionUpdates[swapIndex] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_IN,
                false,
                0,
                0,
                0,
                (uint256(-requiredAmount1) * _swapRatio) / 100,
                (minAmount0 * _swapRatio) / 100
            );
        }
    }

    function calculateRequiredCollateral(DataType.Position memory _position) external view returns (int256) {
        return PositionCalculator.calculateRequiredCollateral(_position, getTWAPSqrtPrice(), context.isMarginZero);
    }

    function calculateMaxAmount0(
        uint256 _amount1,
        uint256 _price,
        uint256 _slippageTorelance
    ) internal view returns (uint256) {
        if (context.isMarginZero) {
            uint256 limitPrice = (_price * (1e4 + _slippageTorelance)) / 1e4;
            return (_amount1 * limitPrice) / 1e18;
        } else {
            uint256 limitPrice = (_price * (1e4 - _slippageTorelance)) / 1e4;
            return (_amount1 * 1e18) / limitPrice;
        }
    }

    function calculateMinAmount0(
        uint256 _amount1,
        uint256 _price,
        uint256 _slippageTorelance
    ) internal view returns (uint256) {
        if (context.isMarginZero) {
            uint256 limitPrice = (_price * (1e4 - _slippageTorelance)) / 1e4;
            return (_amount1 * limitPrice) / 1e18;
        } else {
            uint256 limitPrice = (_price * (1e4 + _slippageTorelance)) / 1e4;
            return (_amount1 * 1e18) / limitPrice;
        }
    }

    function calculateMaxAmount1(
        uint256 _amount0,
        uint256 _price,
        uint256 _slippageTorelance
    ) internal view returns (uint256) {
        if (context.isMarginZero) {
            uint256 limitPrice = (_price * (1e4 - _slippageTorelance)) / 1e4;

            return (_amount0 * 1e18) / limitPrice;
        } else {
            uint256 limitPrice = (_price * (1e4 + _slippageTorelance)) / 1e4;
            return (_amount0 * limitPrice) / 1e18;
        }
    }

    function calculateMinAmount1(
        uint256 _amount0,
        uint256 _price,
        uint256 _slippageTorelance
    ) internal view returns (uint256) {
        if (context.isMarginZero) {
            uint256 limitPrice = (_price * (1e4 + _slippageTorelance)) / 1e4;
            return (_amount0 * 1e18) / limitPrice;
        } else {
            uint256 limitPrice = (_price * (1e4 - _slippageTorelance)) / 1e4;
            return (_amount0 * limitPrice) / 1e18;
        }
    }
}
