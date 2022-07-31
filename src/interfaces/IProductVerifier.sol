//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

interface IProductVerifier {
    function openPosition(
        uint256 _vaultId,
        bool _isLiquidationRequired,
        bytes memory _data
    ) external returns (uint256, uint256);
}

