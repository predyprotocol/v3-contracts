//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../libraries/DataType.sol";

interface IControllerHelper {
    function openPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    )
        external
        returns (
            uint256 vaultId,
            int256,
            int256,
            uint256
        );

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
        );

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
        );

    function closePosition(
        uint256 _vaultId,
        DataType.Position[] memory _positions,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    )
        external
        returns (
            int256,
            int256,
            uint256
        );

    function getSqrtPrice() external view returns (uint160 sqrtPriceX96);

    function getVaultValue(uint256 _vaultId) external view returns (int256);
}
