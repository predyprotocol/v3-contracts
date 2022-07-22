//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

interface IPredyV3Pool {
    enum InstantDebtType {
        NONE,
        LONG,
        SHORT
    }

    function openStrategy(
        address _strategyId,
        uint256 _boardId,
        uint256 _margin,
        bytes memory _data,
        uint256 _buffer0,
        uint256 _buffer1
    ) external returns (uint256 vaultId);

    function closePositionsInVault(
        uint256 _vaultId,
        uint256 _boardId,
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

    function getTokenAmountsToDepositLPT(
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity
    ) external view returns (uint256, uint256);

    function getTokenAmountsToBorrowLPT(
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity,
        bool _isCall
    ) external view returns (uint256, uint256);

    function depositTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) external;

    function depositLPT(
        uint256 _vaultId,
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity,
        uint256 _amount0,
        uint256 _amount1
    ) external returns (uint256, uint256);

    function borrowTokens(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) external;

    function borrowLPT(
        uint256 _vaultId,
        uint256 _boardId,
        uint128 _index,
        uint128 _liquidity,
        InstantDebtType _isInstant
    ) external returns (uint256, uint256);
}
