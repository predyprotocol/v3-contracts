//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

interface IProductVerifier {
    function openPosition(
        uint256 _vaultId,
        bool _isLiquidationRequired,
        bytes memory _data
    ) external returns (uint256, uint256);

    function getLiquidityAndAmount(
        uint256 requestedAmount,
        int24 tick,
        int24 lower,
        int24 upper
    )
        external
        view
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}
