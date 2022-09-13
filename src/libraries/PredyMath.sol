// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

library PredyMath {
    using SafeMath for uint256;

    /**
     * @dev https://github.com/transmissions11/solmate/blob/main/src/utils/FixedPointMathLib.sol
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function subReward(uint256 a, uint256 b) internal pure returns (uint256, uint256) {
        if (a >= b) {
            return (a - b, b);
        } else {
            return (0, a);
        }
    }

    function addDelta(uint256 x, int256 y) internal pure returns (uint256 z) {
        if (y < 0) {
            require((z = x - uint256(-y)) < x, "LS");
        } else {
            require((z = x + uint256(y)) >= x, "LA");
        }
    }
}
