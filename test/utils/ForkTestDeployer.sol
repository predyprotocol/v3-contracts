// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./BaseTestHelper.sol";
import "../../src/PredyV3Pool.sol";
import "../../src/PricingModule2.sol";
import "../../src/strategies/DepositLPTStrategy.sol";
import "../../src/strategies/BorrowLPTStrategy.sol";
import "../../src/mocks/MockERC20.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import {UniswapV3Factory } from "v3-core/contracts/UniswapV3Factory.sol";
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import 'v3-periphery/interfaces/external/IWETH9.sol';
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

abstract contract ForkTestDeployer is BaseTestHelper {
    bool isTokenAToken0;

    address constant uniswapFactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address payable constant positionManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address payable constant swapRouterAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    PricingModule2 pricingModule;

    function deployContracts(address owner) public {
        IWETH9 tokenA = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        IERC20 tokenB = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        tokenA.deposit{value: 1000 ether}();
        isTokenAToken0 = uint160(address(tokenA)) < uint160(address(tokenB));

        if(isTokenAToken0) {
            token0 = tokenA;
            token1 = tokenB;
        }else {
            token0 = tokenB;
            token1 = tokenA;
        }

        UniswapV3Factory factory = UniswapV3Factory(uniswapFactoryAddress);
        NonfungiblePositionManager positionManager = NonfungiblePositionManager(positionManagerAddress);
        swapRouter = SwapRouter(swapRouterAddress);
        uniPool = IUniswapV3Pool(factory.getPool(address(token0), address(token1), 500));

        pool = new PredyV3Pool(address(token0), address(token1), !isTokenAToken0, address(positionManager), address(factory), address(swapRouter));

        depositLPTStrategy = new DepositLPTStrategy(pool);
        borrowLPTStrategy = new BorrowLPTStrategy(address(token0), address(token1), pool);

        pool.addStrategy(address(depositLPTStrategy));
        pool.addStrategy(address(borrowLPTStrategy));

        token0.approve(address(pool), 1e24);
        token1.approve(address(pool), 1e24);
        token0.approve(address(swapRouter), 1e24);
        token1.approve(address(swapRouter), 1e24);

        pricingModule = new PricingModule2();
        pool.setPricingModule(address(pricingModule));
        pool.updateVolatility(1e12);
        pricingModule.updateDaylyFeeAmount(28 * 1e15);
    }
}