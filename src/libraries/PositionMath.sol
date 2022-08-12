// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "./DataType.sol";

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

    function calculatePositionUpdatesToOpen(
        DataType.Position memory _position
    ) internal pure returns (DataType.PositionUpdate[] memory positionUpdates, uint256 swapIndex) {
        positionUpdates = new DataType.PositionUpdate[](calculateLengthOfPositionUpdates(_position) + 1);

        uint256 i;

        for(i = 0;i < _position.lpts.length;i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if(!lpt.isCollateral) {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.BORROW_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            }
        }

        if(_position.collateral0 > 0 || _position.collateral1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.DEPOSIT_TOKEN,
                false,
                0,
                0,
                0,
                _position.collateral0,
                _position.collateral1
            );
            i++;
        }
        
        if(_position.debt0 > 0 || _position.debt1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.BORROW_TOKEN,
                false,
                0,
                0,
                0,
                _position.debt0,
                _position.debt1
            );
            i++;
        }

        swapIndex = i;
        i++;

        for(;i < _position.lpts.length;i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if(lpt.isCollateral) {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.DEPOSIT_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            }
        }

    }

    function calculatePositionUpdatesToClose(
        DataType.Position memory _position
    ) internal pure returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](calculateLengthOfPositionUpdates(_position) + 1);

        uint256 i;

        for(i = 1;i < _position.lpts.length;i++) {
            DataType.LPT memory lpt = _position.lpts[i];
            if(lpt.isCollateral) {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.WITHDRAW_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            } else {
                positionUpdates[i] = DataType.PositionUpdate(
                    DataType.PositionUpdateType.REPAY_LPT,
                    false,
                    lpt.liquidity,
                    lpt.lowerTick,
                    lpt.upperTick,
                    0,
                    0
                );
            }
        }

        if(_position.collateral0 > 0 || _position.collateral1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.WITHDRAW_TOKEN,
                false,
                0,
                0,
                0,
                _position.collateral0,
                _position.collateral1
            );
            i++;
        }

        if(_position.debt0 > 0 || _position.debt1 > 0) {
            positionUpdates[i] = DataType.PositionUpdate(
                DataType.PositionUpdateType.REPAY_TOKEN,
                false,
                0,
                0,
                0,
                _position.debt0,
                _position.debt1
            );
        }
    }

}
