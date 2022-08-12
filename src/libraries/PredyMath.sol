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
}