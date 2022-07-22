// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import "forge-std/Test.sol";
import "../src/PredyV3Pool.sol";
import "../src/mocks/MockERC20.sol";
//import "v3-core/contracts/UniswapV3Factory.sol";
//import "v3-periphery/SwapRouter.sol";

contract PredyV3PoolTest is Test {
    MockERC20 token0;
    MockERC20 token1;
    PredyV3Pool pool;
    SwapRouter swapRouter;

    function setUp() public {
        token0 = new MockERC20("WETH", "WETH", 18);
        token1 = new MockERC20("USDC", "USDC", 6);

        UniswapV3Factory factory = new UniswapV3Factory();
        NonfungiblePositionManager positionManager = new NonfungiblePositionManager(factory, token0, address(0));
        swapRouter = new SwapRouter(factory, token0);

        pool = new PredyV3Pool(token0, token1, false, positionManager, swapRouter);


    }

    function testCreateBoard(uint256 _expiration) public {
        pool.createBoard(_expiration, [], []);
    }
}
