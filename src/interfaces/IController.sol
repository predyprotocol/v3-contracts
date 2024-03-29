//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../libraries/DataType.sol";

interface IController {
    function openPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    )
        external
        returns (
            uint256 vaultId,
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TokenAmounts memory swapAmounts
        );

    function updatePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory positionUpdates,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    )
        external
        returns (
            uint256 vaultId,
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TokenAmounts memory swapAmounts
        );

    function closeSubVault(
        uint256 _vaultId,
        uint256 _subVaultIndex,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) external returns (DataType.TokenAmounts memory requiredAmounts, DataType.TokenAmounts memory swapAmounts);

    function closePosition(
        uint256 _vaultId,
        DataType.Position[] memory _positions,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) external returns (DataType.TokenAmounts memory requiredAmounts, DataType.TokenAmounts memory swapAmounts);

    function getSqrtPrice() external view returns (uint160 sqrtPriceX96);

    function getVaultValue(uint256 _vaultId) external view returns (int256);

    function getVault(uint256 _vaultId) external view returns (DataType.Vault memory);
}
