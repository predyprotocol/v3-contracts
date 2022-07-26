// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";
import "./utils/BaseTestHelper.sol";

import "../src/PricingModule2.sol";
import "v3-core/contracts/libraries/TickMath.sol";
import 'v3-core/contracts/libraries/FullMath.sol';


contract PricingModule2Test is BaseTestHelper, Test {
    address owner;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        deployContracts();

        createBoard();

        depositLPT(0, 0, 0, pool.getLiquidityForOptionAmount(0, 0, 1e17));
        depositLPT(0, 0, 1, pool.getLiquidityForOptionAmount(0, 1, 1e17));

        token0.approve(address(swapRouter), 1e24);
        token1.approve(address(swapRouter), 1e24);

        pricingModule.updateDaylyFeeAmount(28 * 1e15);
    }

    function testCalculatePerpFee(
    ) public {
        pricingModule.takeSnapshot(
            uniPool
        );
        pricingModule.takeSnapshotForRange(
            uniPool,
            202560,
            202570
        );

        swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: 500,
            recipient: owner,
            deadline: block.timestamp,
            amountIn: 500000 * 1e6,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));

        swapRouter.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: address(token1),
            tokenOut: address(token0),
            fee: 500,
            recipient: owner,
            deadline: block.timestamp,
            amountIn: 5 * 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        }));

        uint256 a = pricingModule.calculatePerpFee(
            uniPool,
            202560,
            202570
        ) * 2000000000000000 / 1e16;

        assertGt(a, 0);
        assertLt(a, 1e8);
    }
}
