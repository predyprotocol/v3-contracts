//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../base/BaseProduct.sol";

contract DepositLPTProduct is BaseProduct {
    constructor(IPredyV3Pool _pool) BaseProduct(_pool) {}

    function isLiquidationRequired() external pure override returns (bool) {
        return false;
    }

    function openPosition(
        uint256 _vaultId,
        uint256 _boardId,
        bytes memory _data
    ) external override returns (uint256, uint256) {
        (uint128 index, uint128 liquidity) = abi.decode(_data, (uint128, uint128));

        (uint256 a0, uint256 a1) = pool.getTokenAmountsToDepositLPT(_boardId, index, liquidity);

        pool.depositLPT(_vaultId, _boardId, index, liquidity, a0, a1);

        return (a0, a1);
    }
}
