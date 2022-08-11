// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../src/libraries/PositionUpdator.sol";
import "./utils/TestDeployer.sol";

contract PositionUpdatorTest is TestDeployer, Test {

    address owner;

    DataType.Context private context;
    DataType.Vault private vault;
    mapping(bytes32 => DataType.PerpStatus) private ranges;

    function setUp() public {
        owner = 0x503828976D22510aad0201ac7EC88293211D23Da;
        vm.startPrank(owner);

        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(owner, factory);
        vm.warp(block.timestamp + 1 minutes);

        context = getContext();
    }

    function testUpdatePosition() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](0);
        PositionUpdator.updatePosition(vault, context, ranges, positionUpdates);
    }

    function testUpdatePositionDepositToken() public {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_TOKEN,
            false,
            0,
            0,
            0,
            1e18,
            1e6
        );

        PositionUpdator.updatePosition(vault, context, ranges, positionUpdates);

        assertEq(BaseToken.getCollateralValue(context.tokenState0, vault.balance0), 1e18);
        assertEq(BaseToken.getCollateralValue(context.tokenState1, vault.balance1), 1e6);
    }

}