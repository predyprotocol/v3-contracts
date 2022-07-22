//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./base/BaseStrategy.sol";
import "./interfaces/IPredyV3Pool.sol";
import "openzeppelin-contracts/token/ERC20/SafeERC20.sol";
import "v3-periphery/interfaces/ISwapRouter.sol";

contract BorrowLptStrategy is BaseStrategy {
    address public immutable token0;
    address public immutable token1;

    constructor(
        address _token0,
        address _token1,
        IPredyV3Pool _pool
    ) BaseStrategy(_pool) {
        token0 = _token0;
        token1 = _token1;
    }

    function isLiquidationRequired(
    ) external pure override returns (bool) {
        return false;
    }

    function getRequiredTokenAmounts(uint256 _boardId, bytes memory _data) external view returns (int256, int256) {
        (uint128 index, uint128 liquidity, bool isCall, , ) = abi.decode(
            _data,
            (uint128, uint128, bool, IPredyV3Pool.InstantDebtType, uint256)
        );

        (uint256 a0, uint256 a1) = pool.getTokenAmountsToBorrowLPT(_boardId, index, liquidity, isCall);

        (uint256 aa0, uint256 aa1) = pool.getTokenAmountsToDepositLPT(_boardId, index, liquidity);

        return (int256(a0) - int256(aa0), int256(a1) - int256(aa1));
    }

    function openPosition(
        uint256 _vaultId,
        uint256 _boardId,
        bytes memory _data
    ) external override returns (uint256, uint256) {
        (
            uint128 index,
            uint128 liquidity,
            bool isCall,
            IPredyV3Pool.InstantDebtType isInstant,
            uint256 amountInMaximum
        ) = abi.decode(_data, (uint128, uint128, bool, IPredyV3Pool.InstantDebtType, uint256));

        (uint256 a0, uint256 a1) = pool.getTokenAmountsToBorrowLPT(_boardId, index, liquidity, isCall);

        (uint256 aa0, uint256 aa1) = pool.borrowLPT(_vaultId, _boardId, index, liquidity, isInstant);

        pool.depositTokens(_vaultId, a0, a1);

        if (a0 > aa0) {
            // token0 is required
            // req1 -> req0
            uint256 requiredA1 = pool.swapExactOutput(token1, token0, a0 - aa0, amountInMaximum);
            return (0, requiredA1 - (aa1 - a1));
        } else if (a1 > aa1) {
            // req0 -> req1
            uint256 requiredA0 = pool.swapExactOutput(token0, token1, a1 - aa1, amountInMaximum);
            return (requiredA0 - (aa0 - a0), 0);
        }

        return (0, 0);
        // return (aa0 > a0 ? aa0 - a0 : 0, aa1 > a1 ? aa1 - a1 : 0);
    }
}
