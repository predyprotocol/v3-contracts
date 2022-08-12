//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./libraries/DataType.sol";
import "./libraries/PositionCalculator.sol";

/*

contract ControllerHelper {
    function getPositionUpdatesToOpen(
        DataType.Position memory _position,
        uint160 _sqrtPrice,
        uint256 _limitPrice
    ) external returns (DataType.PositionUpdate[] memory positionUpdates,  uint256 _buffer0, uint256 _buffer1) {

        positionUpdates = new DataType.PositionUpdate[](1);

        (int256 requiredAmount0, int256 requiredAmount1) = PositionCalculator.getRequiredTokenAmountsToOpen(_position, _sqrtPrice);


        //


        //
        if(requiredAmount0 < 0) {
            uint256 amount0 = requiredAmount1 * limitPrice / 1e18;
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_OUT,
                false,
                0,
                0,
                0,
                requiredAmount1,
                requiredAmount1 * limitPrice / 1e18
            );

            _buffer0 = requiredAmount0 + amount0;
            _buffer1 = 0;
        }
    }

    function getPositionUpdatesToClose(
        DataType.Position memory _position,
        uint160 _sqrtPrice
    ) external returns (DataType.PositionUpdate[] memory positionUpdates,  uint256 _buffer0, uint256 _buffer1) {

        positionUpdates = new DataType.PositionUpdate[](1);

        (int256 requiredAmount0, int256 requiredAmount1) = PositionCalculator.getRequiredTokenAmountsToClose(_position, _sqrtPrice);


        //


        //
        if(requiredAmount0 < 0) {
            uint256 amount0 = requiredAmount1 * limitPrice / 1e18;
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_OUT,
                false,
                0,
                0,
                0,
                requiredAmount1,
                requiredAmount1 * limitPrice / 1e18
            );

            _buffer0 = requiredAmount0 + amount0
            _buffer1 = 0;
        }

    }
}
*/