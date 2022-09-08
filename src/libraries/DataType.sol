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

    struct SubVault {
        BaseToken.AccountState balance0;
        BaseToken.AccountState balance1;
        LPTState[] lpts;
    }

    struct Vault {
        uint256 vaultId;
        address owner;
        uint256 marginAmount0;
        uint256 marginAmount1;
        uint256[] subVaults;
    }

    struct Context {
        address token0;
        address token1;
        uint24 feeTier;
        address positionManager;
        address swapRouter;
        address uniswapPool;
        bool isMarginZero;
        uint256 nextSubVaultId;
        BaseToken.TokenState tokenState0;
        BaseToken.TokenState tokenState1;
    }

    // Parameters

    struct InitializationParams {
        uint24 feeTier;
        address token0;
        address token1;
        bool isMarginZero;
    }

    struct LPT {
        bool isCollateral;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
    }

    struct Position {
        uint256 subVaultIndex;
        uint256 collateral0;
        uint256 collateral1;
        uint256 debt0;
        uint256 debt1;
        LPT[] lpts;
    }

    enum PositionUpdateType {
        NOOP,
        DEPOSIT_TOKEN,
        WITHDRAW_TOKEN,
        BORROW_TOKEN,
        REPAY_TOKEN,
        DEPOSIT_LPT,
        WITHDRAW_LPT,
        BORROW_LPT,
        REPAY_LPT,
        SWAP_EXACT_IN,
        SWAP_EXACT_OUT,
        DEPOSIT_MARGIN,
        WITHDRAW_MARGIN
    }

    struct PositionUpdate {
        PositionUpdateType positionUpdateType;
        uint256 subVaultIndex;
        bool zeroForOne;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        uint256 param0;
        uint256 param1;
    }

    struct MetaData {
        uint256 subVaultIndex;
        bytes metadata;
    }

    struct TradeOption {
        bool reduceOnly;
        bool swapAnyway;
        bool quoterMode;
        bool isQuoteZero;
        int256 targetMarginAmount0;
        int256 targetMarginAmount1;
    }

    struct OpenPositionOption {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 bufferAmount0;
        uint256 bufferAmount1;
        MetaData metadata;
    }

    struct ClosePositionOption {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 swapRatio;
        MetaData metadata;
    }

    struct LiquidationOption {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 swapRatio;
        bool swapAnyway;
    }

    struct VaultStatusValue {
        uint256 collateralValue;
        uint256 debtValue;
        int256 premiumValue;
    }

    struct VaultStatusAmount {
        uint256 collateralAmount0;
        uint256 collateralAmount1;
        uint256 debtAmount0;
        uint256 debtAmount1;
        uint256 receivedTradeAmount0;
        uint256 receivedTradeAmount1;
        uint256 receivedPremium;
        uint256 paidpremium;
    }

    struct SubVaultStatus {
        VaultStatusValue values;
        VaultStatusAmount amount;
    }

    struct VaultStatus {
        uint256 marginValue;
        int256 minCollateral;
        SubVaultStatus[] subVaults;
    }
}
