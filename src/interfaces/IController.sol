//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../libraries/DataType.sol";

interface IController {
    function updatePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _buffer0,
        uint256 _buffer1
    ) external returns (uint256 vaultId);
}
