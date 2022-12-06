//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "./PredyMath.sol";
import "./BaseToken.sol";

library DataType {
    // Storage Data Type
    struct PerpStatus {
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
        uint256 id;
        BaseToken.AccountState balance0;
        BaseToken.AccountState balance1;
        LPTState[] lpts;
    }

    struct Vault {
        uint256 vaultId;
        int256 marginAmount0;
        int256 marginAmount1;
        uint256[] subVaults;
    }

    struct Context {
        address token0;
        address token1;
        uint24 feeTier;
        address swapRouter;
        address uniswapPool;
        address chainlinkPriceFeed;
        bool isMarginZero;
        uint256 nextSubVaultId;
        BaseToken.TokenState tokenState0;
        BaseToken.TokenState tokenState1;
        uint256 accumulatedProtocolFee0;
        uint256 accumulatedProtocolFee1;
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
        uint256 asset0;
        uint256 asset1;
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
        SWAP_EXACT_OUT
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

    struct TradeOption {
        bool isLiquidationCall;
        bool swapAnyway;
        bool quoterMode;
        bool isQuoteZero;
        uint8 marginMode0;
        uint8 marginMode1;
        int256 deltaMarginAmount0;
        int256 deltaMarginAmount1;
        bytes metadata;
    }

    struct OpenPositionOption {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 swapRatio;
        uint256 deadline;
    }

    struct ClosePositionOption {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 swapRatio;
        uint256 closeRatio;
        uint256 deadline;
    }

    struct LiquidationOption {
        uint256 swapRatio;
        uint256 closeRatio;
    }

    struct SubVaultValue {
        uint256 assetValue;
        uint256 debtValue;
        int256 premiumValue;
    }

    struct SubVaultAmount {
        uint256 assetAmount0;
        uint256 assetAmount1;
        uint256 debtAmount0;
        uint256 debtAmount1;
    }

    struct SubVaultInterest {
        int256 assetFee0;
        int256 assetFee1;
        int256 debtFee0;
        int256 debtFee1;
    }

    struct SubVaultPremium {
        uint256 receivedTradeAmount0;
        uint256 receivedTradeAmount1;
        uint256 receivedPremium;
        uint256 paidPremium;
    }

    struct SubVaultStatus {
        SubVaultValue values;
        SubVaultAmount amount;
        SubVaultInterest interest;
        SubVaultPremium premium;
    }

    struct VaultStatus {
        int256 positionValue;
        int256 marginValue;
        int256 minCollateral;
        SubVaultStatus[] subVaults;
    }

    struct TokenAmounts {
        int256 amount0;
        int256 amount1;
    }

    struct PositionUpdateResult {
        TokenAmounts requiredAmounts;
        TokenAmounts feeAmounts;
        TokenAmounts positionAmounts;
        TokenAmounts swapAmounts;
    }
}
