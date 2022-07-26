// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/BaseTestHelper.sol";
import "../src/PredyV3Pool.sol";
import "../src/strategies/DepositLptStrategy.sol";
import "../src/strategies/BorrowLptStrategy.sol";
import "../src/mocks/MockERC20.sol";
import {NonfungiblePositionManager} from "v3-periphery/NonfungiblePositionManager.sol";
import {UniswapV3Factory } from "v3-core/contracts/UniswapV3Factory.sol";
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import 'v3-periphery/interfaces/external/IWETH9.sol';
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";


contract BorrowLPTTest is BaseTestHelper, Test {
    address owner;
    uint256 margin = 10000000;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        deployContracts();

        createBoard();

        depositLPT(0, 0, 0, pool.getLiquidityForOptionAmount(0, 0, 1e17));
        depositLPT(0, 0, 1, pool.getLiquidityForOptionAmount(0, 1, 1e17));
    }

    function testBorrow0() public {
        // uint128 liquidity = 2000000000000000;
        // vm.assume(liquidity >= 100000000000000);
        // vm.assume(liquidity <= 300000000000000);
        uint128 index = 0;

        uint256 ethAmount = 1 * 1e16;
        uint256 usdcAmount = ethAmount * 2000 / 1e12;

        uint128 liquidity = pool.getLiquidityForOptionAmount(0, index, ethAmount);


        bytes memory data = abi.encode(index, liquidity, TickMath.getSqrtRatioAtTick(202570), 0, usdcAmount);
        uint256 vaultId = pool.openStrategy(address(borrowLptStrategy), 0, margin, data, usdcAmount, 0);

        vm.warp(block.timestamp + 1 days);
        swap(owner);
        
        (, uint256 collateralAmount0, uint256 collateralAmount1, , ) = pool.vaults(vaultId);

        pool.closePositionsInVault(vaultId, 0, false, collateralAmount1, collateralAmount1 * 1000 / 1e12);
    }

    /*
    function testBorrow1() public {
        // uint128 liquidity = 2000000000000000;
        // vm.assume(liquidity >= 100000000000000);
        // vm.assume(liquidity <= 300000000000000);
        uint128 index = 1;

        uint256 ethAmount = 1 * 1e16;
        uint256 usdcAmount = ethAmount * 2000 / 1e12;

        uint128 liquidity = pool.getLiquidityForOptionAmount(0, index, ethAmount);

        console.log(2, liquidity);

        bytes memory data = abi.encode(index, liquidity, true, 0, usdcAmount);
        pool.openStrategy(address(borrowLptStrategy), 0, margin, data, usdcAmount, 0);
    }
    */
}
