//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

library Constants {
    uint256 internal constant ONE = 1e18;

    // Reserve factor is 10%
    uint256 internal constant RESERVE_FACTOR = 10 * 1e16;

    // Reserve factor of LPToken is 5%
    uint256 internal constant LPT_RESERVE_FACTOR = 5 * 1e16;

    // Margin option
    uint8 internal constant MARGIN_STAY = 1;
    uint8 internal constant MARGIN_USE = 2;
    int256 internal constant FULL_WITHDRAWAL = type(int128).min;

    uint256 internal constant MAX_MARGIN_AMOUNT = 1e32;
    int256 internal constant MIN_MARGIN_AMOUNT = 1e6;

    uint256 internal constant MIN_SQRT_PRICE = 79228162514264337593;
    uint256 internal constant MAX_SQRT_PRICE = 79228162514264337593543950336000000000;

    uint256 internal constant MAX_NUM_OF_SUBVAULTS = 32;

    uint256 internal constant Q96 = 0x1000000000000000000000000;

    // 2%
    uint256 internal constant BASE_MIN_COLLATERAL_WITH_DEBT = 20000;
    // 0.00005
    uint256 internal constant MIN_COLLATERAL_WITH_DEBT_SLOPE = 50;
    // 3% scaled by 1e6
    uint256 internal constant BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE = 15000;
    // 0.000022
    uint256 internal constant LIQ_SLIPPAGE_SQRT_SLOPE = 22;
}
