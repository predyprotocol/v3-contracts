// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import "../../src/PredyV3Pool.sol";
import "../../src/ProductVerifier.sol";
import "../../src/BorrowLPTProduct.sol";
import "../../src/mocks/MockERC20.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

abstract contract BaseTestHelper {
    IERC20 token0;
    IERC20 token1;
    PredyV3Pool pool;
    SwapRouter swapRouter;
    IUniswapV3Pool uniPool;
    ProductVerifier productVerifier;
    BorrowLPTProduct borrowLPTProduct;

    bytes32[] rangeIds;

    function createBoard() public {
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

        rangeIds = pool.createRanges(lowers, uppers);
    }

    function preDepositTokens(uint256 _amount0, uint256 _amount1)
        public
        returns (
            bytes memory data,
            uint256 buffer0,
            uint256 buffer1
        )
    {
        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](0);

        PositionVerifier.Position memory position = PositionVerifier.Position(_amount0, _amount1, 0, 0, lpts);

        PositionVerifier.Proof[] memory proofs = new PositionVerifier.Proof[](0);

        data = abi.encode(position, proofs, 0);
    }

    function depositLPT(
        uint256 _vaultId,
        uint256 _margin,
        bytes32 _rangeId,
        uint256 _amount
    ) public returns (uint256) {
        uint128 liquidity = getLiquidityForOptionAmount(_rangeId, _amount);
        (uint256 a0, uint256 a1) = pool.getTokenAmountsToDepositLPT(_rangeId, liquidity);

        PositionVerifier.LPT[] memory lpts = new PositionVerifier.LPT[](1);

        {
            PredyV3Pool.PerpStatus memory range = pool.getRange(_rangeId);
            lpts[0] = PositionVerifier.LPT(true, liquidity, range.lower, range.upper);
        }

        PositionVerifier.Position memory position = PositionVerifier.Position(0, 0, 0, 0, lpts);

        PositionVerifier.Proof[] memory proofs = new PositionVerifier.Proof[](1);
        proofs[0] = PositionVerifier.Proof(false, false, 0);

        return pool.openPosition(_vaultId, _margin, true, abi.encode(position, proofs, 0), a0, a1);
    }

    function preBorrowLPT(
        bytes32 _rangeId,
        uint256 _ethAmount,
        bool _isCall,
        uint256 _limitPrice
    )
        internal
        returns (
            bytes memory data,
            uint256 buffer0,
            uint256 buffer1
        )
    {
        {
            PredyV3Pool.PerpStatus memory range = pool.getRange(_rangeId);
            (PositionVerifier.Position memory position, PositionVerifier.Proof[] memory proofs) = borrowLPTProduct
                .createPositionAndProof(_ethAmount, range.lower, range.upper, _isCall ? range.upper : range.lower);

            // calculate USDC amount
            uint256 amountMaximum;

            (amountMaximum, buffer0, buffer1) = getAmountInMaximum(position, pool.geSqrtPrice(), _limitPrice);

            data = abi.encode(position, proofs, amountMaximum);
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
        (bytes memory data, uint256 buffer0, uint256 buffer1) = preBorrowLPT(
            _rangeId,
            _ethAmount,
            _isCall,
            _limitPrice
        );

        return pool.openPosition(_vaultId, _margin, false, data, buffer0, buffer1);
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
        (, int24 tick, , , , , ) = IUniswapV3Pool(address(uniPool)).slot0();
        console.log(6, uint256(tick));
    }

    /**
     * option size -> liquidity
     */
    function getLiquidityForOptionAmount(bytes32 _rangeId, uint256 _amount) public view returns (uint128) {
        PredyV3Pool.PerpStatus memory range = pool.getRange(_rangeId);
        (uint128 liquidity, uint256 amount0, uint256 amount1) = PositionVerifier.getLiquidityAndAmount(
            pool.isMarginZero(),
            _amount,
            range.lower,
            range.lower,
            range.upper
        );

        return liquidity;
    }
}
