// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "../../src/PredyV3Pool.sol";
import "../../src/PricingModule2.sol";
import "../../src/strategies/DepositLptStrategy.sol";
import "../../src/strategies/BorrowLptStrategy.sol";
import "../../src/mocks/MockERC20.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import {UniswapV3Factory } from "v3-core/contracts/UniswapV3Factory.sol";
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import 'v3-periphery/interfaces/external/IWETH9.sol';
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";

abstract contract BaseTestHelper {
    bool isTokenAToken0;
    IERC20 token0;
    IERC20 token1;
    PredyV3Pool pool;
    SwapRouter swapRouter;
    address uniswapFactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    IUniswapV3Pool uniPool;
    DepositLptStrategy depositLPTStrategy;
    BorrowLptStrategy borrowLptStrategy;
    PricingModule2 pricingModule;

    function deployContracts() public {
        IWETH9 tokenA = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 tokenB = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        tokenA.deposit{value: 2 ether}();
        isTokenAToken0 = uint160(address(tokenA)) < uint160(address(tokenB));

        if(isTokenAToken0) {
            token0 = tokenA;
            token1 = tokenB;
        }else {
            token0 = tokenB;
            token1 = tokenA;
        }

        //token0.mint(owner, 1e25);
        //token1.mint(owner, 1e25);
        //token0.mint(address(this), 1e25);
        //token1.mint(address(this), 1e25);

        UniswapV3Factory factory = UniswapV3Factory(uniswapFactoryAddress);
        NonfungiblePositionManager positionManager = NonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        swapRouter = SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        /*
        uint160 sqrtPrice = isTokenAToken0 ? 2499174338360388442220824251634492 : 2511670210052190384431928;

        positionManager.createAndInitializePoolIfNecessary(address(token0), address(token1), 500, sqrtPrice);
        */

        uniPool = IUniswapV3Pool(factory.getPool(address(token0), address(token1), 500));
        // uniPool.increaseObservationCardinalityNext(180);

        // (, int24 tick, , , , , ) = IUniswapV3Pool(address(uniPool)).slot0();

        // console.log(6, uint256(tick));

        pool = new PredyV3Pool(address(token0), address(token1), !isTokenAToken0, address(positionManager), address(factory), address(swapRouter));

        depositLPTStrategy = new DepositLptStrategy(pool);
        borrowLptStrategy = new BorrowLptStrategy(address(token0), address(token1), pool);

        pool.addStrategy(address(depositLPTStrategy));
        pool.addStrategy(address(borrowLptStrategy));

        token0.approve(address(pool), 1e24);
        token1.approve(address(pool), 1e24);
        token0.approve(address(swapRouter), 1e24);
        token1.approve(address(swapRouter), 1e24);

        pricingModule = new PricingModule2();
        pool.setPricingModule(address(pricingModule));
        pool.updateVolatility(1e12);
        pricingModule.updateDaylyFeeAmount(28 * 1e15);
    }

    function createBoard() public {
        int24[] memory lowers = new int24[](2);
        int24[] memory uppers = new int24[](2);

        // current tick is 202562
        lowers[0] = 202560;
        uppers[0] = 202570;
        lowers[1] = 202760;
        uppers[1] = 202770;

        pool.createBoard(0, lowers, uppers);
    }

    function depositLPT(uint256 _boardId, uint256 _margin, uint128 _index, uint128 _liquidity) public {
        (uint256 a0, uint256 a1) = pool.getTokenAmountsToDepositLPT(_boardId, _index, _liquidity);
        pool.openStrategy(address(depositLPTStrategy), _boardId, _margin, abi.encode(_index, _liquidity), a0, a1);
    }

    function swap(address recipient) internal {
        swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: 500,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: 500000 * 1e6,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));

        swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token1),
            tokenOut: address(token0),
            fee: 500,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: 5 * 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));
    }
}