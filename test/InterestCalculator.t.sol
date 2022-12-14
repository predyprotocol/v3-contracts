// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import "../src/libraries/InterestCalculator.sol";
import "./utils/TestDeployer.sol";

contract InterestCalculatorTest is TestDeployer, Test {
    address private owner = vm.addr(uint256(1));

    DataType.Context private context;
    DataType.PerpStatus private perpStatus;
    InterestCalculator.YearlyPremiumParams private ypParams;
    BaseToken.AccountState private balance0;

    uint128 private liquidity;

    function setUp() public {
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        context = getContext();
        perpStatus = getPerpState();
        perpStatus.lowerTick = 202500;
        perpStatus.upperTick = 202800;
        perpStatus.lastTouchedTimestamp = block.timestamp;

        ypParams.irmParams = InterestCalculator.IRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16);
        ypParams.premiumParams = InterestCalculator.IRMParams(4 * 1e16, 30 * 1e16, 16 * 1e16, 100 * 1e16);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            getSqrtPrice(),
            TickMath.getSqrtRatioAtTick(perpStatus.lowerTick),
            TickMath.getSqrtRatioAtTick(perpStatus.upperTick),
            ((1e20 * 1005) / 1e12),
            1e20
        );

        vm.stopPrank();

        IUniswapV3Pool(context.uniswapPool).mint(
            address(this),
            perpStatus.lowerTick,
            perpStatus.upperTick,
            liquidity,
            ""
        );

        vm.startPrank(owner);

        perpStatus.borrowedLiquidity = liquidity;
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        if (amount0 > 0) TransferHelper.safeTransfer(context.token0, msg.sender, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(context.token1, msg.sender, amount1);
    }

    function testApplyInterest() public {
        // deposit token
        BaseToken.addAsset(context.tokenState0, balance0, 1e18, true);
        // borrow token
        BaseToken.addDebt(context.tokenState0, balance0, 1e17, true);

        // 1 day passed
        vm.warp(block.timestamp + 1 days);

        // update state
        InterestCalculator.applyInterest(
            context,
            InterestCalculator.IRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16),
            0
        );

        assertGt(context.tokenState0.assetScaler, 1e18);
        assertGt(context.tokenState0.debtScaler, 1e18);
    }

    function testCalculateInterestRate() public {
        InterestCalculator.IRMParams memory irpParams = InterestCalculator.IRMParams(
            1e12,
            30 * 1e16,
            20 * 1e16,
            50 * 1e16
        );

        uint256 ir0 = InterestCalculator.calculateInterestRate(irpParams, 0);
        uint256 ir1 = InterestCalculator.calculateInterestRate(irpParams, 1e16);
        uint256 ir30 = InterestCalculator.calculateInterestRate(irpParams, 30 * 1e16);
        uint256 ir60 = InterestCalculator.calculateInterestRate(irpParams, 60 * 1e16);

        assertEq(ir0, 1000000000000);
        assertEq(ir1, 2001000000000000);
        assertEq(ir30, 60001000000000000);
        assertEq(ir60, 210001000000000000);
    }

    function testUpdatePremiumGrowth(uint256 _amountIn) public {
        uint256 amountIn = bound(_amountIn, 1, 1e14);

        vm.warp(block.timestamp + 30 minutes);

        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: 500,
                recipient: owner,
                deadline: block.timestamp,
                amountIn: amountIn,
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

        InterestCalculator.updatePremiumGrowth(ypParams, context, perpStatus, getSqrtPrice());

        assertGt(perpStatus.premiumGrowthForLender, 0);
        assertGt(perpStatus.premiumGrowthForBorrower, 0);

        uint256 paidPremium = (perpStatus.premiumGrowthForBorrower * perpStatus.borrowedLiquidity) / 1e18;
        uint256 receivedPremium = (perpStatus.premiumGrowthForLender * (liquidity + perpStatus.borrowedLiquidity)) /
            1e18;

        assertLe(paidPremium, receivedPremium + context.accumulatedProtocolFee0 + 2);
        assertGe(paidPremium, receivedPremium + context.accumulatedProtocolFee0);
    }

    function testCalculateDailyPremium() public {
        InterestCalculator.takeSnapshot(ypParams, uniPool, perpStatus.lowerTick, perpStatus.upperTick);

        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: 500,
                recipient: owner,
                deadline: block.timestamp,
                amountIn: 10000 * 1e6,
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

        vm.warp(block.timestamp + 1 hours);

        assertEq(InterestCalculator.calculateInterestRate(ypParams.premiumParams, 50 * 1e16), 288000000000000000);

        uint256 dailyPremium = InterestCalculator.calculateRangeVariance(ypParams, uniPool, perpStatus, 30 * 1e16);

        assertEq(dailyPremium, 88000000000000000);
    }

    function testCalculateValueByStableTokenMargin0Fuzz(uint256 _sqrtPrice) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, 1e18, 1e40));

        int24 lower = 202000;
        int24 upper = 203000;

        uint256 premium = InterestCalculator.calculateValueByStableToken(true, 16 * 1e16, 0, sqrtPrice, lower, upper);

        assertGt(premium, 0);
    }

    function testCalculateStableValueMargin1Fuzz(uint256 _sqrtPrice) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, 1e18, 1e40));

        int24 lower = -203000;
        int24 upper = -202000;

        uint256 premium = InterestCalculator.calculateValueByStableToken(false, 16 * 1e16, 0, sqrtPrice, lower, upper);

        assertGt(premium, 0);
    }

    function testCalculateValueByStableTokenMargin0() public {
        int24 lower = 202000;
        int24 upper = 203000;

        uint256 premium = InterestCalculator.calculateValueByStableToken(
            true,
            16 * 1e16,
            0,
            TickMath.getSqrtRatioAtTick(upper),
            lower,
            upper
        );

        uint128 liquidityForOne = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(upper),
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            0,
            1e18
        );

        assertEq((liquidityForOne * premium) / 1e18, 5014712907);
    }

    function testCalculateValueByStableTokenMargin1() public {
        int24 lower = -203000;
        int24 upper = -202000;

        uint256 premium = InterestCalculator.calculateValueByStableToken(
            false,
            16 * 1e16,
            0,
            TickMath.getSqrtRatioAtTick(lower),
            lower,
            upper
        );

        uint128 liquidityForOne = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            1e18,
            0
        );

        assertEq((liquidityForOne * premium) / 1e18, 5014712907);
    }

    function testCalculateValueByStableTokenMarginDAI() public {
        int24 lower = -74320;
        int24 upper = -73320;

        uint256 premium = InterestCalculator.calculateValueByStableToken(
            true,
            16 * 1e16,
            0,
            TickMath.getSqrtRatioAtTick(upper),
            lower,
            upper
        );

        uint128 liquidityForOne = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(upper),
            TickMath.getSqrtRatioAtTick(lower),
            TickMath.getSqrtRatioAtTick(upper),
            0,
            1e18
        );

        assertEq((liquidityForOne * premium) / 1e18, 5012694270960490914000);
    }

    function testCalculateValueByStableToken2() public {
        int24 lower = 202000;
        int24 upper = 203000;

        uint256 interestPerl = InterestCalculator.calculateValueByStableToken(
            true,
            0,
            5 * 1e16,
            TickMath.getSqrtRatioAtTick(upper),
            lower,
            upper
        );

        assertEq(interestPerl, 95331869018);
    }
}
