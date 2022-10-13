// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../utils/TestDeployer.sol";
import "../../src/ControllerHelper.sol";

import "../../src/satelite/FutureMarket.sol";

contract FutureMarketTest is TestDeployer, Test {
    address owner;
    bool isQuoteZero;

    FutureMarket private futureMarket;

    uint256 private futureVaultId1;
    uint256 private futureVaultId2;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        depositToken(0, 50000 * 1e6, 50 * 1e18);
        uint256 lpVaultId = depositLPT(0, 0, 202000, 202500, 10 * 1e18);
        depositLPT(lpVaultId, 0, 202500, 202700, 10 * 1e18);
        depositLPT(lpVaultId, 0, 202700, 203200, 10 * 1e18);

        isQuoteZero = getIsMarginZero();

        futureMarket = new FutureMarket(address(controller), address(reader), address(token0));

        token0.approve(address(futureMarket), type(uint256).max);

        futureMarket.setRange(9, 202000, 202500);
        futureMarket.setRange(10, 202500, 202700);
        futureMarket.setRange(11, 202700, 203200);

        futureMarket.setCurrentRangeId(10);

        futureMarket.deposit(20000 * 1e6);

        futureVaultId1 = futureMarket.updateMargin(0, 400 * 1e6);
        futureVaultId2 = futureMarket.updateMargin(0, 400 * 1e6);

        futureMarket.trade(futureVaultId1, 1e18);
    }

    /**************************
     *  Test: openPosition    *
     **************************/

    function testOpenLongPosition() public {
        futureMarket.trade(futureVaultId1, 1e18);
    }

    function testOpenShortPosition() public {
        futureMarket.trade(futureVaultId2, -1e18);
    }

    /**************************
     *  Test: closePosition   *
     **************************/

    function testCloseLongPosition() public {
        futureMarket.trade(futureVaultId1, -1e18);
    }

    function testCloseShortPosition() public {
        futureMarket.trade(futureVaultId2, -1e18);
        futureMarket.trade(futureVaultId2, 1e18);
    }

    /**************************
     *  Test: updateMargin    *
     **************************/

    function testDepositMargin() public {
        uint256 beforeBalance = token0.balanceOf(owner);
        futureMarket.updateMargin(futureVaultId1, 100);
        uint256 afterBalance = token0.balanceOf(owner);

        assertEq(beforeBalance - afterBalance, 100);
    }

    function testWithdrawMargin() public {
        uint256 beforeBalance = token0.balanceOf(owner);
        futureMarket.updateMargin(futureVaultId1, -100);
        uint256 afterBalance = token0.balanceOf(owner);

        assertEq(afterBalance - beforeBalance, 100);
    }

    function testCannotWithdrawMargin() public {
        vm.expectRevert(bytes("FM1"));
        futureMarket.updateMargin(futureVaultId1, -300 * 1e6);
    }

    /**************************
     *  Test: liquidationCall *
     **************************/

    function testCannotLiquidationCall() public {
        futureMarket.trade(futureVaultId2, -1e18);

        vm.expectRevert(bytes("FM2"));
        futureMarket.liquidationCall(futureVaultId2);
    }

    function testLiquidationCall() public {
        futureMarket.trade(futureVaultId2, -2 * 1e18);

        slip(owner, true, 10 * 1e18);
        vm.warp(block.timestamp + 10 minutes);

        futureMarket.liquidationCall(futureVaultId2);
    }

    /**************************
     *     Test: deposit      *
     **************************/

    function testDeposit() public {
        uint256 beforeBalance = token0.balanceOf(owner);
        futureMarket.deposit(1000 * 1e6);
        uint256 afterBalance = token0.balanceOf(owner);

        assertEq(beforeBalance - afterBalance, 1000 * 1e6);
    }

    /**************************
     *     Test: withdraw     *
     **************************/

    function testWithdraw() public {
        uint256 beforeBalance = token0.balanceOf(owner);
        futureMarket.withdraw(1000 * 1e6);
        uint256 afterBalance = token0.balanceOf(owner);

        assertEq(afterBalance - beforeBalance, 1000 * 1e6);
    }
}
