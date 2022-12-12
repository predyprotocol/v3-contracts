// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./Setup.t.sol";
import "../../src/Controller.sol";

contract ProtocolInsolvencyTest is TestController {
    bool private isMarginZero;

    function setUp() public override {
        TestController.setUp();

        isMarginZero = getIsMarginZero();
    }

    function supplyToken(uint256 _amount0, uint256 _amount1) internal returns (uint256 vaultId) {
        return supplyOrWithdrawToken(0, _amount0, _amount1, false);
    }

    function withdrawToken(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        supplyOrWithdrawToken(_vaultId, _amount0, _amount1, true);
    }

    function supplyOrWithdrawToken(
        uint256 _vaultId,
        uint256 _amount0,
        uint256 _amount1,
        bool _isWithdraw
    ) internal returns (uint256 vaultId) {
        DataType.PositionUpdate[] memory positionUpdates = new DataType.PositionUpdate[](1);

        positionUpdates[0] = DataType.PositionUpdate(
            _isWithdraw ? DataType.PositionUpdateType.WITHDRAW_TOKEN : DataType.PositionUpdateType.DEPOSIT_TOKEN,
            0,
            false,
            0,
            0,
            0,
            _amount0,
            _amount1
        );

        DataType.OpenPositionOption memory openPositionOption = getOpenPositionParams();

        (vaultId, , ) = controller.updatePosition(
            _vaultId,
            positionUpdates,
            DataType.TradeOption(
                false,
                false,
                false,
                isMarginZero,
                Constants.MARGIN_STAY,
                Constants.MARGIN_STAY,
                0,
                0,
                EMPTY_METADATA
            ),
            openPositionOption
        );
    }

    function getOpenPositionParams() internal view returns (DataType.OpenPositionOption memory) {
        return DataType.OpenPositionOption(getLowerSqrtPrice(), getUpperSqrtPrice(), 100, blockTimestamp());
    }

    function getCloseOptions()
        internal
        view
        returns (DataType.TradeOption memory tradeOption, DataType.ClosePositionOption memory closeOption)
    {
        tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            isMarginZero,
            Constants.MARGIN_USE,
            Constants.MARGIN_STAY,
            Constants.FULL_WITHDRAWAL,
            0,
            EMPTY_METADATA
        );
        closeOption = DataType.ClosePositionOption(
            getLowerSqrtPrice(),
            getUpperSqrtPrice(),
            100,
            1e4,
            blockTimestamp()
        );
    }

    function withdrawAll() internal {
        (DataType.TradeOption memory tradeOption, DataType.ClosePositionOption memory closeOption) = getCloseOptions();

        controller.closeVault(vaultId1, tradeOption, closeOption);
        controller.closeVault(vaultId2, tradeOption, closeOption);

        // withdraw protocol fee
        (, , , uint256 protocolFee0, uint256 protocolFee1) = controller.getContext();

        controller.withdrawProtocolFee(protocolFee0, protocolFee1);
    }

    function testCase1(uint256 _swapAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 5 * 1e18);

        slip(user, true, swapAmount);

        vm.warp(blockTimestamp() + 2 days);

        withdrawAll();

        uint256 balanceUsdc = usdc.balanceOf(address(controller));
        uint256 balanceWeth = weth.balanceOf(address(controller));

        assertLt(balanceUsdc, 10);
        assertLt(balanceWeth, 10);
    }

    function testCase2(uint256 _swapAmount, uint256 _ethAmount) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 5 * 1e18);
        uint256 ethAmount = bound(_ethAmount, 1e17, 100 * 1e18);

        uint256 vaultId = supplyToken(1e10, ethAmount);

        slip(user, true, swapAmount);

        vm.warp(blockTimestamp() + 2 days);

        withdrawToken(vaultId, 1e10, ethAmount);

        withdrawAll();

        uint256 balanceUsdc = usdc.balanceOf(address(controller));
        uint256 balanceWeth = weth.balanceOf(address(controller));

        assertLt(balanceUsdc, 10);
        assertLt(balanceWeth, 10);
    }

    function testCase3(
        uint256 _swapAmount,
        uint256 _elapsedTime,
        uint256 _ethAmount
    ) public {
        uint256 swapAmount = bound(_swapAmount, 1e16, 10 * 1e18);
        uint256 elapsedTime = bound(_elapsedTime, 1 days, 1 weeks);
        uint256 ethAmount = bound(_ethAmount, 1e17, 2 * 1e18);

        uint256 supplyVaultId = supplyToken(1e10, 1e18);

        openShortPut(supplyVaultId, 1, 202500, 202700, 1e18);

        uint256 borrowVaultId = borrowLPT(0, 0, 202600, 202500, 202600, ethAmount, 100 * 1e6);

        slip(user, true, swapAmount);

        vm.warp(blockTimestamp() + elapsedTime);

        (DataType.TradeOption memory tradeOption, DataType.ClosePositionOption memory closeOption) = getCloseOptions();

        controller.closeVault(supplyVaultId, tradeOption, closeOption);
        controller.closeVault(borrowVaultId, tradeOption, closeOption);

        withdrawAll();

        uint256 balanceUsdc = usdc.balanceOf(address(controller));
        uint256 balanceWeth = weth.balanceOf(address(controller));

        assertLt(balanceUsdc, 10);
        assertLt(balanceWeth, 10);
    }
}
