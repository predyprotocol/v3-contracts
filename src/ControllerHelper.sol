//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "./libraries/DataType.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/PositionMath.sol";
import "./Controller.sol";

contract ControllerHelper {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    Controller controller;

    constructor(Controller _controller) {
        controller = _controller;
    }
    
    function getPositionUpdatesToOpen(
        DataType.Position memory _position,
        uint256 _limitPrice
    ) external view returns (DataType.PositionUpdate[] memory positionUpdates,  uint256 _buffer0, uint256 _buffer1) {

        uint256 swapIndex;

        (positionUpdates, swapIndex) = PositionMath.calculatePositionUpdatesToOpen(_position);

        (int256 requiredAmount0, int256 requiredAmount1) = PositionCalculator.getRequiredTokenAmountsToOpen(_position, controller.getSqrtPrice());
        
        if(controller.getIsMarginZero()) {
            uint256 maxAmount0 = calculateAmount0(uint256(requiredAmount1), _limitPrice);
            positionUpdates[swapIndex] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_OUT,
                true,
                0,
                0,
                0,
                uint256(requiredAmount1),
                maxAmount0
            );

            _buffer0 = uint256(int256(maxAmount0).add(requiredAmount0));
            _buffer1 = 0;
        } else {
            uint256 maxAmount1 = calculateAmount1(uint256(requiredAmount0), _limitPrice);
            positionUpdates[swapIndex] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_OUT,
                false,
                0,
                0,
                0,
                uint256(requiredAmount0),
                maxAmount1
            );

            _buffer0 = 0;
            _buffer1 = uint256(int256(maxAmount1).add(requiredAmount1));
        }
    }

    function getPositionUpdatesToClose(
        DataType.Position memory _position,
        uint256 _limitPrice
    ) external view returns (DataType.PositionUpdate[] memory positionUpdates,  uint256 _buffer0, uint256 _buffer1) {

        positionUpdates = PositionMath.calculatePositionUpdatesToClose(_position);

        (int256 requiredAmount0, int256 requiredAmount1) = PositionCalculator.getRequiredTokenAmountsToClose(_position, controller.getSqrtPrice());

        if(requiredAmount0 < 0) {
            uint256 minAmount1 = calculateAmount1(uint256(-requiredAmount0), _limitPrice);
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_IN,
                true,
                0,
                0,
                0,
                uint256(-requiredAmount0),
                minAmount1
            );

            _buffer0 = 0;
            _buffer1 = 0;
        } else if(requiredAmount1 < 0) {
            uint256 maxAmount0 = calculateAmount0(uint256(-requiredAmount1), _limitPrice);
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.SWAP_EXACT_IN,
                false,
                0,
                0,
                0,
                uint256(-requiredAmount1),
                maxAmount0
            );

            _buffer0 = 0;
            _buffer1 = 0;
        }
    }

    function calculateAmount0(uint256 _amount1, uint256 _limitPrice) internal view returns (uint256) {
        if(controller.getIsMarginZero()) {
            return _amount1 * _limitPrice / 1e12;
        } else {
            return _amount1 * 1e12 / _limitPrice;
        }
    }

    function calculateAmount1(uint256 _amount0, uint256 _limitPrice) internal view returns (uint256) {
        if(controller.getIsMarginZero()) {
            return _amount0 * 1e12 / _limitPrice;
        } else {
            return _amount0 * _limitPrice / 1e12;
        }
    }
}
