//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "./interfaces/IPredyV3Pool.sol";
import "./interfaces/IProductVerifier.sol";
import "./libraries/PositionVerifier.sol";
import "./libraries/LPTMath.sol";

contract ProductVerifier is IProductVerifier, Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    IPredyV3Pool public pool;
    int256 public threshold;

    event PositionUpdated(uint256 vaultId, uint256 amount0, uint256 amount1, bool zeroToOne);

    constructor(
        IPredyV3Pool _pool
    ) {
        pool = _pool;
        threshold = 200;
    }

    function setThreshold(int256 _threshold)
        external
    {
        threshold = _threshold;
    }

    function getRequiredTokenAmounts(PositionVerifier.Position memory position, uint160 sqrtPrice)
        external
        pure
        returns (int256 totalAmount0, int256 totalAmount1)
    {
        return PositionVerifier.getAmounts(position, sqrtPrice);
    }

    function openPosition(
        uint256 _vaultId,
        bool _isLiquidationRequired,
        bytes memory _data
    ) external override returns (uint256, uint256) {
        (
            PositionVerifier.Position memory position,
            PositionVerifier.Proof[] memory proofs,
            uint256 amountInMaximum
        ) = abi.decode(_data, (PositionVerifier.Position, PositionVerifier.Proof[], uint256));

        int256 requiredAmount0 = int256(position.collateral0) - int256(position.debt0);
        int256 requiredAmount1 = int256(position.collateral1) - int256(position.debt1);

        // TODO: enter market
        pool.depositTokens(_vaultId, position.collateral0, position.collateral1, _isLiquidationRequired);
        pool.borrowTokens(_vaultId, position.debt0, position.debt1);

        for (uint256 i = 0; i < position.lpts.length; i++) {
            if (position.lpts[i].isCollateral) {
                (uint256 amount0InLPT, uint256 amount1InLPT) = pool.depositLPT(
                    _vaultId,
                    position.lpts[i].lowerTick,
                    position.lpts[i].upperTick,
                    position.lpts[i].liquidity
                );
                requiredAmount0 = requiredAmount0.add(int256(amount0InLPT));
                requiredAmount1 = requiredAmount1.add(int256(amount1InLPT));
            } else {
                (uint256 amount0InLPT, uint256 amount1InLPT) = pool.borrowLPT(
                    _vaultId,
                    position.lpts[i].lowerTick,
                    position.lpts[i].upperTick,
                    position.lpts[i].liquidity
                );
                requiredAmount0 = requiredAmount0.sub(int256(amount0InLPT));
                requiredAmount1 = requiredAmount1.sub(int256(amount1InLPT));
            }
        }

        if (!_isLiquidationRequired) {
            PositionVerifier.verifyPosition(pool.getPosition(_vaultId), proofs, true, threshold);
        }

        if (requiredAmount0 > 0 && requiredAmount1 < 0) {
            uint256 requiredA1 = pool.swapExactOutput(false, uint256(requiredAmount0), amountInMaximum);

            emit PositionUpdated(_vaultId, uint256(requiredAmount0), requiredA1, false);

            return (0, requiredA1.sub(uint256(-requiredAmount1)));
        }

        if (requiredAmount1 > 0 && requiredAmount0 < 0) {
            uint256 requiredA0 = pool.swapExactOutput(true, uint256(requiredAmount1), amountInMaximum);

            emit PositionUpdated(_vaultId, requiredA0, uint256(requiredAmount1), true);

            return (requiredA0.sub(uint256(-requiredAmount0)), 0);
        }

        if (requiredAmount1 >= 0 && requiredAmount0 >= 0) {
            return (uint256(requiredAmount0), uint256(requiredAmount1));
        }

        // out of the money
        return (0, 0);
    }

    function getLiquidityAndAmount(
        uint256 requestedAmount,
        int24 tick,
        int24 lower,
        int24 upper
    )
        external
        view
        override
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        return LPTMath.getLiquidityAndAmountToBorrow(pool.isMarginZero(), requestedAmount, tick, lower, upper);
    }
}
