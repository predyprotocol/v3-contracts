// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import "./DataType.sol";
import "./BaseToken.sol";
import "./LPTMath.sol";
import "./LPTStateLib.sol";
import "./Constants.sol";

library InterestCalculator {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using BaseToken for BaseToken.TokenState;

    struct TickSnapshot {
        uint256 lastFeeGrowthInside0X128;
        uint256 lastFeeGrowthInside1X128;
        uint256 lastFeeGrowthGlobal0X128;
        uint256 lastFeeGrowthGlobal1X128;
    }

    struct TickInfo {
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    struct YearlyPremiumParams {
        IRMParams premiumParams;
        IRMParams irmParams;
        mapping(bytes32 => TickSnapshot) snapshots;
    }

    struct IRMParams {
        uint256 baseRate;
        uint256 kinkRate;
        uint256 slope1;
        uint256 slope2;
    }

    // update premium growth
    function updatePremiumGrowthForVault(
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.Context storage _context,
        DataType.PositionUpdate[] memory _positionUpdates,
        YearlyPremiumParams storage _dpmParams,
        uint160 _sqrtPrice
    ) external {
        // calculate fee for ranges that the vault has.
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault memory subVault = _subVaults[_vault.subVaults[i]];

            for (uint256 j = 0; j < subVault.lpts.length; j++) {
                InterestCalculator.updatePremiumGrowth(
                    _dpmParams,
                    _context,
                    _ranges[subVault.lpts[j].rangeId],
                    _sqrtPrice
                );
            }
        }

        // calculate fee for ranges that positionUpdates have.
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdates[i].lowerTick, _positionUpdates[i].upperTick);

            // if range is not initialized, skip calculation.
            if (_ranges[rangeId].tokenId == 0) {
                continue;
            }

            InterestCalculator.updatePremiumGrowth(_dpmParams, _context, _ranges[rangeId], _sqrtPrice);
        }
    }

    // update scaler for reserves
    function applyInterest(
        DataType.Context storage _context,
        IRMParams memory _irmParams,
        uint256 lastTouchedTimestamp
    ) external returns (uint256) {
        if (block.timestamp <= lastTouchedTimestamp) {
            return lastTouchedTimestamp;
        }

        // calculate interest for tokens
        uint256 interest0 = ((block.timestamp - lastTouchedTimestamp) *
            calculateInterestRate(_irmParams, BaseToken.getUtilizationRatio(_context.tokenState0))) / 365 days;

        uint256 interest1 = ((block.timestamp - lastTouchedTimestamp) *
            calculateInterestRate(_irmParams, BaseToken.getUtilizationRatio(_context.tokenState0))) / 365 days;

        _context.accumuratedProtocolFee0 = _context.accumuratedProtocolFee0.add(
            _context.tokenState0.updateScaler(interest0)
        );
        _context.accumuratedProtocolFee1 = _context.accumuratedProtocolFee1.add(
            _context.tokenState1.updateScaler(interest1)
        );

        return block.timestamp;
    }

    function updatePremiumGrowth(
        YearlyPremiumParams storage _params,
        DataType.Context storage _context,
        DataType.PerpStatus storage _perpState,
        uint160 _sqrtPrice
    ) internal {
        if (block.timestamp <= _perpState.lastTouchedTimestamp) {
            return;
        }

        if (_perpState.borrowedLiquidity > 0) {
            uint256 perpUr = LPTStateLib.getPerpUR(_context.positionManager, _perpState);

            uint256 premium = ((block.timestamp - _perpState.lastTouchedTimestamp) *
                calculateYearlyPremium(_params, _context, _perpState, _sqrtPrice, perpUr)) / 365 days;

            _perpState.premiumGrowthForBorrower = _perpState.premiumGrowthForBorrower.add(premium);

            uint256 protocolFeePerLiquidity = PredyMath.mulDiv(premium, Constants.LPT_RESERVE_FACTOR, Constants.ONE);

            _perpState.premiumGrowthForLender = _perpState.premiumGrowthForLender.add(
                PredyMath.mulDiv(
                    premium.sub(protocolFeePerLiquidity),
                    _perpState.borrowedLiquidity,
                    LPTStateLib.getTotalLiquidityAmount(_context.positionManager, _perpState)
                )
            );

            // accumurate protocol fee
            {
                uint256 protocolFee = PredyMath.mulDiv(
                    protocolFeePerLiquidity,
                    _perpState.borrowedLiquidity,
                    Constants.ONE
                );

                if (_context.isMarginZero) {
                    _context.accumuratedProtocolFee0 = _context.accumuratedProtocolFee0.add(protocolFee);
                } else {
                    _context.accumuratedProtocolFee1 = _context.accumuratedProtocolFee1.add(protocolFee);
                }
            }
        }

        takeSnapshotForRange(_params, IUniswapV3Pool(_context.uniswapPool), _perpState.lowerTick, _perpState.upperTick);

        _perpState.lastTouchedTimestamp = block.timestamp;
    }

    function calculateYearlyPremium(
        YearlyPremiumParams storage _params,
        DataType.Context memory _context,
        DataType.PerpStatus storage _perpState,
        uint160 _sqrtPrice,
        uint256 _perpUr
    ) internal view returns (uint256) {
        return
            calculateValueByStableToken(
                _context.isMarginZero,
                calculateRangeVariance(
                    _params,
                    IUniswapV3Pool(_context.uniswapPool),
                    _perpState.lowerTick,
                    _perpState.upperTick,
                    _perpUr
                ),
                calculateInterestRate(_params.irmParams, _perpUr),
                _sqrtPrice,
                _perpState.lowerTick,
                _perpState.upperTick
            );
    }

    function calculateValueByStableToken(
        bool _isMarginZero,
        uint256 _variance,
        uint256 _interestRate,
        uint160 _sqrtPrice,
        int24 _lowerTick,
        int24 _upperTick
    ) internal pure returns (uint256 value) {
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtPrice,
            TickMath.getSqrtRatioAtTick(_lowerTick),
            TickMath.getSqrtRatioAtTick(_upperTick),
            1e18
        );

        uint256 price = LPTMath.decodeSqrtPriceX96(_isMarginZero, _sqrtPrice);

        if (_isMarginZero) {
            value = PredyMath.mulDiv(amount1, price, 1e18).add(amount0);
        } else {
            value = PredyMath.mulDiv(amount0, price, 1e18).add(amount1);
        }

        // value (usd/liquidity)
        value = value.mul(_interestRate).div(1e18);

        // premium = (value of virtual liquidity) * variance / L
        // where `(value of virtual liquidity) = 2 * L * sqrt{price}` and `L = 1e18`.
        // value per 1 underlying token is `2 * sqrt{price/1e18}`
        // so value for `L=1e18` is `2 * sqrt{price/1e18} * L`
        // then
        // `(value of virtual liquidity) = 2 * sqrt{price/1e18}*1e18 = 2 * sqrt{price * 1e18}`
        // Since variance is multiplied by 2 in advance, final formula is below.
        value = value.add((PredyMath.sqrt(price.mul(1e18)).mul(_variance)).div(1e18));
    }

    function calculateRangeVariance(
        YearlyPremiumParams storage _params,
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _utilizationRatio
    ) internal view returns (uint256) {
        uint256 feeGrowthGlobal0X128 = uniPool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = uniPool.feeGrowthGlobal1X128();

        (, int24 tickCurrent, , , , , ) = uniPool.slot0();

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
            getFeeGrowthOutside(uniPool, _lowerTick),
            getFeeGrowthOutside(uniPool, _upperTick),
            _lowerTick,
            _upperTick,
            tickCurrent,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );

        bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

        return
            calculateRatio(
                calculateInterestRate(_params.premiumParams, _utilizationRatio),
                _params.snapshots[key],
                feeGrowthInside0X128,
                feeGrowthInside1X128,
                feeGrowthGlobal0X128,
                feeGrowthGlobal1X128
            );
    }

    function calculateRatio(
        uint256 _variance,
        TickSnapshot memory snapshot,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal pure returns (uint256) {
        uint256 a;
        uint256 b;

        if (feeGrowthGlobal0X128 > snapshot.lastFeeGrowthGlobal0X128) {
            a =
                (Constants.ONE * (feeGrowthInside0X128 - snapshot.lastFeeGrowthInside0X128)) /
                (feeGrowthGlobal0X128 - snapshot.lastFeeGrowthGlobal0X128);
        }

        if (feeGrowthGlobal1X128 > snapshot.lastFeeGrowthGlobal1X128) {
            b =
                (Constants.ONE * (feeGrowthInside1X128 - snapshot.lastFeeGrowthInside1X128)) /
                (feeGrowthGlobal1X128 - snapshot.lastFeeGrowthGlobal1X128);
        }

        return (_variance * (a + b)) / (2 * Constants.ONE);
    }

    function calculateInterestRate(IRMParams memory _irmParams, uint256 _utilizationRatio)
        internal
        pure
        returns (uint256)
    {
        uint256 ir = _irmParams.baseRate;

        if (_utilizationRatio <= _irmParams.kinkRate) {
            ir += (_utilizationRatio * _irmParams.slope1) / Constants.ONE;
        } else {
            ir += (_irmParams.kinkRate * _irmParams.slope1) / Constants.ONE;
            ir += (_irmParams.slope2 * (_utilizationRatio - _irmParams.kinkRate)) / Constants.ONE;
        }

        return ir;
    }

    function takeSnapshotForRange(
        YearlyPremiumParams storage _params,
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) internal {
        uint256 feeGrowthGlobal0X128 = uniPool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = uniPool.feeGrowthGlobal1X128();

        (, int24 tickCurrent, , , , , ) = uniPool.slot0();

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(
            getFeeGrowthOutside(uniPool, _lowerTick),
            getFeeGrowthOutside(uniPool, _upperTick),
            _lowerTick,
            _upperTick,
            tickCurrent,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );

        bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

        _params.snapshots[key].lastFeeGrowthInside0X128 = feeGrowthInside0X128;
        _params.snapshots[key].lastFeeGrowthInside1X128 = feeGrowthInside1X128;
        _params.snapshots[key].lastFeeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        _params.snapshots[key].lastFeeGrowthGlobal1X128 = feeGrowthGlobal1X128;
    }

    function getFeeGrowthOutside(IUniswapV3Pool uniPool, int24 _tickId) internal view returns (TickInfo memory) {
        (, , uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128, , , , bool initialized) = uniPool.ticks(
            _tickId
        );

        require(initialized, "initialized");

        return TickInfo(feeGrowthOutside0X128, feeGrowthOutside1X128);
    }

    function getFeeGrowthInside(
        TickInfo memory lower,
        TickInfo memory upper,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal pure returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        // calculate fee growth below
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;

        if (tickCurrent >= tickLower) {
            // 1808790600867964665724044468235309
            feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
        }

        // calculate fee growth above
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            //  1808790600867964665724044468235309
            feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
}
