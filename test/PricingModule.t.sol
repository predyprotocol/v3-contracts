// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";
import "./utils/TestDeployer.sol";
import "../src/PricingModule.sol";

contract PricingModuleTest is TestDeployer, Test {
    address owner;
    uint256 constant dailyFeeAmount = 28 * 1e15;

    uint256 baseRate = 1e12;
    uint256 kinkRate = 30 * 1e16;
    uint256 slope1 = 20 * 1e16;
    uint256 slope2 = 50 * 1e16;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);

        createBoard();

        uint256 vaultId = depositLPT(0, 0, 0, 0, pool.getLiquidityForOptionAmount(0, 0, 1e17));
        depositLPT(0, vaultId, 0, 1, pool.getLiquidityForOptionAmount(0, 1, 1e17));

        token0.approve(address(swapRouter), 1e24);
        token1.approve(address(swapRouter), 1e24);

        pricingModule.updateDaylyFeeAmount(dailyFeeAmount);

        pricingModule.updateIRMParams(baseRate, kinkRate, slope1, slope2);
    }

    function testCalculateDailyPremium() public {
        pricingModule.takeSnapshotForRange(uniPool, 202560, 202570);

        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: 500,
                recipient: owner,
                deadline: block.timestamp,
                amountIn: 500000 * 1e6,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: 500,
                recipient: owner,
                deadline: block.timestamp,
                amountIn: 5 * 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 dailyPremium = (pricingModule.calculateDailyPremium(uniPool, 202560, 202570) * 2000000000000000) / 1e16;

        assertGt(dailyPremium, 0);
        assertLt(dailyPremium, dailyFeeAmount);
    }

    function testCalculateInterestRate() public {
        uint256 ir0 = pricingModule.calculateInterestRate(0);
        uint256 ir1 = pricingModule.calculateInterestRate(1e16);
        uint256 ir30 = pricingModule.calculateInterestRate(30 * 1e16);
        uint256 ir60 = pricingModule.calculateInterestRate(60 * 1e16);

        assertEq(ir0, 1000000000000);
        assertEq(ir1, 2001000000000000);
        assertEq(ir30, 60001000000000000);
        assertEq(ir60, 210001000000000000);
    }
}
