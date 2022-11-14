//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./Controller.sol";
import "./libraries/BaseToken.sol";
import "./libraries/PriceHelper.sol";
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

    /**
     * @notice Reader constructor
     * @param _controller controller address
     */
    constructor(Controller _controller) {
        controller = _controller;

        (isMarginZero, , uniswapPool, , ) = controller.getContext();
    }

    /**
     * @notice Gets current underlying asset price.
     * @return price
     **/
    function getPrice() public view returns (uint256) {
        return PriceHelper.decodeSqrtPriceX96(isMarginZero, controller.getSqrtPrice());
    }

    /**
     * @notice Gets index price.
     * @return indexPrice
     **/
    function getIndexPrice() external view returns (uint256) {
        return PriceHelper.decodeSqrtPriceX96(isMarginZero, controller.getSqrtIndexPrice());
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

        if (range.lastTouchedTimestamp == 0) {
            return (0, 0, 0);
        }

        return LPTStateLib.getPerpStatus(address(controller), uniswapPool, range);
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

    function quoteOpenPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    ) external returns (DataType.PositionUpdateResult memory result) {
        require(_vaultId > 0);
        require(_tradeOption.quoterMode);
        try controller.openPosition(_vaultId, _position, _tradeOption, _openPositionOptions) {} catch (
            bytes memory reason
        ) {
            return handleRevert(reason);
        }
    }

    function quoteCloseSubVault(
        uint256 _vaultId,
        uint256 _subVaultIndex,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) external returns (DataType.PositionUpdateResult memory result) {
        require(_vaultId > 0);
        require(_tradeOption.quoterMode);
        try controller.closeSubVault(_vaultId, _subVaultIndex, _tradeOption, _closePositionOptions) {} catch (
            bytes memory reason
        ) {
            return handleRevert(reason);
        }
    }

    function parseRevertReason(bytes memory reason)
        private
        pure
        returns (
            int256,
            int256,
            int256,
            int256,
            int256,
            int256,
            int256,
            int256
        )
    {
        if (reason.length != 256) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (int256, int256, int256, int256, int256, int256, int256, int256));
    }

    function handleRevert(bytes memory reason) internal pure returns (DataType.PositionUpdateResult memory result) {
        (
            result.requiredAmounts.amount0,
            result.requiredAmounts.amount1,
            result.feeAmounts.amount0,
            result.feeAmounts.amount1,
            result.positionAmounts.amount0,
            result.positionAmounts.amount1,
            result.swapAmounts.amount0,
            result.swapAmounts.amount1
        ) = parseRevertReason(reason);
    }
}
