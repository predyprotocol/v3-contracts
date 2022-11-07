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

    event PositionUpdated(
        uint256 vaultId,
        DataType.TokenAmounts requiredAmounts,
        DataType.TokenAmounts swapAmounts,
        bytes metadata
    );
    event VaultCreated(uint256 vaultId, address owner);

    function updatePosition(
        uint256 vaultId,
        DataType.Vault storage _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates,
        DataType.TradeOption memory _tradeOption
    ) external returns (DataType.TokenAmounts memory requiredAmounts, DataType.TokenAmounts memory swapAmounts) {
        require(!_tradeOption.isLiquidationCall);

        // update position in the vault
        (requiredAmounts, swapAmounts) = PositionUpdater.updatePosition(
            _vault,
            _subVaults,
            _context,
            _ranges,
            _positionUpdates,
            _tradeOption
        );

        if (_tradeOption.quoterMode) {
            revertRequiredAmounts(requiredAmounts, swapAmounts);
        }

        // check the vault is safe
        require(!LiquidationLogic.checkLiquidatable(_vault, _subVaults, _context, _ranges), "UPL0");

        if (requiredAmounts.amount0 > 0) {
            TransferHelper.safeTransferFrom(
                _context.token0,
                msg.sender,
                address(this),
                uint256(requiredAmounts.amount0)
            );
        } else if (requiredAmounts.amount0 < 0) {
            TransferHelper.safeTransfer(_context.token0, msg.sender, uint256(-requiredAmounts.amount0));
        }

        if (requiredAmounts.amount1 > 0) {
            TransferHelper.safeTransferFrom(
                _context.token1,
                msg.sender,
                address(this),
                uint256(requiredAmounts.amount1)
            );
        } else if (requiredAmounts.amount1 < 0) {
            TransferHelper.safeTransfer(_context.token1, msg.sender, uint256(-requiredAmounts.amount1));
        }

        emit PositionUpdated(vaultId, requiredAmounts, swapAmounts, _tradeOption.metadata);
    }

    function revertRequiredAmounts(
        DataType.TokenAmounts memory requiredAmounts,
        DataType.TokenAmounts memory swapAmounts
    ) internal pure {
        int256 r0 = requiredAmounts.amount0;
        int256 r1 = requiredAmounts.amount1;
        int256 s0 = swapAmounts.amount0;
        int256 s1 = swapAmounts.amount1;

        assembly {
            let ptr := mload(0x20)
            mstore(ptr, r0)
            mstore(add(ptr, 0x20), r1)
            mstore(add(ptr, 0x40), s0)
            mstore(add(ptr, 0x60), s1)
            revert(ptr, 128)
        }
    }
}
