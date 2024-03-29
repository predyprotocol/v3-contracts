// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "../DataType.sol";
import "../PositionLib.sol";
import "../PositionCalculator.sol";
import "../PositionUpdater.sol";
import "../PriceHelper.sol";

/**
 * @title LiquidationLogic library
 * @notice Implements the base logic for all the actions related to liquidation call.
 */
library LiquidationLogic {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    event Liquidated(uint256 indexed vaultId, address liquidator, uint256 penaltyAmount);

    /**
     * @notice Anyone can liquidates the vault if its vault value is less than Min. Deposit.
     * Up to 100% of debt is repaid.
     * @param _vault vault
     * @param _positionUpdates parameters to update position
     */
    function execLiquidation(
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.PositionUpdate[] memory _positionUpdates,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) external {
        uint160 sqrtTwap = PriceHelper.getSqrtIndexPrice(_context);

        PositionCalculator.PositionCalculatorParams memory _params = VaultLib.getPositionCalculatorParams(
            _vault,
            _subVaults,
            _ranges,
            _context
        );

        // check that the vault is not safe
        require(!_isVaultSafe(_context.isMarginZero, _params, sqrtTwap), "L0");

        // calculate debt value to calculate penalty amount
        (, , uint256 debtValue) = PositionCalculator.calculateCollateralAndDebtValue(
            _params,
            sqrtTwap,
            _context.isMarginZero
        );

        // close all positions in the vault
        uint256 penaltyAmount = reducePosition(
            _vault,
            _subVaults,
            _context,
            _ranges,
            _positionUpdates,
            calculatePenaltyAmount(debtValue)
        );

        sendReward(_context, msg.sender, penaltyAmount);

        {
            // reverts if price is out of slippage threshold
            uint256 sqrtPrice = UniHelper.getSqrtPrice(_context.uniswapPool);

            uint256 liquidationSlippageSqrtTolerance = calculateLiquidationSlippageTolerance(debtValue);

            require(
                uint256(sqrtTwap).mul(1e6).div(1e6 + liquidationSlippageSqrtTolerance) <= sqrtPrice &&
                    sqrtPrice <= uint256(sqrtTwap).mul(1e6 + liquidationSlippageSqrtTolerance).div(1e6),
                "L4"
            );
        }

        emit Liquidated(_vault.vaultId, msg.sender, penaltyAmount);
    }

    function calculateLiquidationSlippageTolerance(uint256 _debtValue) internal pure returns (uint256) {
        uint256 liquidationSlippageSqrtTolerance = PredyMath.max(
            Constants.LIQ_SLIPPAGE_SQRT_SLOPE.mul(PredyMath.sqrt(_debtValue.mul(1e6))) /
                1e6 +
                Constants.LIQ_SLIPPAGE_SQRT_BASE,
            Constants.BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE
        );

        if (liquidationSlippageSqrtTolerance > 1e6) {
            return 1e6;
        }

        return liquidationSlippageSqrtTolerance;
    }

    function calculatePenaltyAmount(uint256 _debtValue) internal pure returns (uint256) {
        // penalty amount is 0.4% of debt value
        return
            PredyMath.max(
                ((_debtValue / 250) / Constants.MARGIN_ROUNDED_DECIMALS).mul(Constants.MARGIN_ROUNDED_DECIMALS),
                Constants.MIN_PENALTY
            );
    }

    /**
     * @notice Checks the vault is safe or not.
     * if the vault value is greater than Min. Deposit, then return true.
     * otherwise return false.
     */
    function isVaultSafe(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) public view returns (bool) {
        uint160 sqrtPrice = PriceHelper.getSqrtIndexPrice(_context);

        PositionCalculator.PositionCalculatorParams memory _params = VaultLib.getPositionCalculatorParams(
            _vault,
            _subVaults,
            _ranges,
            _context
        );

        return _isVaultSafe(_context.isMarginZero, _params, sqrtPrice);
    }

    function getVaultValue(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) external view returns (int256) {
        uint160 sqrtPrice = PriceHelper.getSqrtIndexPrice(_context);

        PositionCalculator.PositionCalculatorParams memory _params = VaultLib.getPositionCalculatorParams(
            _vault,
            _subVaults,
            _ranges,
            _context
        );

        return VaultLib.getVaultValue(_context, _params, sqrtPrice);
    }

    function _isVaultSafe(
        bool isMarginZero,
        PositionCalculator.PositionCalculatorParams memory _params,
        uint160 sqrtPrice
    ) internal pure returns (bool) {
        // calculate Min. Deposit by using TWAP.
        int256 minDeposit = PositionCalculator.calculateMinDeposit(_params, sqrtPrice, isMarginZero);

        int256 vaultValue;
        int256 marginValue;
        {
            uint256 assetValue;
            uint256 debtValue;

            (marginValue, assetValue, debtValue) = PositionCalculator.calculateCollateralAndDebtValue(
                _params,
                sqrtPrice,
                isMarginZero
            );

            vaultValue = marginValue.add(int256(assetValue)).sub(int256(debtValue));

            if (debtValue == 0) {
                // if debt value is 0 then vault is safe.
                return true;
            }
        }

        return minDeposit <= vaultValue && marginValue >= 0;
    }

    function reducePosition(
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _penaltyAmount
    ) public returns (uint256 penaltyAmount) {
        // reduce position
        DataType.PositionUpdateResult memory positionUpdateResult = PositionUpdater.updatePosition(
            _vault,
            _subVaults,
            _context,
            _ranges,
            _positionUpdates,
            // reduce only
            DataType.TradeOption(
                true,
                true,
                false,
                _context.isMarginZero,
                Constants.MARGIN_USE,
                Constants.MARGIN_USE,
                0,
                0,
                bytes("")
            )
        );

        require(0 == positionUpdateResult.requiredAmounts.amount0, "L2");
        require(0 == positionUpdateResult.requiredAmounts.amount1, "L3");

        {
            if (_context.isMarginZero) {
                (_vault.marginAmount0, penaltyAmount) = PredyMath.subReward(_vault.marginAmount0, _penaltyAmount);
            } else {
                (_vault.marginAmount1, penaltyAmount) = PredyMath.subReward(_vault.marginAmount1, _penaltyAmount);
            }
        }
    }

    function sendReward(
        DataType.Context memory _context,
        address _liquidator,
        uint256 _reward
    ) internal {
        TransferHelper.safeTransfer(_context.isMarginZero ? _context.token0 : _context.token1, _liquidator, _reward);
    }

    function getSqrtIndexPrice(DataType.Context memory _context) external view returns (uint160) {
        return PriceHelper.getSqrtIndexPrice(_context);
    }
}
