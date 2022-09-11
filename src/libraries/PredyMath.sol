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
