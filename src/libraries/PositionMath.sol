// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";

/*
library PositionMath {
    using SafeMath for uint256;
    using SignedSafeMath for int256;


    function calculateLengthOfPositionUpdates(
        DataType.Position memory _position
    ) internal pure returns (uint256 length) {
        length = _position.lpts.length;

        if(_position.collateral0 > 0 || _position.collateral1 > 0) {
            length += 1;
        }

        if(_position.debt0 > 0 || _position.debt1 > 0) {
            length += 1;
        }
    }

    function calculatePositionUpdates(
        DataType.Position memory _position
    ) internal pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](calculateLengthOfPositionUpdates(_position));

        for(uint256 i = 0;i < _position.lpts.lengthi++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if(lpt.isCollateral) {
                positionUpdates[0] = DataType.PositionUpdate();
            } else {

            }
        }

        

    }
}
*/