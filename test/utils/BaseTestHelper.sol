// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "../../src/PredyV3Pool.sol";
import "../../src/PricingModule2.sol";
import "../../src/strategies/DepositLPTStrategy.sol";
import "../../src/strategies/BorrowLPTStrategy.sol";
import "../../src/strategies/LevLPStrategy.sol";
import "../../src/strategies/DepositTokenStrategy.sol";
import "../../src/mocks/MockERC20.sol";
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

abstract contract BaseTestHelper {
    IERC20 token0;
    IERC20 token1;
    PredyV3Pool pool;
    SwapRouter swapRouter;
    IUniswapV3Pool uniPool;
    DepositLPTStrategy depositLPTStrategy;
    BorrowLPTStrategy borrowLPTStrategy;
    LevLPStrategy levLPStrategy;
    DepositTokenStrategy depositTokenStrategy;

    function createBoard() public {
        int24[] memory lowers = new int24[](2);
        int24[] memory uppers = new int24[](2);

        // current tick is 202562
        lowers[0] = 202560;
        uppers[0] = 202570;
        lowers[1] = 202580;
        uppers[1] = 202590;

        pool.createBoard(0, lowers, uppers);
    }

    function depositLPT(uint256 _boardId, uint256 _margin, uint128 _index, uint128 _liquidity) public returns(uint256) {
        (uint256 a0, uint256 a1) = pool.getTokenAmountsToDepositLPT(_boardId, _index, _liquidity);
        return pool.openStrategy(address(depositLPTStrategy), _boardId, _margin, abi.encode(_index, _liquidity), a0, a1);
    }

    function swap(address recipient, bool _priceUp) internal {
        uint256 ethAmount;
        uint256 usdcAmount;
        if(_priceUp) {
            usdcAmount = 2000 * 1e6;
            ethAmount = 400 * 1e18;
        }else {
            usdcAmount = 500000 * 1e6;
            ethAmount = 5 * 1e18;
        }
        swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: 500,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: usdcAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));

        swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token1),
            tokenOut: address(token0),
            fee: 500,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: ethAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));
    }

    function showCurrentTick() internal {
        (, int24 tick, , , , , ) = IUniswapV3Pool(address(uniPool)).slot0();
        console.log(6, uint256(tick));
    }
}
