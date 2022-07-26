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
import "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";


contract PredyV3PoolTest is BaseTestHelper, Test {
    address owner;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        deployContracts();
    }

    function testCreateBoard(uint256 _expiration, uint128 _l) public {
        vm.assume(_l > 1000000000000);
        vm.assume(_l < 100000000000000);

        int24[] memory lowers = new int24[](1);
        int24[] memory uppers = new int24[](1);

        lowers[0] = -207240;
        uppers[0] = -207230;

        pool.createBoard(_expiration, lowers, uppers);
        
        (uint256 a0, uint256 a1) = pool.getTokenAmountsToDepositLPT(0, 0, _l);

        pool.openStrategy(address(depositLPTStrategy), 0, 1000000, abi.encode(0, _l), a0, a1);
    }

    function testCreateBoard2(uint256 _expiration, uint24 _spacing) public {
        vm.assume(_spacing < 2000);

        int24[] memory lowers = new int24[](1);
        int24[] memory uppers = new int24[](1);

        lowers[0] = -207240;
        uppers[0] = -207230 + int24(_spacing * 10);

        pool.createBoard(_expiration, lowers, uppers);
    }

}
