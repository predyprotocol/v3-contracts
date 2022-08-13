//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "./PredyMath.sol";
import "./BaseToken.sol";

library DataType {
    // Storage Data Type
    struct PerpStatus {
        uint256 tokenId;
        int24 lowerTick;
        int24 upperTick;
        uint128 borrowedLiquidity;
        uint256 premiumGrowthForBorrower;
        uint256 premiumGrowthForLender;
        uint256 fee0Growth;
        uint256 fee1Growth;
        uint256 lastTouchedTimestamp;
    }

    struct LPTState {
        bool isCollateral;
        bytes32 rangeId;
        uint128 liquidityAmount;
        uint256 premiumGrowthLast;
        uint256 fee0Last;
        uint256 fee1Last;
    }

    struct Vault {
        address owner;
        bool isClosed;
        BaseToken.AccountState balance0;
        BaseToken.AccountState balance1;
        LPTState[] lpts;
    }

    struct Context {
        address token0;
        address token1;
        uint24 feeTier;
        address positionManager;
        address swapRouter;
        address uniswapPool;
        bool isMarginZero;
        BaseToken.TokenState tokenState0;
        BaseToken.TokenState tokenState1;
    }

    // Parameters
    struct LPT {
        bool isCollateral;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
    }

    struct Position {
        uint256 collateral0;
        uint256 collateral1;
        uint256 debt0;
        uint256 debt1;
        LPT[] lpts;
    }

    enum PositionUpdateType {
        DEPOSIT_TOKEN,
        WITHDRAW_TOKEN,
        BORROW_TOKEN,
        REPAY_TOKEN,
        DEPOSIT_LPT,
        WITHDRAW_LPT,
        BORROW_LPT,
        REPAY_LPT,
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
}
