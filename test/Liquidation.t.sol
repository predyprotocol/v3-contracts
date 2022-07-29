// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "./utils/TestDeployer.sol";
import "../src/PredyV3Pool.sol";

contract LiquidationTest is TestDeployer, Test {
    address owner;
    uint256 vaultId;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.deal(owner, 1000 ether);
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);

        createBoard();

        depositLPT(0, 0, 0, 0, pool.getLiquidityForOptionAmount(0, 0, 1e17));
        depositLPT(0, 0, 0, 1, pool.getLiquidityForOptionAmount(0, 1, 1e17));
        vaultId = borrowLPT(0, 0, 50000000, 0, 1e16, true, 2000);

        vm.warp(block.timestamp + 1 hours);
        swap(owner, false);
    }

    function testCannotLiquidate() public {
        uint256 ethAmount = 1 * 1e16;
        uint256 minUsdcAmount = (ethAmount * 1000) / 1e12;

        vm.expectRevert(bytes("vault is not danger"));
        pool.liquidate(vaultId, 0, false, ethAmount, minUsdcAmount);
    }

    function testLiquidate() public {
        uint256 ethAmount = 1 * 1e16;
        uint256 minUsdcAmount = (ethAmount * 1000) / 1e12;

        vm.warp(block.timestamp + 1 hours);
        swap(owner, true);
        vm.warp(block.timestamp + 1 hours);
        swap(owner, false);

        pool.liquidate(vaultId, 0, false, ethAmount, minUsdcAmount);
    }

}
