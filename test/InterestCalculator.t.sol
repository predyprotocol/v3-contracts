// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../src/libraries/InterestCalculator.sol";
import "./utils/TestDeployer.sol";

contract InterestCalculatorTest is TestDeployer, Test {

    address owner;

    DataType.Context private context;
    DataType.PerpStatus private perpStatus;
    InterestCalculator.DPMParams private dpmParams;

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
        perpStatus.borrowedLiquidity = 10000000000;

        dpmParams.dailyFeeAmount = 1000000000000;

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

        (perpStatus.tokenId, , ,) = positionManager.mint(params);
    }

    function testApplyInterest() public {
        InterestCalculator.applyInterest(context, 0);

        assertGt(context.tokenState0.collateralScaler, 1e18);
        assertGt(context.tokenState0.debtScaler, 1e18);
    }

    function testApplyDailyPremium() public {
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

        InterestCalculator.applyDailyPremium(dpmParams, getContext(), perpStatus);

        // assertGt(perpStatus.premiumGrowthForLender, 0);
        assertGt(perpStatus.premiumGrowthForBorrower, 0);
    }
}