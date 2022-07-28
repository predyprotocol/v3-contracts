// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./utils/TestDeployer.sol";
import "../src/PredyV3Pool.sol";
import "../src/mocks/MockERC20.sol";

contract DepositTokenTest is TestDeployer, Test {
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
    }

    function testDepositToken(uint256 _a0, uint256 _a1) public {
        vm.assume(_a0 < 1e6);
        vm.assume(_a1 < 1e6);

        uint256 margin = 0;
        pool.openPosition(address(depositTokenProduct), boardId, margin, abi.encode(_a0, _a1), _a0, _a1);
    }
}
