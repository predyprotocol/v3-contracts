// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "../utils/TestDeployer.sol";

contract TestController is TestDeployer, Test {
    address internal user = vm.addr(uint256(1));
    bool internal isQuoteZero;
    uint256 internal vaultId1;
    uint256 internal vaultId2;

    function setUp() public virtual {
        vm.startPrank(user);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(user, factory);
        vm.warp(block.timestamp + 1 minutes);

        vaultId1 = depositToken(0, 1e10, 5 * 1e18);
        vaultId2 = depositLPT(0, 0, 202500, 202600, 2 * 1e18);

        isQuoteZero = getIsMarginZero();
    }
}
