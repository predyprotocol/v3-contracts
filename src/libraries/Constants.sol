//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

library Constants {
    uint256 internal constant ONE = 1e18;
    uint256 internal constant RESERVE_FACTOR = 5 * 1e16;

    // margin option
    int256 internal constant MARGIN_STAY = -1;
    int256 internal constant MARGIN_USE = -2;

    uint256 internal constant MAX_MARGIN_AMOUNT = 1e32;
}
