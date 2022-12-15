//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
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
    using SafeMath for uint256;

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
    function getAssetStatus(BaseToken.TokenState memory _tokenState0, BaseToken.TokenState memory _tokenState1)
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            BaseToken.getTotalCollateralValue(_tokenState0),
            BaseToken.getTotalDebtValue(_tokenState0),
            BaseToken.getUtilizationRatio(_tokenState0),
            BaseToken.getTotalCollateralValue(_tokenState1),
            BaseToken.getTotalDebtValue(_tokenState1),
            BaseToken.getUtilizationRatio(_tokenState1)
        );
    }

    function calculateLPTPremium(
        bytes32 _rangeId,
        bool _isBorrow,
        uint256 _deltaLiquidity,
        uint256 _elapsed,
        uint256 _baseTradeFeePerLiquidity
    )
        external
        view
        returns (
            uint256 premiumGrowthForBorrower,
            uint256 premiumGrowthForLender,
            uint256 protocolFeePerLiquidity,
            uint256 tradeFeePerLiquidity
        )
    {
        (uint256 supply, uint256 borrow, ) = controller.getUtilizationRatio(_rangeId);

        if (supply == 0) {
            return (0, 0, 0, _baseTradeFeePerLiquidity);
        }

        uint256 afterUr = _isBorrow
            ? borrow.add(_deltaLiquidity).mul(1e18).div(supply)
            : borrow.mul(1e18).div(supply.add(_deltaLiquidity));

        if (afterUr > 1e18) {
            afterUr = 1e18;
        }

        (premiumGrowthForBorrower, , protocolFeePerLiquidity) = controller.calculateLPTBorrowerAndLenderPremium(
            _rangeId,
            afterUr,
            _elapsed
        );

        premiumGrowthForLender = premiumGrowthForBorrower.sub(protocolFeePerLiquidity).mul(afterUr).div(1e18);

        tradeFeePerLiquidity = _baseTradeFeePerLiquidity.mul(uint256(1e18).sub(afterUr)).div(1e18);
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
        uint256 _subVaultId,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    ) external returns (DataType.PositionUpdateResult memory result) {
        require(_vaultId > 0);
        require(_tradeOption.quoterMode);
        try controller.closeSubVault(_vaultId, _subVaultId, _tradeOption, _closePositionOptions) {} catch (
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
