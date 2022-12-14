// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import "../../src/Controller.sol";
import "../../src/Reader.sol";
import "../../src/VaultNFT.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/libraries/VaultLib.sol";
import "../../src/libraries/PositionCalculator.sol";
import "../../src/libraries/DataType.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

abstract contract BaseTestHelper {
    IERC20 internal token0;
    IERC20 internal token1;

    Controller internal controller;
    Reader internal reader;

    NonfungiblePositionManager internal positionManager;
    SwapRouter internal swapRouter;
    IUniswapV3Pool internal uniPool;

    MockERC20 internal weth = new MockERC20("WETH", "WETH", 18);
    MockERC20 internal usdc = new MockERC20("USDC", "USDC", 6);

    address internal constant OTHER_ACCOUNT = address(1500);

    bytes32[] internal rangeIds;

    bytes internal constant EMPTY_METADATA = bytes("");

    function getContext() internal view returns (DataType.Context memory) {
        BaseToken.TokenState memory tokenState = BaseToken.TokenState(0, 0, 0, 0, 1e18, 1e18, 0, 0);

        return
            DataType.Context(
                address(token0),
                address(token1),
                500,
                address(swapRouter),
                address(uniPool),
                address(0),
                true,
                1,
                tokenState,
                tokenState,
                0,
                0
            );
    }

    function getPerpState() internal pure returns (DataType.PerpStatus memory) {
        return DataType.PerpStatus(0, 0, 0, 0, 0, 0, 0, 0);
    }

    function getIsMarginZero() internal view returns (bool) {
        (bool isMarginZero, , , , ) = controller.getContext();

        return isMarginZero;
    }

    function depositToken(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1,
        bool _withCompound
    ) public returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            0,
            _withCompound,
            0,
            0,
            0,
            _amount0,
            _amount1
        );

        (vaultId, , ) = controller.updatePosition(
            _vaultId,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function borrowToken(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) public returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_TOKEN,
            0,
            false,
            0,
            0,
            0,
            _amount0,
            _amount1
        );

        (vaultId, , ) = controller.updatePosition(
            _vaultId,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function depositLPT(
        uint256 _vaultId,
        uint256 _subVaultId,
        int24 _lower,
        int24 _upper,
        uint256 _amount
    ) public returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        (uint128 liquidity, , ) = getLiquidityAndAmountToDeposit(
            getIsMarginZero(),
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

        (vaultId, , ) = controller.updatePosition(
            _vaultId,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                _vaultId == 0 ? Constants.MARGIN_USE : Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                _vaultId == 0 ? Constants.MIN_MARGIN_AMOUNT : 0,
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
        );
    }

    function openShortPut(
        uint256 _vaultId,
        uint256 _subVaultId,
        int24 _lower,
        int24 _upper,
        uint256 _amount
    ) public returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](2);

        (uint128 liquidity, uint256 amount0, ) = getLiquidityAndAmountToDeposit(
            getIsMarginZero(),
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
        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.BORROW_TOKEN,
            _subVaultId,
            false,
            0,
            0,
            0,
            amount0 / 2,
            0
        );

        (vaultId, , ) = controller.updatePosition(
            _vaultId,
            positionUpdates,
            DataType.TradeOption(
                false,
                true,
                false,
                getIsMarginZero(),
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 0, block.timestamp)
        );
    }

    function getBorrowLPTPosition(
        uint256 _subVaultId,
        int24 _tick,
        int24 _lower,
        int24 _upper,
        uint256 _amount
    ) internal pure returns (DataType.Position[] memory positions) {
        (uint128 liquidity, , ) = getLiquidityAndAmountToBorrow(true, _amount, _tick, _lower, _upper);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, _lower, _upper);

        positions = new DataType.Position[](1);

        positions[0] = DataType.Position(_subVaultId, 0, _amount, 0, 0, lpts);
    }

    function borrowLPT(
        uint256 _vaultId,
        uint256 _subVaultId,
        int24 _tick,
        int24 _lower,
        int24 _upper,
        uint256 _amount,
        uint256 _margin
    ) public returns (uint256 vaultId) {
        DataType.Position[] memory positions = getBorrowLPTPosition(_subVaultId, _tick, _lower, _upper, _amount);

        (vaultId, , ) = controller.openPosition(
            _vaultId,
            positions[0],
            DataType.TradeOption(
                false,
                false,
                false,
                getIsMarginZero(),
                Constants.MARGIN_USE,
                Constants.MARGIN_STAY,
                int256(_margin),
                0,
                EMPTY_METADATA
            ),
            DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, block.timestamp)
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

    function getLowerSqrtPrice() internal view returns (uint160) {
        return (controller.getSqrtPrice() * 100) / 120;
    }

    function getUpperSqrtPrice() internal view returns (uint160) {
        return (controller.getSqrtPrice() * 120) / 100;
    }

    function getVaultStatus(uint256 _vaultId) internal returns (DataType.VaultStatus memory) {
        return controller.getVaultStatus(_vaultId, controller.getSqrtPrice());
    }

    function getLiquidityAndAmountToDeposit(
        bool isMarginZero,
        uint256 requestedAmount,
        uint160 currentSqrtPrice,
        int24 lower,
        int24 upper
    )
        internal
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (isMarginZero) {
            return
                getLiquidityAndAmount(
                    0,
                    requestedAmount,
                    TickMath.getSqrtRatioAtTick(upper),
                    currentSqrtPrice,
                    lower,
                    upper
                );
        } else {
            return
                getLiquidityAndAmount(
                    requestedAmount,
                    0,
                    TickMath.getSqrtRatioAtTick(lower),
                    currentSqrtPrice,
                    lower,
                    upper
                );
        }
    }

    function getLiquidityAndAmountToBorrow(
        bool isMarginZero,
        uint256 requestedAmount,
        int24 tick,
        int24 lower,
        int24 upper
    )
        internal
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (isMarginZero) {
            return
                getLiquidityAndAmount(
                    0,
                    requestedAmount,
                    TickMath.getSqrtRatioAtTick(upper),
                    TickMath.getSqrtRatioAtTick(tick),
                    lower,
                    upper
                );
        } else {
            return
                getLiquidityAndAmount(
                    requestedAmount,
                    0,
                    TickMath.getSqrtRatioAtTick(lower),
                    TickMath.getSqrtRatioAtTick(tick),
                    lower,
                    upper
                );
        }
    }

    function getLiquidityAndAmount(
        uint256 requestedAmount0,
        uint256 requestedAmount1,
        uint160 sqrtPrice1,
        uint160 sqrtPrice2,
        int24 lower,
        int24 upper
    )
        internal
        pure
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        (liquidity) = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice1,
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            requestedAmount0,
            requestedAmount1
        );

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPrice2,
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            liquidity
        );
    }

    function blockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }
}
