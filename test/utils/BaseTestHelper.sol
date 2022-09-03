// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import "../../src/Controller.sol";
import "../../src/ControllerHelper.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/libraries/LPTMath.sol";
import "../../src/libraries/VaultLib.sol";
import "../../src/libraries/PositionCalculator.sol";
import "../../src/libraries/DataType.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

abstract contract BaseTestHelper {
    IERC20 internal token0;
    IERC20 internal token1;
    ControllerHelper internal controller;
    // ControllerHelper internal controllerHelper;
    NonfungiblePositionManager internal positionManager;
    SwapRouter internal swapRouter;
    IUniswapV3Pool internal uniPool;

    address internal constant otherAccount = address(1500);

    bytes32[] internal rangeIds;

    DataType.MetaData internal emptyMetaData;

    mapping(uint256 => DataType.SubVault) internal subVaults;

    function getContext() internal view returns (DataType.Context memory) {
        BaseToken.TokenState memory tokenState = BaseToken.TokenState(0, 0, 1e18, 1e18);

        return
            DataType.Context(
                address(token0),
                address(token1),
                500,
                address(positionManager),
                address(swapRouter),
                address(uniPool),
                true,
                1,
                tokenState,
                tokenState
            );
    }

    function getPerpState() internal pure returns (DataType.PerpStatus memory) {
        return DataType.PerpStatus(0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    function depositToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        _updateTokenPosition(_vault, _context, _ranges, DataType.PositionUpdateType.DEPOSIT_TOKEN, _amount0, _amount1);
    }

    function withdrawToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        _updateTokenPosition(_vault, _context, _ranges, DataType.PositionUpdateType.WITHDRAW_TOKEN, _amount0, _amount1);
    }

    function borrowToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        _updateTokenPosition(_vault, _context, _ranges, DataType.PositionUpdateType.BORROW_TOKEN, _amount0, _amount1);
    }

    function repayToken(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        _updateTokenPosition(_vault, _context, _ranges, DataType.PositionUpdateType.REPAY_TOKEN, _amount0, _amount1);
    }

    function _updateTokenPosition(
        DataType.Vault storage _vault,
        DataType.Context storage _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdateType _positionUpdateType,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(_positionUpdateType, 0, false, 0, 0, 0, _amount0, _amount1);

        PositionUpdater.updatePosition(
            _vault,
            subVaults,
            _context,
            _ranges,
            positionUpdates,
            DataType.TradeOption(false, false, false, _context.isMarginZero, -1, -1)
        );
    }

    function depositToken(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            0,
            false,
            0,
            0,
            0,
            _amount0,
            _amount1
        );

        controller.updatePosition(
            _vaultId,
            positionUpdates,
            _amount0,
            _amount1,
            DataType.TradeOption(false, false, false, controller.getIsMarginZero(), -1, -1),
            emptyMetaData
        );
    }

    function depositLPT(
        uint256 _vaultId,
        uint256 _subVaultId,
        int24 _lower,
        int24 _upper,
        uint256 _amount
    ) public returns (uint256) {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        (uint128 liquidity, uint256 amount0, uint256 amount1) = LPTMath.getLiquidityAndAmountToDeposit(
            controller.getIsMarginZero(),
            _amount,
            controller.getSqrtPrice(),
            _lower,
            _upper
        );
        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            _subVaultId,
            false,
            liquidity,
            _lower,
            _upper,
            0,
            0
        );

        return
            controller.updatePosition(
                _vaultId,
                positionUpdates,
                (amount0 * 105) / 100,
                (amount1 * 105) / 100,
                DataType.TradeOption(false, false, false, controller.getIsMarginZero(), -1, -1),
                emptyMetaData
            );
    }

    function borrowLPT(
        uint256 _vaultId,
        uint256 _subVaultId,
        int24 _tick,
        int24 _lower,
        int24 _upper,
        uint256 _amount,
        uint256 _margin
    ) public returns (uint256) {
        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, _amount, _tick, _lower, _upper);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, _lower, _upper);
        DataType.Position memory position = DataType.Position(_subVaultId, _margin, _amount, 0, 0, lpts);

        return
            controller.openPosition(
                _vaultId,
                position,
                DataType.TradeOption(false, false, false, controller.getIsMarginZero(), -1, -1),
                DataType.OpenPositionOption(1500 * 1e6, 1000, 1e10, 0, emptyMetaData)
            );
    }

    function swap(address recipient, bool _priceUp) internal {
        uint256 ethAmount;
        uint256 usdcAmount;
        if (_priceUp) {
            usdcAmount = 1000 * 1e6;
            ethAmount = 5 * 1e18;
        } else {
            usdcAmount = 8000 * 1e6;
            ethAmount = 1 * 1e18;
        }
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: 500,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: usdcAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: 500,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: ethAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function slip(
        address recipient,
        bool _priceUp,
        uint256 _amount
    ) internal {
        if (_priceUp) {
            uint256 usdcAmount = (_amount * 1200) / 1e12;
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(token0),
                    tokenOut: address(token1),
                    fee: 500,
                    recipient: recipient,
                    deadline: block.timestamp,
                    amountIn: usdcAmount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        } else {
            uint256 ethAmount = _amount;
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(token1),
                    tokenOut: address(token0),
                    fee: 500,
                    recipient: recipient,
                    deadline: block.timestamp,
                    amountIn: ethAmount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    function swapToSamePrice(address recipient) internal {
        uint256 usdcAmount = 1000 * 1e6;

        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: 500,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: usdcAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        swapRouter.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: 500,
                recipient: recipient,
                deadline: block.timestamp,
                amountOut: usdcAmount,
                amountInMaximum: type(uint256).max,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function showCurrentTick() internal view {
        (, int24 tick, , , , , ) = uniPool.slot0();
        console.log(6, uint256(tick));
    }

    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = uniPool.slot0();
    }
}
