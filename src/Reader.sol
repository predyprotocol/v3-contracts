//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./Controller.sol";
import "./libraries/BaseToken.sol";
import "./libraries/LPTMath.sol";
import "./libraries/PositionCalculator.sol";

contract Reader {
    Controller public controller;
    bool public isMarginZero;
    address public uniswapPool;
    address public positionManager;

    constructor(Controller _controller) {
        controller = _controller;

        (isMarginZero, , uniswapPool, positionManager, , ) = controller.getContext();
    }

    function getPrice() public view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(isMarginZero, controller.getSqrtPrice());
    }

    function getTWAP() external view returns (uint256) {
        uint160 sqrtPrice = LiquidationLogic.getSqrtTWAP(uniswapPool);

        return LPTMath.decodeSqrtPriceX96(isMarginZero, sqrtPrice);
    }

    function getAssetStatus()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (BaseToken.TokenState memory tokenState0, BaseToken.TokenState memory tokenState1) = controller.getTokenState();

        return (
            BaseToken.getTotalCollateralValue(tokenState0),
            BaseToken.getTotalDebtValue(tokenState0),
            BaseToken.getUtilizationRatio(tokenState0),
            BaseToken.getTotalCollateralValue(tokenState1),
            BaseToken.getTotalDebtValue(tokenState1),
            BaseToken.getUtilizationRatio(tokenState1)
        );
    }

    function getLPTStatus(bytes32 _rangeId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        DataType.PerpStatus memory range = controller.getRange(_rangeId);

        return LPTStateLib.getPerpStatus(positionManager, range);
    }

    /**
     * @notice Calculates Min. Deposit of the vault.
     * @param _vaultId vault id
     * @param _position position you wanna add to the vault
     * @return minDeposit minimal amount of deposit to keep positions.
     */
    function calculateMinDeposit(uint256 _vaultId, DataType.Position memory _position) external view returns (int256) {
        return
            PositionCalculator.calculateMinDeposit(
                PositionCalculator.add(controller.getPositionCalculatorParams(_vaultId), _position),
                controller.getSqrtPrice(),
                isMarginZero
            );
    }
}
