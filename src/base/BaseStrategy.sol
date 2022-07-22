//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../interfaces/IPredyV3Pool.sol";

contract BaseStrategy {
    IPredyV3Pool public pool;

    constructor(IPredyV3Pool _pool) {
        pool = _pool;
    }

    function isLiquidationRequired(
    ) external pure virtual returns (bool) {}


    function openPosition(
        uint256 _vaultId,
        uint256 _boardId,
        bytes memory _data
    ) external virtual returns (uint256, uint256) {}
}
