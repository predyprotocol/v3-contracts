// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
pragma abicoder v2;

import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "../DataType.sol";
import "../PositionLib.sol";
import "../PositionCalculator.sol";
import "../PositionUpdater.sol";

library LiquidationLogic {
    uint256 internal constant ORACLE_PERIOD = 1 minutes;

    /**
     * @notice Anyone can liquidates the vault if its required collateral value is positive.
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
        uint160 sqrtPrice = getSqrtTWAP(_context.uniswapPool);

        // check liquidation
        require(_checkLiquidatable(_vault, _subVaults, _context, _ranges, sqrtPrice), "L0");

        // calculate penalty
        uint256 debtValue = VaultLib.getDebtPositionValue(_vault, _subVaults, _ranges, _context, sqrtPrice);

        // close position
        uint256 penaltyAmount = reducePosition(
            _vault,
            _subVaults,
            _context,
            _ranges,
            _positionUpdates,
            debtValue / 200
        );

        require(VaultLib.getDebtPositionValue(_vault, _subVaults, _ranges, _context, sqrtPrice) == 0, "L1");

        sendReward(_context, msg.sender, penaltyAmount);
    }

    /**
     * @notice Checks the vault is liquidatable or not.
     * if Min collateral is greater than margin value + position value, then return true.
     * otherwise return false.
     */
    function checkLiquidatable(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges
    ) public view returns (bool) {
        uint160 sqrtPrice = getSqrtTWAP(_context.uniswapPool);

        return _checkLiquidatable(_vault, _subVaults, _context, _ranges, sqrtPrice);
    }

    function _checkLiquidatable(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint160 sqrtPrice
    ) internal view returns (bool) {
        DataType.Position memory position = VaultLib.getPosition(_vault, _subVaults, _ranges, _context);

        // calculate Min. Collateral by using TWAP.
        int256 minCollateral = PositionCalculator.calculateMinCollateral(position, sqrtPrice, _context.isMarginZero);

        int256 vaultValue = VaultLib.getVaultValue(_vault, _subVaults, _ranges, _context, position, sqrtPrice);

        return minCollateral > vaultValue;
    }

    function reducePosition(
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _penaltyAmount
    ) public returns (uint256) {
        // reduce position
        (int256 surplusAmount0, int256 surplusAmount1) = PositionUpdater.updatePosition(
            _vault,
            _subVaults,
            _context,
            _ranges,
            _positionUpdates,
            // reduce only
            DataType.TradeOption(true, true, false, _context.isMarginZero, -2, -2)
        );

        require(0 == surplusAmount0, "L2");
        require(0 == surplusAmount1, "L3");

        {
            uint256 penaltyAmount;

            if (_context.isMarginZero) {
                (_vault.marginAmount0, penaltyAmount) = PredyMath.subReward(_vault.marginAmount0, _penaltyAmount);
            } else {
                (_vault.marginAmount1, penaltyAmount) = PredyMath.subReward(_vault.marginAmount1, _penaltyAmount);
            }

            return penaltyAmount;
        }
    }

    function sendReward(
        DataType.Context memory _context,
        address _liquidator,
        uint256 _reward
    ) internal {
        TransferHelper.safeTransfer(_context.isMarginZero ? _context.token0 : _context.token1, _liquidator, _reward);
    }

    /**
     * Gets square root of time Wweighted average price.
     */
    function getSqrtTWAP(address _uniswapPool) internal view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(_uniswapPool), ORACLE_PERIOD);
    }
}
