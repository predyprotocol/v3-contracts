//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "./libraries/DataType.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/PositionLib.sol";
import "./Controller.sol";

contract ControllerHelper is Controller {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    constructor() {}

    /**
     * @notice Opens new position.
     */
    function openPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    ) external returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToOpen(
            _position,
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

        _checkPrice(_openPositionOptions.lowerSqrtPrice, _openPositionOptions.upperSqrtPrice);
    }

    /**
     * @notice Closes all positions in a vault.
     */
    function closeVault(
        uint256 _vaultId,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) external {
        applyInterest();

        closePosition(_vaultId, _getPosition(_vaultId), _tradeOption, _closePositionOptions);
    }

    /**
     * @notice Closes all positions in sub-vault.
     */
    function closeSubVault(
        uint256 _vaultId,
        uint256 _subVaultIndex,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) external {
        applyInterest();

        DataType.Position[] memory positions = new DataType.Position[](1);

        positions[0] = _getPositionOfSubVault(_vaultId, _subVaultIndex);

        closePosition(_vaultId, positions, _tradeOption, _closePositionOptions);
    }

    /**
     * @notice Closes position partially.
     */
    function closePosition(
        uint256 _vaultId,
        DataType.Position[] memory _positions,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) public {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            _positions,
            _tradeOption.isQuoteZero,
            _closePositionOptions.swapRatio,
            getSqrtPrice()
        );

        updatePosition(_vaultId, positionUpdates, 0, 0, _tradeOption, _closePositionOptions.metadata);

        _checkPrice(_closePositionOptions.lowerSqrtPrice, _closePositionOptions.upperSqrtPrice);
    }

    /**
     * @notice Liquidates a vault.
     */
    function liquidate(uint256 _vaultId, DataType.LiquidationOption memory _liquidationOption) external {
        applyInterest();

        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            getPosition(_vaultId),
            context.isMarginZero,
            _liquidationOption.swapRatio,
            getSqrtPrice()
        );

        liquidate(_vaultId, positionUpdates);

        _checkPrice(_liquidationOption.lowerSqrtPrice, _liquidationOption.upperSqrtPrice);
    }

    function _checkPrice(uint256 _lowerSqrtPrice, uint256 _upperSqrtPrice) internal view {
        uint256 sqrtPrice = getSqrtPrice();

        require(_lowerSqrtPrice <= sqrtPrice && sqrtPrice <= _upperSqrtPrice, "CH2");
    }
}
