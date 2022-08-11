//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../libraries/PositionCalculator.sol";

interface IProductVerifier {
    enum PositionUpdateType {
        DEPOSIT_TOKEN,
        BORROW_TOKEN,
        DEPOSIT_LPT,
        BORROW_LPT,
        SWAP_EXACT_IN,
        SWAP_EXACT_OUT
    }
    
    struct PositionUpdate {
        PositionUpdateType positionUpdateType;
        bool zeroForOne;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        uint256 param0;
        uint256 param1;
    }

    function openPosition(
        uint256 _vaultId,
        PositionUpdate[] memory _positionUpdates
    ) external returns (int256, int256);

    function calculateRequiredCollateral(
        PositionCalculator.Position memory position, 
        uint160 _sqrtPrice,
        bool isMarginZero
    )
        external
        pure
        returns (int256);

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
