//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./Controller.sol";
import "./libraries/LPTMath.sol";
import "./libraries/PositionCalculator.sol";

contract Reader {
    Controller public controller;
    bool public isMarginZero;

    constructor(Controller _controller) {
        controller = _controller;

        (isMarginZero, , ) = controller.getContext();
    }

    function getPrice() public view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(isMarginZero, controller.getSqrtPrice());
    }

    function getTWAP() external view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(isMarginZero, controller.getSqrtTWAP());
    }

    /**
     * @notice Calculates Min. Collateral of the vault.
     * @param _vaultId vault id
     * @param _position position you wanna add to the vault
     * @return minCollateral minimal amount of collateral to keep positions.
     */
    function calculateMinCollateral(uint256 _vaultId, DataType.Position memory _position)
        external
        returns (int256)
    {
        return
            PositionCalculator.calculateMinCollateral(
                PositionLib.concat(controller.getPosition(_vaultId), _position),
                controller.getSqrtPrice(),
                isMarginZero
            );
    }
}
