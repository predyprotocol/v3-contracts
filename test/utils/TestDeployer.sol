// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./BaseTestHelper.sol";
import "../../src/ControllerHelper.sol";
import "../../src/Reader.sol";
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
        // deploy contracts
        weth.mint(owner, 1e25);
        usdc.mint(owner, 1e25);
        weth.mint(address(this), 1e25);
        usdc.mint(address(this), 1e25);

        bool isTokenAToken0 = uint160(address(weth)) < uint160(address(usdc));

        if (isTokenAToken0) {
            token0 = weth;
            token1 = usdc;
        } else {
            token0 = usdc;
            token1 = weth;
        }

        positionManager = new NonfungiblePositionManager(factory, address(weth), address(0));
        swapRouter = new SwapRouter(factory, address(weth));

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

        controller = new ControllerHelper();
        controller.initialize(initializationParam, address(positionManager), factory, address(swapRouter));

        reader = new Reader(controller);

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
        controller.updateYearlyPremiumParams(
            InterestCalculator.IRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16),
            InterestCalculator.IRMParams(7000 * 1e8, 30 * 1e16, 5000 * 1e8, 10000 * 1e8)
        );
    }
}
