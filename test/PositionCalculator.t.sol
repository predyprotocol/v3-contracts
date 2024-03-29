// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../src/libraries/PositionCalculator.sol";

contract PositionCalculatorTest is Test {
    function testCalculateMinSqrtPrice(int256 _lowerTick, int256 _upperTick) public {
        vm.assume(TickMath.MIN_TICK < _lowerTick && _lowerTick < TickMath.MAX_TICK);
        vm.assume(TickMath.MIN_TICK < _upperTick && _upperTick < TickMath.MAX_TICK);
        vm.assume(_lowerTick < _upperTick);

        uint160 minSqrtPrice = PositionCalculator.calculateMinSqrtPrice(int24(_lowerTick), int24(_upperTick));

        assertLe(uint256(TickMath.getSqrtRatioAtTick(int24(_lowerTick))), minSqrtPrice);
        assertLe(minSqrtPrice, uint256(TickMath.getSqrtRatioAtTick(int24(_upperTick))));
    }

    function testCalculateMinLPTValue0() public {
        // isMarginZero false(1 is USDC)
        {
            int24 lower = -202450;
            int24 upper = -200280;

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(lower),
                TickMath.getSqrtRatioAtTick(upper),
                1e18
            );
            uint256 value1 = PositionCalculator.calculateMinLPTValue(DataType.LPT(false, liquidity, lower, upper));
            assertEq(value1, 1799974674);
        }
    }

    function testCalculateMinLPTValue1() public {
        // isMarginZero true(0 is USDC)
        {
            int24 lower = 200280;
            int24 upper = 202450;

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(lower),
                TickMath.getSqrtRatioAtTick(upper),
                1e18
            );
            uint256 value1 = PositionCalculator.calculateMinLPTValue(DataType.LPT(false, liquidity, lower, upper));
            assertEq(value1, 999999999999999457);
        }
    }

    function testCannotCalculateMinDeposit() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        PositionCalculator.PositionCalculatorParams memory position = PositionCalculator.PositionCalculatorParams(
            0,
            0,
            1e18,
            0,
            0,
            1000 * 1e6,
            lpts
        );

        vm.expectRevert(bytes("Out of sqrtprice range"));
        PositionCalculator.calculateMinDeposit(position, uint160(Constants.MIN_SQRT_PRICE - 1), false);

        vm.expectRevert(bytes("Out of sqrtprice range"));
        PositionCalculator.calculateMinDeposit(position, uint160(Constants.MAX_SQRT_PRICE + 1), false);
    }

    function testCannotCalculateMinDepositByTooManyLPTs() public {
        DataType.LPT[] memory lpts = new DataType.LPT[](17);

        PositionCalculator.PositionCalculatorParams memory position = PositionCalculator.PositionCalculatorParams(
            0,
            0,
            1e18,
            0,
            0,
            1000 * 1e6,
            lpts
        );

        vm.expectRevert(bytes("Exceeds max num of LPTs"));
        PositionCalculator.calculateMinDeposit(position, uint160(Constants.MIN_SQRT_PRICE), false);
    }

    function testCalculateMinDepositOfLongToken0(uint160 _sqrtPrice) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, 2823045766959374473400000, Constants.MAX_SQRT_PRICE));

        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        PositionCalculator.PositionCalculatorParams memory position = PositionCalculator.PositionCalculatorParams(
            0,
            0,
            1e18,
            0,
            0,
            1000 * 1e6,
            lpts
        );

        assertGe(PositionCalculator.calculateMinDeposit(position, sqrtPrice, false), 0);
    }

    function testCalculateMinDepositOfBorrowLPT0(uint256 _sqrtPrice) public {
        uint256 sqrtPrice = bound(_sqrtPrice, Constants.MIN_SQRT_PRICE, Constants.MAX_SQRT_PRICE);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202550),
            1e18,
            0
        );

        lpts[0] = DataType.LPT(false, liquidity, -202560, -202550);

        PositionCalculator.PositionCalculatorParams memory position = PositionCalculator.PositionCalculatorParams(
            0,
            0,
            1e18,
            50 * 1e6,
            0,
            0,
            lpts
        );

        assertGe(PositionCalculator.calculateMinDeposit(position, uint160(sqrtPrice), false), 0);
    }

    function testCalculateMinDepositOfBorrowLPT1(uint256 _sqrtPrice) public {
        uint256 sqrtPrice = bound(_sqrtPrice, Constants.MIN_SQRT_PRICE, Constants.MAX_SQRT_PRICE);

        DataType.LPT[] memory lpts = new DataType.LPT[](1);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202560),
            TickMath.getSqrtRatioAtTick(-202550),
            1e18,
            0
        );

        lpts[0] = DataType.LPT(false, liquidity, -202560, -202550);

        PositionCalculator.PositionCalculatorParams memory position = PositionCalculator.PositionCalculatorParams(
            0,
            0,
            0,
            1700 * 1e6,
            0,
            0,
            lpts
        );

        assertGe(PositionCalculator.calculateMinDeposit(position, uint160(sqrtPrice), false), 0);
    }

    function testCalculateMinDepositWith0Debt(uint160 _sqrtPrice) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, 2823045766959374473400000, Constants.MAX_SQRT_PRICE));

        DataType.LPT[] memory lpts = new DataType.LPT[](0);

        PositionCalculator.PositionCalculatorParams memory position = PositionCalculator.PositionCalculatorParams(
            1e16,
            1e10,
            0,
            0,
            0,
            0,
            lpts
        );

        assertEq(PositionCalculator.calculateMinDeposit(position, sqrtPrice, false), 0);
    }

    /*********************************************
     * Test: calculateRequiredCollateralWithDebt *
     *********************************************/

    function testCalculateRequiredCollateralWithDebt1(uint256 _debtValue) public {
        uint256 debtValue = bound(_debtValue, 1, 150000 * 1e6);

        assertLe(PositionCalculator.calculateRequiredCollateralWithDebt(debtValue), 2 * 1e4);
    }

    function testCalculateRequiredCollateralWithDebt2(uint256 _debtValue) public {
        uint256 debtValue = bound(_debtValue, 170000 * 1e6, 900000 * 1e6);

        assertLe(PositionCalculator.calculateRequiredCollateralWithDebt(debtValue), 5 * 1e4);
        assertGe(PositionCalculator.calculateRequiredCollateralWithDebt(debtValue), 2 * 1e4);
    }

    function getLiquidity(
        uint256 _amount,
        int24 _lower,
        int24 _upper
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmounts(
                TickMath.getSqrtRatioAtTick(_lower),
                TickMath.getSqrtRatioAtTick(_lower),
                TickMath.getSqrtRatioAtTick(_upper),
                _amount,
                0
            );
    }

    function testcalculateMinDepositOfCallSpread(uint256 _sqrtPrice) public {
        uint160 sqrtPrice = uint160(bound(_sqrtPrice, Constants.MIN_SQRT_PRICE, Constants.MAX_SQRT_PRICE));

        DataType.LPT[] memory lpts = new DataType.LPT[](2);
        uint128 liquidity0 = getLiquidity(1e18, -202560, -202550);
        uint128 liquidity1 = getLiquidity(1e18, -202520, -202500);

        lpts[0] = DataType.LPT(false, liquidity0, -202560, -202550);
        lpts[1] = DataType.LPT(true, liquidity1, -202520, -202500);

        PositionCalculator.PositionCalculatorParams memory position = PositionCalculator.PositionCalculatorParams(
            0,
            0,
            0,
            50 * 1e6,
            0,
            0,
            lpts
        );

        assertGe(PositionCalculator.calculateMinDeposit(position, sqrtPrice, false), 0);
    }
}
