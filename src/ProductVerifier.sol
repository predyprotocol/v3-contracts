//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "./interfaces/IController.sol";
import "./interfaces/IProductVerifier.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/LPTMath.sol";
    /*

contract ProductVerifier is IProductVerifier, Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    IController public pool;

    event PositionUpdated(uint256 vaultId, uint256 amount0, uint256 amount1, bool zeroToOne);

    constructor(
        IController _pool
    ) {
        pool = _pool;
    }

    function openPosition(
        uint256 _vaultId,
        PositionUpdate[] memory _positionUpdates
    ) external override returns (int256, int256) {
        int256 requiredAmount0;
        int256 requiredAmount1;

        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            PositionUpdate memory positionUpdate = _positionUpdates[i];
            if(positionUpdate.positionUpdateType == PositionUpdateType.DEPOSIT_TOKEN) {
                pool.depositTokens(_vaultId, positionUpdate.param0, positionUpdate.param1, true);

                requiredAmount0 = requiredAmount0.add(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.add(int256(positionUpdate.param1));

            }else if(positionUpdate.positionUpdateType == PositionUpdateType.BORROW_TOKEN) {
                pool.borrowTokens(_vaultId, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param1));

            }else if(positionUpdate.positionUpdateType == PositionUpdateType.DEPOSIT_LPT) {
                (uint256 amount0InLPT, uint256 amount1InLPT) = pool.depositLPT(
                    _vaultId,
                    positionUpdate.lowerTick,
                    positionUpdate.upperTick,
                    positionUpdate.liquidity,
                    positionUpdate.param0,
                    positionUpdate.param1
                );

                requiredAmount0 = requiredAmount0.add(int256(amount0InLPT));
                requiredAmount1 = requiredAmount1.add(int256(amount1InLPT));
            }else if(positionUpdate.positionUpdateType == PositionUpdateType.BORROW_LPT) {
                (uint256 amount0InLPT, uint256 amount1InLPT) = pool.borrowLPT(
                    _vaultId,
                    positionUpdate.lowerTick,
                    positionUpdate.upperTick,
                    positionUpdate.liquidity,
                    positionUpdate.param0,
                    positionUpdate.param1
                );

                requiredAmount0 = requiredAmount0.sub(int256(amount0InLPT));
                requiredAmount1 = requiredAmount1.sub(int256(amount1InLPT));
            }else if(positionUpdate.positionUpdateType == PositionUpdateType.SWAP_EXACT_IN) {
                uint256 amountOut = pool.swapExactInput(positionUpdate.zeroForOne, positionUpdate.param0, positionUpdate.param1);

                if(positionUpdate.zeroForOne) {
                    requiredAmount0 = requiredAmount0.add(int256(positionUpdate.param0));
                    requiredAmount1 = requiredAmount1.sub(int256(amountOut));
                } else {
                    requiredAmount0 = requiredAmount0.sub(int256(amountOut));
                    requiredAmount1 = requiredAmount1.add(int256(positionUpdate.param0));
                }

            }else if(positionUpdate.positionUpdateType == PositionUpdateType.SWAP_EXACT_OUT) {
                uint256 amountIn = pool.swapExactOutput(positionUpdate.zeroForOne, positionUpdate.param0, positionUpdate.param1);

                if(positionUpdate.zeroForOne) {
                    requiredAmount0 = requiredAmount0.add(int256(amountIn));
                    requiredAmount1 = requiredAmount1.sub(int256(positionUpdate.param0));
                } else {
                    requiredAmount0 = requiredAmount0.sub(int256(positionUpdate.param0));
                    requiredAmount1 = requiredAmount1.add(int256(amountIn));
                }
            }
        }

        return (requiredAmount0, requiredAmount1);
    }

    function calculateRequiredCollateral(
        PositionCalculator.Position memory _position,     
        uint160 _sqrtPrice,
        bool _isMarginZero
    )
        external
        pure
        override
        returns (int256)
    {
        return PositionCalculator.calculateRequiredCollateral(_position, _sqrtPrice, _isMarginZero);
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
    */
