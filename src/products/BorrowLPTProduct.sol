//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "openzeppelin-contracts/math/SafeMath.sol";
import "../base/BaseProduct.sol";
import "../interfaces/IPredyV3Pool.sol";

contract BorrowLPTProduct is BaseProduct {
    using SafeMath for uint256;

    address public immutable token0;
    address public immutable token1;

    event LPTBorrowed(uint256 amount0, uint256 amount1, bool zeroToOne);

    constructor(
        address _token0,
        address _token1,
        IPredyV3Pool _pool
    ) BaseProduct(_pool) {
        token0 = _token0;
        token1 = _token1;
    }

    function isLiquidationRequired() external pure override returns (bool) {
        return false;
    }

    function getRequiredTokenAmounts(uint256 _boardId, uint128 _index, uint128 _liquidity, uint160 _sqrtPrice) external view returns (
        int256,
        int256
    ) {
        (uint256 targetAmount0, uint256 targetAmount1) = pool.getTokenAmountsToBorrowLPT(_boardId, _index, _liquidity, _sqrtPrice);
        (uint256 amount0InLPT, uint256 amount1InLPT) = pool.getTokenAmountsToDepositLPT(_boardId, _index, _liquidity);

        return (int256(targetAmount0) - int256(amount0InLPT), int256(targetAmount1) - int256(amount1InLPT));
    }

    function openPosition(
        uint256 _vaultId,
        uint256 _boardId,
        bytes memory _data
    ) external override returns (uint256, uint256) {
        (
            uint128 index,
            uint128 liquidity,
            uint160 sqrtPrice,
            IPredyV3Pool.InstantDebtType isInstant,
            uint256 amountInMaximum
        ) = abi.decode(_data, (uint128, uint128, uint160, IPredyV3Pool.InstantDebtType, uint256));

        (uint256 targetAmount0, uint256 targetAmount1) = pool.getTokenAmountsToBorrowLPT(_boardId, index, liquidity, sqrtPrice);

        (uint256 amount0InLPT, uint256 amount1InLPT) = pool.borrowLPT(_vaultId, _boardId, index, liquidity, isInstant);

        pool.depositTokens(_vaultId, targetAmount0, targetAmount1, false);

        if (targetAmount0 > amount0InLPT) {
            uint256 requiredA1 = pool.swapExactOutput(token1, token0, targetAmount0.sub(amount0InLPT), amountInMaximum);

            emit LPTBorrowed(targetAmount0.sub(amount0InLPT), requiredA1, false);

            return (0, requiredA1.sub(amount1InLPT.sub(targetAmount1)));
        }
        
        if (targetAmount1 > amount1InLPT) {
            uint256 requiredA0 = pool.swapExactOutput(token0, token1, targetAmount1.sub(amount1InLPT), amountInMaximum);

            emit LPTBorrowed(requiredA0, targetAmount1.sub(amount1InLPT), true);

            return (requiredA0.sub(amount0InLPT.sub(targetAmount0)), 0);
        }

        // out of the money
        return (0, 0);
    }
}
