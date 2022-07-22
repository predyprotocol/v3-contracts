// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../src/PredyV3Pool.sol";
import "../src/mocks/MockERC20.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import {UniswapV3Factory } from "v3-core/contracts/UniswapV3Factory.sol";
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";


contract PredyV3PoolTest is Test {
    MockERC20 token0;
    MockERC20 token1;
    PredyV3Pool pool;
    SwapRouter swapRouter;
    address owner;

    function setUp() public {
        owner = msg.sender;
        // vm.startPrank(owner);

        MockERC20 tokenA = new MockERC20("WETH", "WETH", 18);
        MockERC20 tokenB = new MockERC20("USDC", "USDC", 6);
        bool isTokenAToken0 = uint160(address(tokenA)) < uint160(address(tokenB));

        if(isTokenAToken0) {
            token0 = tokenA;
            token1 = tokenB;
        }else {
            token0 = tokenB;
            token1 = tokenA;
        }

        token0.mint(owner, 1e25);
        token1.mint(owner, 1e25);
        token0.mint(address(this), 1e25);
        token1.mint(address(this), 1e25);

        UniswapV3Factory factory = new UniswapV3Factory();
        NonfungiblePositionManager positionManager = new NonfungiblePositionManager(address(factory), address(tokenA), address(0));
        swapRouter = new SwapRouter(address(factory), address(tokenA));

        uint160 sqrtPrice = isTokenAToken0 ? 2499174338360388442220824251634492 : 2511670210052190384431928;

        positionManager.createAndInitializePoolIfNecessary(address(token0), address(token1), 500, sqrtPrice);

        IUniswapV3PoolActions uniPool = IUniswapV3PoolActions(factory.getPool(address(token0), address(token1), 500));
        uniPool.increaseObservationCardinalityNext(180);
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(address(uniPool)).slot0();

        console.log(sqrtPriceX96);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            address(token0),
            address(token1),
            500,
            -887220,
            887220,
            isTokenAToken0 ? 1e20 : (1e20 * 1005 / 1e12),
            isTokenAToken0 ? (1e20 * 1005 / 1e12) : 1e20,
            1,
            1,
            owner,
            block.timestamp
        );

        token0.approve(address(positionManager), 1e24);
        token1.approve(address(positionManager), 1e24);

        console.log(owner);
        console.log(token0.balanceOf(owner));
        console.log(token0.allowance(owner, address(positionManager)));

        (uint256 amount0, , , ) = positionManager.mint(params);

        //pool = new PredyV3Pool(address(token0), address(token1), !isTokenAToken0, address(positionManager), address(factory), address(swapRouter));
    }

    function testCreateBoard(uint256 _expiration) public {

        int24[] memory lowers = new int24[](1);
        int24[] memory uppers = new int24[](1);

        lowers[0] = -207240;
        uppers[0] = -207230;

        // vm.startPrank(owner);
        token0.approve(address(pool), 1e24);
        token1.approve(address(pool), 1e24);
        pool.createBoard(_expiration, lowers, uppers);
    }
}
