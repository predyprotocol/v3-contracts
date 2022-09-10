// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

library PredyMath {
    using SafeMath for uint256;

    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        return a.mul(b).div(denominator);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function subReward(int256 a, uint256 b) internal pure returns (int256, uint256) {
        if (a >= int256(b)) {
            return (a - int256(b), b);
        } else {
            if (a > 0) {
                return (0, uint256(a));
            } else {
                return (0, 0);
            }
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
