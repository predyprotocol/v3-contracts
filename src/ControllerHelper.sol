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

    constructor() {}

    function openPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    ) external returns (uint256 vaultId) {
        (DataType.PositionUpdate[] memory positionUpdates, uint256 buffer0, uint256 buffer1) = PositionLib
            .getPositionUpdatesToOpen(
                _position,
                _openPositionOptions.price,
                _openPositionOptions.slippageTorelance,
                _tradeOption.isQuoteZero,
                getSqrtPrice(),
                context.isMarginZero
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
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            getPosition(_vaultId),
            _closePositionOptions.price,
            _closePositionOptions.slippageTorelance,
            _closePositionOptions.swapRatio,
            getSqrtPrice(),
            context.isMarginZero
        );

        vaultId = updatePosition(_vaultId, positionUpdates, 0, 0, _tradeOption, _closePositionOptions.metadata);

        checkPrice(_closePositionOptions.price, _closePositionOptions.slippageTorelance);
    }

    function liquidate(uint256 _vaultId, DataType.LiquidationOption memory _liquidationOption) external {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            getPosition(_vaultId),
            _liquidationOption.price,
            _liquidationOption.slippageTorelance,
            _liquidationOption.swapRatio,
            getSqrtPrice(),
            context.isMarginZero
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

    function calculateRequiredCollateral(DataType.Position memory _position) external view returns (int256) {
        return PositionCalculator.calculateRequiredCollateral(_position, getTWAPSqrtPrice(), context.isMarginZero);
    }

    function getPositionUpdatesToOpen(
        DataType.Position memory _position,
        uint256 _price,
        uint256 _slippageTorelance,
        bool _isQuoteZero,
        uint160 _sqrtPrice,
        bool _isMarginZero
    )
        public
        pure
        returns (
            DataType.PositionUpdate[] memory positionUpdates,
            uint256 _buffer0,
            uint256 _buffer1
        )
    {
        return
            PositionLib.getPositionUpdatesToOpen(
                _position,
                _price,
                _slippageTorelance,
                _isQuoteZero,
                _sqrtPrice,
                _isMarginZero
            );
    }

    function getPositionUpdatesToClose(
        DataType.Position memory _position,
        uint256 _price,
        uint256 _slippageTorelance,
        uint256 _swapRatio,
        uint160 _sqrtPrice,
        bool _isMarginZero
    ) public pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        return
            PositionLib.getPositionUpdatesToClose(
                _position,
                _price,
                _slippageTorelance,
                _swapRatio,
                _sqrtPrice,
                _isMarginZero
            );
    }
}
