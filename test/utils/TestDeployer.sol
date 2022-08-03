// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./BaseTestHelper.sol";
import "../../src/PredyV3Pool.sol";
import "../../src/PricingModule.sol";
import "../../src/LPTMathModule.sol";
import "../../src/ProductVerifier.sol";
import "../../src/BorrowLPTProduct.sol";
import "../../src/mocks/MockERC20.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import {UniswapV3Factory} from "v3-core/contracts/UniswapV3Factory.sol";
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import "v3-periphery/interfaces/external/IWETH9.sol";
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

abstract contract TestDeployer is BaseTestHelper {
    PricingModule pricingModule;

    function deployContracts(address owner, address factory) public {
        MockERC20 tokenA = new MockERC20("WETH", "WETH", 18);
        MockERC20 tokenB = new MockERC20("USDC", "USDC", 6);

        tokenA.mint(owner, 1e25);
        tokenB.mint(owner, 1e25);

        bool isTokenAToken0 = uint160(address(tokenA)) < uint160(address(tokenB));

        if (isTokenAToken0) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        NonfungiblePositionManager positionManager = new NonfungiblePositionManager(
            factory,
            address(tokenA),
            address(0)
        );
        swapRouter = new SwapRouter(factory, address(tokenA));

        uint160 sqrtPrice = 1982611457661667117153625747031458;

        positionManager.createAndInitializePoolIfNecessary(address(token0), address(token1), 500, sqrtPrice);

        uniPool = IUniswapV3Pool(IUniswapV3Factory(factory).getPool(address(token0), address(token1), 500));
        IUniswapV3PoolActions(uniPool).increaseObservationCardinalityNext(180);

        pool = new PredyV3Pool(
            address(token0),
            address(token1),
            true,
            address(positionManager),
            factory,
            address(swapRouter)
        );

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            address(token0),
            address(token1),
            500,
            -887220,
            887220,
            ((1e20 * 1005) / 1e12),
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

        productVerifier = new ProductVerifier(pool);

        pool.setProductVerifier(address(productVerifier));

        borrowLPTProduct = new BorrowLPTProduct(pool.isMarginZero());

        pricingModule = new PricingModule();
        pool.setPricingModule(address(pricingModule));

        lptMathModule = new LPTMathModule();
        pool.setLPTMathModule(address(lptMathModule));

        pricingModule.updateDaylyFeeAmount(120 * 1e12);
        pricingModule.updateMinCollateralPerLiquidity(1e10);
        pricingModule.updateIRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16);

        swapToSamePrice(owner);
    }
}
