// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../utils/TestDeployer.sol";
import "../../src/ControllerHelper.sol";

import "../../src/satelite/OptionMarket.sol";

contract ControllerHelperTest is TestDeployer, Test {
    address owner;
    bool isQuoteZero;

    OptionMarket private optionMarket;

    uint256 boardId;

    uint256 optionId;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        depositToken(0, 20000 * 1e6, 30 * 1e18);
        depositLPT(0, 0, 202500, 202700, 10 * 1e18);

        isQuoteZero = getIsMarginZero();

        optionMarket = new OptionMarket(address(controller), address(reader), address(token0));

        token0.approve(address(optionMarket), type(uint256).max);

        int24[] memory lowerTicks = new int24[](1);
        int24[] memory upperTicks = new int24[](1);

        lowerTicks[0] = 202500;
        upperTicks[0] = 202700;

        boardId = optionMarket.createBoard(block.timestamp + 1 days, lowerTicks, upperTicks);

        optionMarket.deposit(1000 * 1e6);

        optionId = optionMarket.buy(1, 1e8, 100 * 1e6 * 2, false);
    }

    function testBuy() public {
        uint256 beforeBalance = token0.balanceOf(owner);
        optionMarket.buy(1, 1e8, 100 * 1e6 * 2, false);
        uint256 afterBalance = token0.balanceOf(owner);

        console.log(beforeBalance - afterBalance);
    }

    function testSell() public {
        optionMarket.sell(optionId, 1e8);
    }

    function testCannotExercise() public {
        vm.expectRevert(bytes("OM1"));
        optionMarket.exicise(boardId, 100);
    }

    function testExercise() public {
        swap(owner, false);

        vm.warp(block.timestamp + 1 days + 1 minutes);

        assertFalse(controller.checkLiquidatable(optionMarket.vaultId()));

        optionMarket.exicise(boardId, 100);

        uint256 beforeBalance = token0.balanceOf(owner);
        optionMarket.claimProfit(optionId);
        uint256 afterBalance = token0.balanceOf(owner);

        assertGt(afterBalance, beforeBalance);

        optionMarket.withdraw(1000 * 1e6);
    }

    function testDeposit() public {
        uint256 beforeBalance = optionMarket.balanceOf(owner);
        optionMarket.deposit(1000 * 1e6);
        uint256 afterBalance = optionMarket.balanceOf(owner);

        assertEq(afterBalance - beforeBalance, 1000 * 1e6);
    }
}
