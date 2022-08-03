// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/TestDeployer.sol";
import "../src/PredyV3Pool.sol";
import "../src/mocks/MockERC20.sol";

contract PredyV3PoolTest is TestDeployer, Test {
    address owner;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);
    }

    /*

    function testCreateRanges() public {
        int24[] memory lowers = new int24[](1);
        int24[] memory uppers = new int24[](1);

        lowers[0] = -207240;
        uppers[0] = -207230;

        pool.createRanges(lowers, uppers);
    }

    function testCreateRanges2(uint24 _spacing) public {
        vm.assume(_spacing < 2000);

        int24[] memory lowers = new int24[](1);
        int24[] memory uppers = new int24[](1);

        lowers[0] = -207240;
        uppers[0] = -207230 + int24(_spacing * 10);

        pool.createRanges(lowers, uppers);
    }
    */
}
