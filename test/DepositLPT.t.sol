// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/TestDeployer.sol";
import "../src/PredyV3Pool.sol";
import "../src/mocks/MockERC20.sol";

contract DepositLPTTest is TestDeployer, Test {
    address owner;
    uint256 margin = 10000000;
    uint256 vaultId;
    uint256 constant boardId = 0;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.deal(owner, 1000 ether);
        vm.startPrank(owner);

        address factory = deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        deployContracts(owner, factory);

        createBoard();
        vaultId = depositLPT(0, 0, 1, pool.getLiquidityForOptionAmount(0, 1, 1e17));
    }

    function testDepositLPT(uint128 _liquidity) public {
        vm.assume(_liquidity >= 1e10);
        vm.assume(_liquidity <= 1e15);

        uint128 index = 0;
        uint256 margin = 0;

        (uint256 a0, uint256 a1) = pool.getTokenAmountsToDepositLPT(boardId, index, _liquidity);
        pool.openStrategy(address(depositLPTStrategy), boardId, margin, abi.encode(index, _liquidity), a0, a1);
    }

    function testClosePosition() public {
        pool.closePositionsInVault(vaultId, boardId, false, 0, 0);
    }

}
