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
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToOpen(
            _position,
            _openPositionOptions.marginAmount,
            _tradeOption.isQuoteZero,
            getSqrtPrice()
        );

        vaultId = updatePosition(
            _vaultId,
            positionUpdates,
            _openPositionOptions.bufferAmount0,
            _openPositionOptions.bufferAmount1,
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
            _closePositionOptions.marginAmount,
            _closePositionOptions.swapRatio,
            getSqrtPrice()
        );

        vaultId = updatePosition(_vaultId, positionUpdates, 0, 0, _tradeOption, _closePositionOptions.metadata);

        checkPrice(_closePositionOptions.price, _closePositionOptions.slippageTorelance);
    }

    function liquidate(uint256 _vaultId, DataType.LiquidationOption memory _liquidationOption) external {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            getPosition(_vaultId),
            0,
            _liquidationOption.swapRatio,
            getSqrtPrice()
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
        bool _isQuoteZero,
        uint160 _sqrtPrice
    ) public pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        return PositionLib.getPositionUpdatesToOpen(_position, 0, _isQuoteZero, _sqrtPrice);
    }

    function getPositionUpdatesToClose(
        DataType.Position[] memory _positions,
        uint256 _swapRatio,
        uint160 _sqrtPrice
    ) public pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        return PositionLib.getPositionUpdatesToClose(_positions, 0, _swapRatio, _sqrtPrice);
    }
}
