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

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.deal(owner, 1000 ether);
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);

        createBoard();

        depositLPT(0, 0, rangeIds[0], pool.getLiquidityForOptionAmount(rangeIds[0], 1e17));
        depositLPT(0, 0, rangeIds[1], pool.getLiquidityForOptionAmount(rangeIds[1], 1e17));
    }

    function testCannotBorrow() public {
        uint256 ethAmount = 1 * 1e16;

        uint256 margin = 0;

        (bytes memory data,
        uint256 buffer0,
        uint256 buffer1) = preBorrowLPT(rangeIds[0], ethAmount, true, 2000);
        
        vm.expectRevert(bytes("P2"));
        pool.openPosition(0, margin, false, data, buffer0, buffer1);
    }

    function testBorrow0() public {
        uint256 ethAmount = 1 * 1e16;

        uint256 vaultId = borrowLPT(0, 50000000, rangeIds[0], 1e16, true, 2000);

        vm.warp(block.timestamp + 1 minutes);
        swap(owner, false);

        pool.closePositionsInVault(vaultId, false, ethAmount, (ethAmount * 1000) / 1e12);
    }

    function testBorrow1() public {
        uint256 ethAmount = 1 * 1e16;
        uint256 usdcAmount = (ethAmount * 2000) / 1e12;

        uint256 vaultId = borrowLPT(0, 50000000, rangeIds[1], 1e16, false, 2000);

        vm.warp(block.timestamp + 1 minutes);
        swap(owner, true);

        pool.closePositionsInVault(vaultId, true, usdcAmount, (usdcAmount * 1e12) / 2000);
    }
}