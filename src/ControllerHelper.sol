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

    /**
     * @notice Opens new position.
     * @param _vaultId The id of the vault. 0 means that it creates new vault.
     * @param _position Position to open
     * @param _tradeOption Trade parameters
     * @param _openPositionOptions Option parameters to open position
     */
    function openPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    )
        external
        returns (
            uint256 vaultId,
            int256 requiredAmount0,
            int256 requiredAmount1,
            uint256 averagePrice
        )
    {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToOpen(
            _position,
            _tradeOption.isQuoteZero,
            _openPositionOptions.feeTier,
            getSqrtPrice()
        );

        (vaultId, requiredAmount0, requiredAmount1, averagePrice) = updatePosition(
            _vaultId,
            positionUpdates,
            _tradeOption
        );

        _checkPrice(_openPositionOptions.lowerSqrtPrice, _openPositionOptions.upperSqrtPrice);
    }

    function updatePositionInVault(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory positionUpdates,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    )
        external
        returns (
            uint256 vaultId,
            int256 requiredAmount0,
            int256 requiredAmount1,
            uint256 averagePrice
        )
    {
        (vaultId, requiredAmount0, requiredAmount1, averagePrice) = updatePosition(
            _vaultId,
            positionUpdates,
            _tradeOption
        );

        _checkPrice(_openPositionOptions.lowerSqrtPrice, _openPositionOptions.upperSqrtPrice);
    }

    /**
     * @notice Closes all positions in a vault.
     * @param _vaultId The id of the vault
     * @param _tradeOption Trade parameters
     * @param _closePositionOptions Option parameters to close position
     */
    function closeVault(
        uint256 _vaultId,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    )
        external
        returns (
            int256,
            int256,
            uint256
        )
    {
        applyInterest();

        return closePosition(_vaultId, _getPosition(_vaultId), _tradeOption, _closePositionOptions);
    }

    /**
     * @notice Closes all positions in sub-vault.
     * @param _vaultId The id of the vault
     * @param _subVaultIndex The index of the sub-vault
     * @param _tradeOption Trade parameters
     * @param _closePositionOptions Option parameters to close position
     */
    function closeSubVault(
        uint256 _vaultId,
        uint256 _subVaultIndex,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    )
        external
        returns (
            int256,
            int256,
            uint256
        )
    {
        applyInterest();

        DataType.Position[] memory positions = new DataType.Position[](1);

        positions[0] = _getPositionOfSubVault(_vaultId, _subVaultIndex);

        return closePosition(_vaultId, positions, _tradeOption, _closePositionOptions);
    }

    /**
     * @notice Closes position partially.
     * @param _vaultId The id of the vault
     * @param _positions Positions to close
     * @param _tradeOption Trade parameters
     * @param _closePositionOptions Option parameters to close position
     */
    function closePosition(
        uint256 _vaultId,
        DataType.Position[] memory _positions,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    )
        public
        returns (
            int256 requiredAmount0,
            int256 requiredAmount1,
            uint256 averagePrice
        )
    {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            _positions,
            _tradeOption.isQuoteZero,
            _closePositionOptions.feeTier,
            _closePositionOptions.swapRatio,
            _closePositionOptions.closeRatio,
            getSqrtPrice()
        );

        (, requiredAmount0, requiredAmount1, averagePrice) = updatePosition(_vaultId, positionUpdates, _tradeOption);

        _checkPrice(_closePositionOptions.lowerSqrtPrice, _closePositionOptions.upperSqrtPrice);
    }

    /**
     * @notice Liquidates a vault.
     * @param _vaultId The id of the vault
     * @param _liquidationOption option parameters for liquidation call
     */
    function liquidate(uint256 _vaultId, DataType.LiquidationOption memory _liquidationOption) external {
        applyInterest();

        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            getPosition(_vaultId),
            context.isMarginZero,
            _liquidationOption.feeTier,
            _liquidationOption.swapRatio,
            _liquidationOption.closeRatio,
            getSqrtPrice()
        );

        liquidate(_vaultId, positionUpdates);
    }

    function _checkPrice(uint256 _lowerSqrtPrice, uint256 _upperSqrtPrice) internal view {
        uint256 sqrtPrice = getSqrtPrice();

        require(_lowerSqrtPrice <= sqrtPrice && sqrtPrice <= _upperSqrtPrice, "CH2");
    }
}
