// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "../../src/libraries/DataType.sol";
import "../../src/libraries/PositionUpdater.sol";
import "./TestDeployer.sol";

abstract contract PositionUpdaterHelper is TestDeployer {
    mapping(uint256 => DataType.SubVault) internal subVaults;

    function depositToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1,
        bool _isCompound
    ) internal {
        _updateTokenPosition(
            _vault,
            _context,
            _ranges,
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            _amount0,
            _amount1,
            _isCompound,
            -1
        );
    }

    function withdrawToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        _updateTokenPosition(
            _vault,
            _context,
            _ranges,
            DataType.PositionUpdateType.WITHDRAW_TOKEN,
            _amount0,
            _amount1,
            false,
            -1
        );
    }

    function borrowToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1,
        bool _isCompound,
        int256 _margin
    ) internal {
        _updateTokenPosition(
            _vault,
            _context,
            _ranges,
            DataType.PositionUpdateType.BORROW_TOKEN,
            _amount0,
            _amount1,
            _isCompound,
            _margin
        );
    }

    function repayToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        _updateTokenPosition(
            _vault,
            _context,
            _ranges,
            DataType.PositionUpdateType.REPAY_TOKEN,
            _amount0,
            _amount1,
            false,
            -1
        );
    }

    function _updateTokenPosition(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdateType _positionUpdateType,
        uint256 _amount0,
        uint256 _amount1,
        bool _isCompound,
        int256 _margin
    ) internal {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(_positionUpdateType, 0, _isCompound, 0, 0, 0, _amount0, _amount1);

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            false,
            false,
            _context.isMarginZero,
            Constants.MARGIN_USE,
            Constants.MARGIN_STAY,
            _margin,
            0,
            EMPTY_METADATA
        );

        PositionUpdater.updatePosition(_vault, subVaults, _context, _ranges, positionUpdates, tradeOption);
    }
}
