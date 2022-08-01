//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../libraries/PositionVerifier.sol";

interface IPredyV3Pool {
    enum InstantDebtType {
        NONE,
        LONG,
        SHORT
    }

    function isMarginZero() external view returns (bool);

    function openPosition(
        uint256 _vaultId,
        uint256 _margin,
        bool _isLiquidationRequired,
        bytes memory _data,
        uint256 _buffer0,
        uint256 _buffer1
    ) external returns (uint256 vaultId);

    function closePositionsInVault(
        uint256 _vaultId,
        bool _zeroOrOne,
        uint256 _amount,
        uint256 _amountOutMinimum
    ) external;

    function swapExactInput(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMinimum
    ) external returns (uint256);

    function swapExactOutput(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountOut,
        uint256 _amountInMaximum
    ) external returns (uint256);

    function getTokenAmountsToDepositLPT(bytes32 _rangeId, uint128 _liquidity) external view returns (uint256, uint256);

    function getTokenAmountsToBorrowLPT(
        bytes32 _rangeId,
        uint128 _liquidity,
        uint160 _sqrtPrice
    ) external view returns (uint256, uint256);

    function getPosition(uint256 _vaultId) external view returns (PositionVerifier.Position memory position);

    function depositTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1,
        bool _withEnteringMarket
    ) external;

    function depositLPT(
        uint256 _vaultId,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity
    ) external returns (uint256, uint256);

    function borrowTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) external;

    function borrowLPT(
        uint256 _vaultId,
        int24 _lower,
        int24 _upper,
        uint128 _liquidity
    ) external returns (uint256, uint256);
}
