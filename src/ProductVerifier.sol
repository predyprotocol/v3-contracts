//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "openzeppelin-contracts/math/SafeMath.sol";
import "openzeppelin-contracts/math/SignedSafeMath.sol";
import "./interfaces/IPredyV3Pool.sol";
import "./libraries/PositionVerifier.sol";

contract ProductVerifier {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    address public immutable token0;
    address public immutable token1;
    IPredyV3Pool public pool;

    event LPTBorrowed(uint256 amount0, uint256 amount1, bool zeroToOne);

    constructor(
        address _token0,
        address _token1,
        IPredyV3Pool _pool
    ) {
        token0 = _token0;
        token1 = _token1;
        pool = _pool;
    }

    function getRequiredTokenAmounts(PositionVerifier.Position memory position, uint160 sqrtPrice) external view returns(int256 totalAmount0, int256 totalAmount1) {
        return PositionVerifier.getAmounts(position, sqrtPrice);
    }

    function openPosition(
        uint256 _vaultId,
        bool _isLiquidationRequired,
        bytes memory _data
    ) external returns (uint256, uint256) {
        (
            PositionVerifier.Position memory position,
            PositionVerifier.Proof[] memory proofs,
            uint256 amountInMaximum
        ) = abi.decode(_data, (PositionVerifier.Position, PositionVerifier.Proof[], uint256));

        int256 requiredAmount0 = int256(position.collateral0) - int256(position.debt0);
        int256 requiredAmount1 = int256(position.collateral1) - int256(position.debt1);

        if(!_isLiquidationRequired) {
            PositionVerifier.verifyPosition(position, proofs);
        }

        pool.depositTokens(_vaultId, position.collateral0, position.collateral1, false);
        pool.borrowTokens(_vaultId, position.debt0, position.debt1);

        for(uint256 i = 0;i < position.lpts.length;i++) {
            if(position.lpts[i].isCollateral) {
                (uint256 amount0InLPT, uint256 amount1InLPT) = pool.depositLPT(_vaultId, position.lpts[i].lowerTick, position.lpts[i].upperTick, position.lpts[i].liquidity);
                requiredAmount0 = requiredAmount0.add(int256(amount0InLPT));
                requiredAmount1 = requiredAmount1.add(int256(amount1InLPT));
            } else {
                (uint256 amount0InLPT, uint256 amount1InLPT) = pool.borrowLPT(_vaultId, position.lpts[i].lowerTick, position.lpts[i].upperTick, position.lpts[i].liquidity);
                requiredAmount0 = requiredAmount0.sub(int256(amount0InLPT));
                requiredAmount1 = requiredAmount1.sub(int256(amount1InLPT));
            }
        }

        if (requiredAmount0 > 0 && requiredAmount1 < 0) {
            uint256 requiredA1 = pool.swapExactOutput(token1, token0, uint256(requiredAmount0), amountInMaximum);

            emit LPTBorrowed(uint256(requiredAmount0), requiredA1, false);

            return (0, requiredA1.sub(uint256(-requiredAmount1)));
        }
        
        if (requiredAmount1 > 0 && requiredAmount0 < 0) {
            uint256 requiredA0 = pool.swapExactOutput(token0, token1, uint256(requiredAmount1), amountInMaximum);

            emit LPTBorrowed(requiredA0, uint256(requiredAmount1), true);

            return (requiredA0.sub(uint256(-requiredAmount0)), 0);
        }

        if (requiredAmount1 >= 0 && requiredAmount0 >= 0) {
            return (uint256(requiredAmount0), uint256(requiredAmount1));
        }

        // out of the money
        return (0, 0);
    }
}
