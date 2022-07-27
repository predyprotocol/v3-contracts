// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./utils/TestDeployer.sol";
import "../src/PredyV3Pool.sol";

contract BorrowLPTTest is TestDeployer, Test {
    address owner;
    uint256 margin = 10000000;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.deal(owner, 1000 ether);
        vm.startPrank(owner);

        address factory = deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        deployContracts(owner, factory);

        createBoard();

        depositLPT(0, 0, 0, pool.getLiquidityForOptionAmount(0, 0, 1e17));
        depositLPT(0, 0, 1, pool.getLiquidityForOptionAmount(0, 1, 1e17));
    }

    function testCannotBorrow() public {
        uint128 index = 0;
        uint256 ethAmount = 1 * 1e16;
        uint256 usdcAmount = ethAmount * 2000 / 1e12;

        uint128 liquidity = pool.getLiquidityForOptionAmount(0, index, ethAmount);
        uint256 margin = 0;

        bytes memory data = abi.encode(index, liquidity, TickMath.getSqrtRatioAtTick(202570), 0, usdcAmount);
        vm.expectRevert(bytes("P2"));
        pool.openStrategy(address(borrowLPTStrategy), 0, margin, data, usdcAmount, 0);
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
        uint256 vaultId = pool.openStrategy(address(borrowLPTStrategy), 0, margin, data, usdcAmount, 0);

        vm.warp(block.timestamp + 1 days);
        swap(owner, false);
        
        (, uint256 collateralAmount0, uint256 collateralAmount1, , ) = pool.vaults(vaultId);

        pool.closePositionsInVault(vaultId, 0, false, collateralAmount1, collateralAmount1 * 1000 / 1e12);
    }

    function testBorrow1() public {
        // uint128 liquidity = 2000000000000000;
        // vm.assume(liquidity >= 100000000000000);
        // vm.assume(liquidity <= 300000000000000);
        uint128 index = 1;

        uint256 ethAmount = 1 * 1e16;
        uint256 usdcAmount = ethAmount * 2000 / 1e12;

        uint128 liquidity = pool.getLiquidityForOptionAmount(0, index, ethAmount);

        console.log(2, liquidity);

        bytes memory data = abi.encode(index, liquidity, TickMath.getSqrtRatioAtTick(202570), 0, usdcAmount);
        uint256 vaultId = pool.openStrategy(address(borrowLPTStrategy), 0, margin, data, usdcAmount, 0);

        vm.warp(block.timestamp + 1 days);
        swap(owner, true);

        showCurrentTick();
        
        (, uint256 collateralAmount0, uint256 collateralAmount1, , ) = pool.vaults(vaultId);

        /*
        (uint256 a0, uint256 a1) = pool.getTokenAmountsToDepositLPT(0, index, liquidity);

        console.log(collateralAmount0);
        console.log(collateralAmount1);
        console.log(a0);
        console.log(a1);
        */

        pool.closePositionsInVault(vaultId, 0, true, collateralAmount0, collateralAmount0 * 1e12 / 2000);

    }
}
