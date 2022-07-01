// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/PredyV3Pool.sol";

contract PredyV3PoolTest is Test {
    PredyV3Pool pool;

    function setUp() public {
        pool = new PredyV3Pool();
    }

    function testAddLiquidity(uint256 _tickId, uint256 _amount) public {
        pool.addLiquidity(_tickId, _amount);
    }

    function testRemoveLiquidity(uint256 _tickId, uint256 _amount) public {
        pool.removeLiquidity(_tickId, _amount);
    }

    function testAddAndRemoveLiquidity(uint256 _amount) public {
        for(uint256 i = 5;i < 500;i++) {
            pool.addLiquidity(i, _amount);
        }
        pool.removeLiquidity(5, _amount);
    }

    function testAddPerpOption(uint256 _amount) public {
        pool.addPerpOption(_amount);
    }

    function testRemovePerpOption(uint256 _amount) public {
        pool.removePerpOption(_amount);
    }

    function testSwap(int256 _amount) public {
        pool.swap(_amount);
    }

}
