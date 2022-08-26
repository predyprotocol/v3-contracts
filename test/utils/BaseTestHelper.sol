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
                tokenState,
                tokenState
            );
    }

    function getPerpState() internal view returns (DataType.PerpStatus memory) {
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

        positionUpdates[0] = DataType.PositionUpdate(_positionUpdateType, false, 0, 0, 0, _amount0, _amount1);

        PositionUpdater.updatePosition(
            _vault,
            _context,
            _ranges,
            positionUpdates,
            DataType.TradeOption(false, false, false, _context.isMarginZero)
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
            DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
            bytes("")
        );
    }

    function depositLPT(
        uint256 _vaultId,
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
                DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
                bytes("")
            );
    }

    function borrowLPT(
        uint256 _vaultId,
        int24 _tick,
        int24 _lower,
        int24 _upper,
        uint256 _amount,
        uint256 _margin
    ) public returns (uint256) {
        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, _amount, _tick, _lower, _upper);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        lpts[0] = DataType.LPT(false, liquidity, _lower, _upper);
        DataType.Position memory position = DataType.Position(_margin, _amount, 0, 0, lpts);

        return
            controller.openPosition(
                _vaultId,
                position,
                DataType.TradeOption(false, false, false, controller.getIsMarginZero()),
                DataType.OpenPositionOption(1500 * 1e6, 1000, 1e10, 0, bytes(""))
            );
    }

    /*

    function createBoard() public returns(uint256){
        int24[] memory lowers = new int24[](5);
        int24[] memory uppers = new int24[](5);

        // current tick is 202562
        lowers[0] = 202560;
        uppers[0] = 202570;
        lowers[1] = 202580;
        uppers[1] = 202590;
        lowers[2] = 202680;
        uppers[2] = 202690;
        lowers[3] = 202780;
        uppers[3] = 202790;
        lowers[4] = 202880;
        uppers[4] = 202890;


        uint256 buffer0;
        uint256 buffer1;
        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](lowers.length);
        PositionVerifier.Proof[] memory proofs = new PositionVerifier.Proof[](lowers.length);

        for(uint256 i = 0;i < lowers.length;i++) {
            (uint128 liquidity, uint256 a0, uint256 a1) = getTokenAmountsToDepositLPT(lowers[i], uppers[i], 1e12);
            console.log(liquidity);
            buffer0 += a0;
            buffer1 += a1;
            lpts[i] = PositionVerifier.LPT(true, liquidity, lowers[i], uppers[i]);
            proofs[i] = PositionVerifier.Proof(false, false, 0);

            rangeIds.push(getRangeKey(lowers[i], uppers[i]));
        }

        PositionVerifier.Position memory position = PositionVerifier.Position(0, 0, 0, 0, lpts);

        return pool.updatePosition(0, 0, IProductVerifier.OpenPositionParams(position, 0), buffer0*2, buffer1*2);

    }

    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }

    function preDepositTokens(uint256 _amount0, uint256 _amount1)
        public
        returns (
            IProductVerifier.PositionUpdate[] memory params,
            uint256 buffer0,
            uint256 buffer1
        )
    {
        params = new IProductVerifier.PositionUpdate[](1);
        
        params[0] = IProductVerifier.PositionUpdate(
            IProductVerifierPositionUpdateType.DEPOSIT_TOKEN,
            false,
            0,
            0,
            0,
            _amount0,
            _amount1
        );
        buffer0 = _amount0;
        buffer1 = _amount1;
    }

    function depositLPT(
        uint256 _vaultId,
        bytes32 _rangeId,
        uint256 _amount
    ) public returns (uint256) {
        VaultLib.PerpStatus memory range = pool.getRange(_rangeId);

        uint128 liquidity = getLiquidityForOptionAmount(range.lowerTick, range.upperTick, _amount);
        uint256 a0;
        uint256 a1;
        (a0, a1) = LPTMath.getAmountsForLiquidity(
            pool.getSqrtPrice(),
            range.lowerTick,
            range.upperTick,
            liquidity
        );

        IProductVerifier.PositionUpdate memory params = new IProductVerifier.PositionUpdate[](1);
        
        params[0] = IProductVerifier.PositionUpdate(
            IProductVerifierPositionUpdateType.DEPOSIT_LPT,
            false,
            range.lowerTick,
            range.upperTick,
            liquidity,
            _amount0,
            _amount1
        );
        buffer0 = _amount0;
        buffer1 = _amount1;

        return pool.updatePosition(_vaultId, params, a0, a1);
    }

    function preBorrowLPT(
        bytes32 _rangeId,
        uint256 _ethAmount,
        bool _isCall,
        uint256 _limitPrice
    )
        internal
        returns (
            IProductVerifier.PositionUpdate[] memory params,
            uint256 buffer0,
            uint256 buffer1
        )
    {
        params = new IProductVerifier.PositionUpdate[](_isCall?2:1);

        {
            VaultLib.PerpStatus memory range = pool.getRange(_rangeId);

            // calculate USDC amount
            uint256 amountMaximum;

            (amountMaximum, buffer0, buffer1) = getAmountInMaximum(position, pool.getSqrtPrice(), _limitPrice);

            params[0] = IProductVerifier.PositionUpdate(
                IProductVerifierPositionUpdateType.BORROW_LPT,
                false,
                range.lowerTick,
                range.upperTick,
                getLiquidityForOptionAmount(_rangeId, _ethAmount),
                0,
                0
            );
            if(_isCall) {
                params[1] = IProductVerifier.PositionUpdate(
                    IProductVerifierPositionUpdateType.SWAP_EXACT_OUT,
                    false,
                    0,
                    0,
                    0,
                    _ethAmount,
                    amountMaximum
                );
            }
        }
    }

    function borrowLPT(
        uint256 _vaultId,
        uint256 _margin,
        bytes32 _rangeId,
        uint256 _ethAmount,
        bool _isCall,
        uint256 _limitPrice
    ) internal returns (uint256) {
        (IProductVerifier.OpenPositionParams memory params, uint256 buffer0, uint256 buffer1) = preBorrowLPT(
            _rangeId,
            _ethAmount,
            _isCall,
            _limitPrice
        );

        return pool.updatePosition(_vaultId, _margin, params, buffer0, buffer1);
    }

    function getAmountInMaximum(
        PositionVerifier.Position memory _position,
        uint160 _sqrtPrice,
        uint256 _limitPrice
    )
        internal
        returns (
            uint256 amountMaximum,
            uint256 buffer0,
            uint256 buffer1
        )
    {
        (int256 requiredAmount0, int256 requiredAmount1) = productVerifier.getRequiredTokenAmounts(
            _position,
            _sqrtPrice
        );

        if (requiredAmount0 > 0) {
            amountMaximum = (uint256(requiredAmount0) * 1e12) / _limitPrice;
            buffer1 = amountMaximum - uint256(-requiredAmount1);
        }
        if (requiredAmount1 > 0) {
            amountMaximum = (uint256(requiredAmount1) * _limitPrice) / 1e12;
            buffer0 = amountMaximum - uint256(requiredAmount0);
        }
    }
    */

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

    function showCurrentTick() internal {
        (, int24 tick, , , , , ) = uniPool.slot0();
        console.log(6, uint256(tick));
    }

    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = uniPool.slot0();
    }

    /**
     * option size -> liquidity
     */
    /*
    function getLiquidityForOptionAmount(bytes32 _rangeId, uint256 _amount) public view returns (uint128) {
        DataType.PerpStatus memory range = pool.getRange(_rangeId);

        return getLiquidityForOptionAmount(range.lowerTick, range.upperTick, _amount);
    }

    function getLiquidityForOptionAmount(int24 lower, int24 upper, uint256 _amount) public view returns (uint128) {
        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(
            pool.isMarginZero(),
            _amount,
            lower,
            lower,
            upper
        );

        return liquidity;
    }

    function getTokenAmountsToDepositLPT(int24 lower, int24 upper, uint256 _amount) public view
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )    
    {
        return LPTMath.getLiquidityAndAmountToDeposit(
            pool.isMarginZero(),
            _amount,
            pool.getSqrtPrice(),
            lower,
            upper
        );
    }
    */

    function getSqrtPriceRange(int24 _slippageTolerance)
        internal
        view
        returns (uint160 lowerSqrtPrice, uint160 upperSqrtPrice)
    {
        int24 tick = controller.getCurrentTick();

        lowerSqrtPrice = TickMath.getSqrtRatioAtTick(tick - _slippageTolerance);
        upperSqrtPrice = TickMath.getSqrtRatioAtTick(tick + _slippageTolerance);
    }
}
