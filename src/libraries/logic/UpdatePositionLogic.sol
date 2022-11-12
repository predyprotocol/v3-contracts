// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import {IVaultNFT} from "../../interfaces/IVaultNFT.sol";
import "./LiquidationLogic.sol";
import "../DataType.sol";
import "../PositionLib.sol";
import "../PositionCalculator.sol";
import "../PositionUpdater.sol";
import "../PriceHelper.sol";

/**
 * @title UpdatePositionLogic library
 * @notice Implements the base logic for all the actions related to update position.
 * Error Codes
 * UPL0: vault must be safe
 */
library UpdatePositionLogic {
    using SafeMath for uint256;

    event PositionUpdated(uint256 vaultId, DataType.PositionUpdateResult positionUpdateResult, bytes metadata);
    event VaultCreated(uint256 vaultId, address owner);

    function updatePosition(
        uint256 vaultId,
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates,
        DataType.TradeOption memory _tradeOption
    ) external returns (DataType.PositionUpdateResult memory positionUpdateResult) {
        require(!_tradeOption.isLiquidationCall);

        // update position in the vault
        positionUpdateResult = PositionUpdater.updatePosition(
            _vault,
            _subVaults,
            _context,
            _ranges,
            _positionUpdates,
            _tradeOption
        );

        if (_tradeOption.quoterMode) {
            revertRequiredAmounts(positionUpdateResult);
        }

        // check the vault is safe
        require(LiquidationLogic.isVaultSafe(_vault, _subVaults, _context, _ranges), "UPL0");

        if (positionUpdateResult.requiredAmounts.amount0 > 0) {
            TransferHelper.safeTransferFrom(
                _context.token0,
                msg.sender,
                address(this),
                uint256(positionUpdateResult.requiredAmounts.amount0)
            );
        } else if (positionUpdateResult.requiredAmounts.amount0 < 0) {
            TransferHelper.safeTransfer(
                _context.token0,
                msg.sender,
                uint256(-positionUpdateResult.requiredAmounts.amount0)
            );
        }

        if (positionUpdateResult.requiredAmounts.amount1 > 0) {
            TransferHelper.safeTransferFrom(
                _context.token1,
                msg.sender,
                address(this),
                uint256(positionUpdateResult.requiredAmounts.amount1)
            );
        } else if (positionUpdateResult.requiredAmounts.amount1 < 0) {
            TransferHelper.safeTransfer(
                _context.token1,
                msg.sender,
                uint256(-positionUpdateResult.requiredAmounts.amount1)
            );
        }

        emit PositionUpdated(vaultId, positionUpdateResult, _tradeOption.metadata);
    }

    function revertRequiredAmounts(DataType.PositionUpdateResult memory positionUpdateResult) internal pure {
        int256 r0 = positionUpdateResult.requiredAmounts.amount0;
        int256 r1 = positionUpdateResult.requiredAmounts.amount1;
        int256 f0 = positionUpdateResult.feeAmounts.amount0;
        int256 f1 = positionUpdateResult.feeAmounts.amount1;
        int256 p0 = positionUpdateResult.positionAmounts.amount0;
        int256 p1 = positionUpdateResult.positionAmounts.amount1;
        int256 s0 = positionUpdateResult.swapAmounts.amount0;
        int256 s1 = positionUpdateResult.swapAmounts.amount1;

        assembly {
            let ptr := mload(0x20)
            mstore(ptr, r0)
            mstore(add(ptr, 0x20), r1)
            mstore(add(ptr, 0x40), f0)
            mstore(add(ptr, 0x60), f1)
            mstore(add(ptr, 0x80), p0)
            mstore(add(ptr, 0xA0), p1)
            mstore(add(ptr, 0xC0), s0)
            mstore(add(ptr, 0xE0), s1)
            revert(ptr, 256)
        }
    }
}
