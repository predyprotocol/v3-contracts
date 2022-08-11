// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./DataType.sol";
import "./VaultLib.sol";
import "./LPTStateLib.sol";
import "./UniHelper.sol";

library PositionUpdator {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using VaultLib for DataType.Vault;
    using LPTStateLib for DataType.PerpStatus;

    uint24 internal constant FEE_TIER = 500;

    /**
     * @notice update position and return required token amounts.
     */
    function updatePosition(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates
    ) internal returns (int256 requiredAmount0, int256 requiredAmount1) {
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            DataType.PositionUpdate memory positionUpdate = _positionUpdates[i];

            if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_TOKEN) {
                depositTokens(_vault, _context, positionUpdate.param0, positionUpdate.param1);

                requiredAmount0 = requiredAmount0.add(int256(positionUpdate.param0));
                requiredAmount1 = requiredAmount1.add(int256(positionUpdate.param1));
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_TOKEN) {
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_TOKEN) {
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_TOKEN) {
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.DEPOSIT_LPT) {
                (uint256 amount0, uint256 amount1) = depositLPT(_vault, _context, _ranges, positionUpdate);

                requiredAmount0 = requiredAmount0.add(int256(amount0));
                requiredAmount1 = requiredAmount1.add(int256(amount1));
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.WITHDRAW_LPT) {
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.BORROW_LPT) {
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.REPAY_LPT) {
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_IN) {
            }else if(positionUpdate.positionUpdateType == DataType.PositionUpdateType.SWAP_EXACT_OUT) {
            }
        }
    }

    function depositTokens(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        uint256 amount0,
        uint256 amount1
    ) internal pure {
    }

    function withdrawTokens(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        uint256 amount0,
        uint256 amount1
    ) internal pure {
    }

    function borrowTokens(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        uint256 amount0,
        uint256 amount1
    ) internal pure {
    }

    function repayTokens(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        uint256 amount0,
        uint256 amount1
    ) internal pure {
    }

    function depositLPT(
        DataType.Vault storage _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate memory _positionUpdate
    ) internal returns (uint256 requiredAmount0, uint256 requiredAmount1) {
        bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdate.lowerTick, _positionUpdate.upperTick);

        (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidity(
            getSqrtPrice(IUniswapV3Pool(_context.uniswapPool)),
            _positionUpdate.lowerTick,
            _positionUpdate.upperTick,
            _positionUpdate.liquidity
        );

        uint128 liquidity;
        if(_ranges[rangeId].tokenId > 0) {
            (, liquidity, requiredAmount0, requiredAmount1) =  UniHelper.increaseLiquidity(
                _context,
                _ranges[rangeId].tokenId,
                amount0,
                amount1,
                _positionUpdate.param0,
                _positionUpdate.param1
            );
        } else {
            uint256 tokenId = 0;

            (tokenId, liquidity, requiredAmount0, requiredAmount1) =  UniHelper.mint(
                _context,
                _positionUpdate.lowerTick,
                _positionUpdate.upperTick,
                amount0,
                amount1,
                _positionUpdate.param0,
                _positionUpdate.param1
            );

            _ranges[rangeId].lowerTick = _positionUpdate.lowerTick;
            _ranges[rangeId].upperTick = _positionUpdate.upperTick;
            _ranges[rangeId].lastTouchedTimestamp = block.timestamp;

            _ranges[rangeId].registerNewLPTState(tokenId);
        }


        _vault.depositLPT(_ranges, rangeId, _positionUpdate.liquidity);
    }

    function withdrawLPT(
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates
    ) internal pure returns (uint256 requiredAmount0, uint256 requiredAmount1) {
    }

    function borrowLPT(
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates
    ) internal pure returns (uint256 requiredAmount0, uint256 requiredAmount1) {
    }

    function repayLPT(
        DataType.Vault storage _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates
    ) internal pure returns (uint256 requiredAmount0, uint256 requiredAmount1) {
    }

    function swapExactIn(
        DataType.PositionUpdate[] memory _positionUpdates
    ) internal pure returns (uint256 requiredAmount0, uint256 requiredAmount1) {
    }

    function swapExactOut(
        DataType.PositionUpdate[] memory _positionUpdates
    ) internal pure returns (uint256 requiredAmount0, uint256 requiredAmount1) {
    }

    function getSqrtPrice(IUniswapV3Pool _uniswapPool) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = _uniswapPool.slot0();
    }
}