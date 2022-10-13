//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./Controller.sol";
import "./libraries/BaseToken.sol";
import "./libraries/LPTMath.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/UniHelper.sol";

/**
 * @title Reader contract
 * @notice Reader contract with an controller
 **/
contract Reader {
    Controller public controller;
    bool public isMarginZero;
    address public uniswapPool;
    address public positionManager;

    /**
     * @notice Reader constructor
     * @param _controller controller address
     */
    constructor(Controller _controller) {
        controller = _controller;

        (isMarginZero, , uniswapPool, positionManager, , ) = controller.getContext();
    }

    /**
     * @notice Gets current underlying asset price.
     * @return price
     **/
    function getPrice() public view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(isMarginZero, controller.getSqrtPrice());
    }

    /**
     * @notice Gets time weighted average price of underlying asset.
     * @return twap
     **/
    function getTWAP() external view returns (uint256) {
        uint160 sqrtPrice = UniHelper.getSqrtTWAP(uniswapPool);

        return LPTMath.decodeSqrtPriceX96(isMarginZero, sqrtPrice);
    }

    /**
     * @notice Gets asset status
     **/
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

    /**
     * @notice Gets liquidity provider token status
     **/
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

        if (range.tokenId == 0) {
            return (0, 0, 0);
        }

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
