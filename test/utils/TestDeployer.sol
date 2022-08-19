// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./BaseTestHelper.sol";
import "../../src/Controller.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/libraries/DataType.sol";
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
    function deployContracts(address owner, address factory) public {
        MockERC20 tokenA = new MockERC20("WETH", "WETH", 18);
        MockERC20 tokenB = new MockERC20("USDC", "USDC", 6);

        tokenA.mint(owner, 1e25);
        tokenB.mint(owner, 1e25);
        tokenA.mint(address(this), 1e25);
        tokenB.mint(address(this), 1e25);

        bool isTokenAToken0 = uint160(address(tokenA)) < uint160(address(tokenB));

        if (isTokenAToken0) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        positionManager = new NonfungiblePositionManager(factory, address(tokenA), address(0));
        swapRouter = new SwapRouter(factory, address(tokenA));

        uint160 sqrtPrice = 1982611457661667117153625747031458;

        positionManager.createAndInitializePoolIfNecessary(address(token0), address(token1), 500, sqrtPrice);

        uniPool = IUniswapV3Pool(IUniswapV3Factory(factory).getPool(address(token0), address(token1), 500));
        IUniswapV3PoolActions(uniPool).increaseObservationCardinalityNext(180);

        DataType.InitializationParams memory initializationParam = DataType.InitializationParams(
            500,
            address(token0),
            address(token1),
            true
        );

        controller = new ControllerHelper(initializationParam, address(positionManager), factory, address(swapRouter));

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            initializationParam.token0,
            initializationParam.token1,
            initializationParam.feeTier,
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
        token0.approve(address(controller), 1e24);
        token1.approve(address(controller), 1e24);
        token0.approve(address(swapRouter), 1e24);
        token1.approve(address(swapRouter), 1e24);

        positionManager.mint(params);

        controller.updateIRMParams(InterestCalculator.IRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16));
        controller.updateDRMParams(
            InterestCalculator.IRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16),
            InterestCalculator.IRMParams(7000 * 1e6, 30 * 1e16, 5000 * 1e6, 10000 * 1e6)
        );
    }
}
