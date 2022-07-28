// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./BaseTestHelper.sol";
import "../../src/PredyV3Pool.sol";
import "../../src/PricingModule2.sol";
import "../../src/strategies/DepositLPTStrategy.sol";
import "../../src/strategies/BorrowLPTStrategy.sol";
import "../../src/strategies/LevLPStrategy.sol";
import "../../src/strategies/DepositTokenStrategy.sol";
import "../../src/mocks/MockERC20.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import {UniswapV3Factory } from "v3-core/contracts/UniswapV3Factory.sol";
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import 'v3-periphery/interfaces/external/IWETH9.sol';
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

abstract contract TestDeployer is BaseTestHelper {
    PricingModule2 pricingModule;

    function deployContracts(address owner, address factory) public {
        MockERC20 tokenA = new MockERC20("WETH", "WETH", 18);
        MockERC20 tokenB = new MockERC20("USDC", "USDC", 6);

        tokenA.mint(owner, 1e25);
        tokenB.mint(owner, 1e25);

        bool isTokenAToken0 = uint160(address(tokenA)) < uint160(address(tokenB));

        if(isTokenAToken0) {
            token0 = tokenA;
            token1 = tokenB;
        }else {
            token0 = tokenB;
            token1 = tokenA;
        }

        
        NonfungiblePositionManager positionManager = new NonfungiblePositionManager(factory, address(tokenA), address(0));
        swapRouter = new SwapRouter(factory, address(tokenA));

        uint160 sqrtPrice = 1982611457661667117153625747031458;

        positionManager.createAndInitializePoolIfNecessary(address(token0), address(token1), 500, sqrtPrice);

        uniPool = IUniswapV3Pool(IUniswapV3Factory(factory).getPool(address(token0), address(token1), 500));
        IUniswapV3PoolActions(uniPool).increaseObservationCardinalityNext(180);

        pool = new PredyV3Pool(address(token0), address(token1), !isTokenAToken0, address(positionManager), factory, address(swapRouter));

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            address(token0),
            address(token1),
            500,
            -887220,
            887220,
            (1e20 * 1005 / 1e12),
            1e20,
            1,
            1,
            owner,
            block.timestamp
        );

        token0.approve(address(positionManager), 1e24);
        token1.approve(address(positionManager), 1e24);
        token0.approve(address(pool), 1e24);
        token1.approve(address(pool), 1e24);
        token0.approve(address(swapRouter), 1e24);
        token1.approve(address(swapRouter), 1e24);

        positionManager.mint(params);

        depositLPTStrategy = new DepositLPTStrategy(pool);
        borrowLPTStrategy = new BorrowLPTStrategy(address(token0), address(token1), pool);
        levLPStrategy = new LevLPStrategy(pool);
        depositTokenStrategy = new DepositTokenStrategy(pool);

        pool.addStrategy(address(depositLPTStrategy));
        pool.addStrategy(address(borrowLPTStrategy));
        pool.addStrategy(address(levLPStrategy));
        pool.addStrategy(address(depositTokenStrategy));

        pricingModule = new PricingModule2();
        pool.setPricingModule(address(pricingModule));
        pool.updateVolatility(1e12);
        pricingModule.updateDaylyFeeAmount(28 * 1e15);
    }
}
