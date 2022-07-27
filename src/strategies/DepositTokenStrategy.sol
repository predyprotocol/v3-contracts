//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../base/BaseStrategy.sol";

contract LevLPStrategy is BaseStrategy {
    constructor(IPredyV3Pool _pool) BaseStrategy(_pool) {}

    function isLiquidationRequired(
    ) external pure override returns (bool) {
        return false;
    }
    
    function openPosition(
        uint256 _vaultId,
        uint256 _boardId,
        bytes memory _data
    ) external override returns (uint256, uint256) {
        (uint256 amount0, uint256 amount1) = abi.decode(_data, (uint256, uint256));

        pool.depositTokens(_vaultId, amount0, amount1);

        return (amount0, amount1);
    }
}
