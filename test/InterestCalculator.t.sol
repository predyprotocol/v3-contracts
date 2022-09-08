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
    address private owner;

    DataType.Context private context;
    DataType.PerpStatus private perpStatus;
    InterestCalculator.DPMParams private dpmParams;
    BaseToken.AccountState private balance0;

    uint128 private liquidity;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
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

        dpmParams.irmParams = InterestCalculator.IRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16);
        dpmParams.premiumParams = InterestCalculator.IRMParams(8000 * 1e6, 30 * 1e16, 10000 * 1e6, 20000 * 1e6);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams(
            address(token0),
            address(token1),
            500,
            perpStatus.lowerTick,
            perpStatus.upperTick,
            ((1e20 * 1005) / 1e12),
            1e20,
            1,
            1,
            owner,
            block.timestamp
        );

        (perpStatus.tokenId, liquidity, , ) = positionManager.mint(params);

        perpStatus.borrowedLiquidity = liquidity / 2;
    }

    function testApplyInterest() public {
        // deposit token
        BaseToken.addCollateral(context.tokenState0, balance0, 1e18, true);
        // borrow token
        BaseToken.addDebt(context.tokenState0, balance0, 1e17);

        // 1 day passed
        vm.warp(block.timestamp + 1 days);

        // update state
        InterestCalculator.applyInterest(
            context,
            InterestCalculator.IRMParams(1e12, 30 * 1e16, 20 * 1e16, 50 * 1e16),
            0
        );

        assertGt(context.tokenState0.collateralScaler, 1e18);
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

    function testupdatePremiumGrowth() public {
        vm.warp(block.timestamp + 5 minutes);

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

        InterestCalculator.updatePremiumGrowth(dpmParams, context, perpStatus, getSqrtPrice());

        assertGt(perpStatus.premiumGrowthForLender, 0);
        assertGt(perpStatus.premiumGrowthForBorrower, 0);
    }

    function testCalculateDailyPremium() public {
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

        swapToSamePrice(owner);

        assertEq(InterestCalculator.calculateInterestRate(dpmParams.premiumParams, 50 * 1e16), 15000000000);

        uint256 dailyPremium = InterestCalculator.calculatePremium(
            dpmParams,
            uniPool,
            perpStatus.lowerTick,
            perpStatus.upperTick,
            50 * 1e16
        );

        assertEq(dailyPremium, 15000000000);

        uint256 premium = InterestCalculator.calculateStableValueFromTotalPremiumValue(
            dailyPremium,
            liquidity - perpStatus.borrowedLiquidity
        );

        assertEq(premium, 141104560991);
        uint128 liquidityForOne = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(perpStatus.upperTick),
            TickMath.getSqrtRatioAtTick(perpStatus.lowerTick),
            TickMath.getSqrtRatioAtTick(perpStatus.upperTick),
            0,
            1e18
        );

        assertEq((liquidityForOne * premium) / 1e18, 374281712);
    }
}
