// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "../utils/PositionUpdaterHelper.sol";

contract TestPositionUpdater is PositionUpdaterHelper, Test {
    DataType.Context internal context;

    DataType.Vault internal vault1;
    DataType.Vault internal vault2;
    DataType.Vault internal vault3;
    DataType.Vault internal vault4;
    DataType.Vault internal vault5;

    mapping(bytes32 => DataType.PerpStatus) internal ranges;

    DataType.TradeOption internal tradeOption;

    function setUp() public virtual {
        address factory = deployCode(
            "../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory"
        );

        deployContracts(address(this), factory);
        vm.warp(block.timestamp + 1 minutes);

        context = getContext();
        tradeOption = DataType.TradeOption(
            false,
            false,
            false,
            context.isMarginZero,
            Constants.MARGIN_STAY,
            Constants.MARGIN_STAY,
            0,
            0,
            EMPTY_METADATA
        );

        // vault1 is empty
        // vault2 has deposited token
        // vault3 has borrowed token
        // vault4 has deposited token with compound option
        // vault5 has borrowed token with compound option
        depositToken(vault2, context, ranges, 2 * 1e6, 2 * 1e18, false);
        borrowToken(vault3, context, ranges, 1e6, 0, false, 100 * 1e6);
        depositToken(vault4, context, ranges, 2 * 1e6, 2 * 1e18, true);
        borrowToken(vault5, context, ranges, 1e6, 1e18, true, -1);
    }

    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        if (amount0 > 0) TransferHelper.safeTransfer(context.token0, msg.sender, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(context.token1, msg.sender, amount1);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (amount0Delta > 0) TransferHelper.safeTransfer(context.token0, msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) TransferHelper.safeTransfer(context.token1, msg.sender, uint256(amount1Delta));
    }
}
