// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/libraries/LiquidityAmounts.sol";

import "./DataType.sol";
import "./BaseToken.sol";
import "./PriceHelper.sol";
import "./LPTStateLib.sol";
import "./Constants.sol";

/**
 * @title InterestCalculator library
 * @notice Implements the base logic calculating interest rate and premium.
 */
library InterestCalculator {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using BaseToken for BaseToken.TokenState;

    event InterestScalerUpdated(uint256 assetGrowth0, uint256 debtGrowth0, uint256 assetGrowth1, uint256 debtGrowth1);
    event PremiumGrowthUpdated(
        int24 lowerTick,
        int24 upperTick,
        uint256 premiumGrowthForBorrower,
        uint256 premiumGrowthForLender
    );
    event FeeGrowthUpdated(int24 lowerTick, int24 upperTick, uint256 fee0Growth, uint256 fee1Growth);

    struct TickSnapshot {
        uint256 lastSecondsPerLiquidityInside;
        uint256 lastSecondsPerLiquidity;
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
                updatePremiumGrowth(_dpmParams, _context, _ranges[subVault.lpts[j].rangeId], _sqrtPrice);
            }
        }

        // calculate fee for ranges that positionUpdates have.
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdates[i].lowerTick, _positionUpdates[i].upperTick);

            // if range is not initialized, skip calculation.
            if (_ranges[rangeId].lastTouchedTimestamp == 0) {
                continue;
            }

            updatePremiumGrowth(_dpmParams, _context, _ranges[rangeId], _sqrtPrice);
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
        uint256 interest0 = PredyMath.mulDiv(
            block.timestamp - lastTouchedTimestamp,
            calculateInterestRate(_irmParams, BaseToken.getUtilizationRatio(_context.tokenState0)),
            365 days
        );

        uint256 interest1 = PredyMath.mulDiv(
            block.timestamp - lastTouchedTimestamp,
            calculateInterestRate(_irmParams, BaseToken.getUtilizationRatio(_context.tokenState1)),
            365 days
        );

        _context.accumulatedProtocolFee0 = _context.accumulatedProtocolFee0.add(
            _context.tokenState0.updateScaler(interest0)
        );
        _context.accumulatedProtocolFee1 = _context.accumulatedProtocolFee1.add(
            _context.tokenState1.updateScaler(interest1)
        );

        emit InterestScalerUpdated(
            _context.tokenState0.assetGrowth,
            _context.tokenState0.debtGrowth,
            _context.tokenState1.assetGrowth,
            _context.tokenState1.debtGrowth
        );

        return block.timestamp;
    }

    function updatePremiumGrowth(
        YearlyPremiumParams storage _params,
        DataType.Context storage _context,
        DataType.PerpStatus storage _perpState,
        uint160 _sqrtPrice
    ) public {
        if (block.timestamp <= _perpState.lastTouchedTimestamp) {
            return;
        }

        if (_perpState.borrowedLiquidity > 0) {
            uint256 perpUr = LPTStateLib.getPerpUR(address(this), _context.uniswapPool, _perpState);

            (
                uint256 premiumGrowthForBorrower,
                uint256 premiumGrowthForLender,
                uint256 protocolFeePerLiquidity
            ) = calculateLPTBorrowerAndLenderPremium(
                    _params,
                    _context,
                    _perpState,
                    _sqrtPrice,
                    perpUr,
                    (block.timestamp - _perpState.lastTouchedTimestamp)
                );

            _perpState.premiumGrowthForBorrower = _perpState.premiumGrowthForBorrower.add(premiumGrowthForBorrower);

            _perpState.premiumGrowthForLender = _perpState.premiumGrowthForLender.add(premiumGrowthForLender);

            // accumulate protocol fee
            {
                uint256 protocolFee = PredyMath.mulDiv(
                    protocolFeePerLiquidity,
                    _perpState.borrowedLiquidity,
                    Constants.ONE
                );

                if (_context.isMarginZero) {
                    _context.accumulatedProtocolFee0 = _context.accumulatedProtocolFee0.add(protocolFee);
                } else {
                    _context.accumulatedProtocolFee1 = _context.accumulatedProtocolFee1.add(protocolFee);
                }
            }
        }

        takeSnapshot(_params, IUniswapV3Pool(_context.uniswapPool), _perpState.lowerTick, _perpState.upperTick);

        _perpState.lastTouchedTimestamp = block.timestamp;

        emitPremiumGrowthUpdatedEvent(_perpState);
    }

    function emitPremiumGrowthUpdatedEvent(DataType.PerpStatus memory _perpState) internal {
        emit PremiumGrowthUpdated(
            _perpState.lowerTick,
            _perpState.upperTick,
            _perpState.premiumGrowthForBorrower,
            _perpState.premiumGrowthForLender
        );
    }

    /**
     * @notice Collects trade fee and updates fee growth.
     */
    function updateFeeGrowth(
        DataType.Context memory _context,
        DataType.Vault memory _vault,
        mapping(uint256 => DataType.SubVault) storage _subVaults,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        DataType.PositionUpdate[] memory _positionUpdates
    ) external {
        // calculate trade fee for ranges that the vault has
        for (uint256 i = 0; i < _vault.subVaults.length; i++) {
            DataType.SubVault memory subVault = _subVaults[_vault.subVaults[i]];

            for (uint256 j = 0; j < subVault.lpts.length; j++) {
                updateFeeGrowthForRange(_context, _ranges[subVault.lpts[j].rangeId]);
            }
        }

        // calculate trade fee for ranges that trader would open
        for (uint256 i = 0; i < _positionUpdates.length; i++) {
            bytes32 rangeId = LPTStateLib.getRangeKey(_positionUpdates[i].lowerTick, _positionUpdates[i].upperTick);

            updateFeeGrowthForRange(_context, _ranges[rangeId]);
        }
    }

    function updateFeeGrowthForRange(DataType.Context memory _context, DataType.PerpStatus storage _range) public {
        if (_range.lastTouchedTimestamp == 0) {
            return;
        }

        uint256 totalLiquidity = LPTStateLib.getTotalLiquidityAmount(address(this), _context.uniswapPool, _range);

        if (totalLiquidity == 0) {
            emit FeeGrowthUpdated(_range.lowerTick, _range.upperTick, _range.fee0Growth, _range.fee1Growth);

            return;
        }

        {
            // Skip fee collection if utilization ratio is 100%
            uint256 availableLiquidity = LPTStateLib.getAvailableLiquidityAmount(
                address(this),
                _context.uniswapPool,
                _range
            );

            if (availableLiquidity == 0) {
                return;
            }
        }

        // burn 0 amount of LPT to collect trade fee from Uniswap pool.
        IUniswapV3Pool(_context.uniswapPool).burn(_range.lowerTick, _range.upperTick, 0);

        // collect trade fee
        (uint256 collect0, uint256 collect1) = IUniswapV3Pool(_context.uniswapPool).collect(
            address(this),
            _range.lowerTick,
            _range.upperTick,
            type(uint128).max,
            type(uint128).max
        );

        _range.fee0Growth = _range.fee0Growth.add(PredyMath.mulDiv(collect0, Constants.ONE, totalLiquidity));
        _range.fee1Growth = _range.fee1Growth.add(PredyMath.mulDiv(collect1, Constants.ONE, totalLiquidity));

        emit FeeGrowthUpdated(_range.lowerTick, _range.upperTick, _range.fee0Growth, _range.fee1Growth);
    }

    function calculateLPTBorrowerAndLenderPremium(
        YearlyPremiumParams storage _params,
        DataType.Context memory _context,
        DataType.PerpStatus memory _perpState,
        uint160 _sqrtPrice,
        uint256 _perpUr,
        uint256 _elapsed
    )
        public
        view
        returns (
            uint256 premiumGrowthForBorrower,
            uint256 premiumGrowthForLender,
            uint256 protocolFeePerLiquidity
        )
    {
        premiumGrowthForBorrower = PredyMath.mulDiv(
            _elapsed,
            calculateYearlyPremium(_params, _context, _perpState, _sqrtPrice, _perpUr),
            365 days
        );

        protocolFeePerLiquidity = PredyMath.mulDiv(
            premiumGrowthForBorrower,
            Constants.LPT_RESERVE_FACTOR,
            Constants.ONE
        );

        premiumGrowthForLender = PredyMath.mulDiv(
            premiumGrowthForBorrower.sub(protocolFeePerLiquidity),
            _perpUr,
            Constants.ONE
        );
    }

    function calculateYearlyPremium(
        YearlyPremiumParams storage _params,
        DataType.Context memory _context,
        DataType.PerpStatus memory _perpState,
        uint160 _sqrtPrice,
        uint256 _perpUr
    ) internal view returns (uint256) {
        return
            calculateValueByStableToken(
                _context.isMarginZero,
                calculateRangeVariance(_params, IUniswapV3Pool(_context.uniswapPool), _perpState, _perpUr),
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

        value = uint256(PriceHelper.getValue(_isMarginZero, _sqrtPrice, int256(amount0), int256(amount1)));

        // value (usd/liquidity)
        value = value.mul(_interestRate).div(1e18);

        // premium = (value of virtual liquidity) * variance / L
        // where `(value of virtual liquidity) = 2 * L * sqrt{price}` and `L = 1e18`.
        // value per 1 underlying token is `2 * sqrt{price/1e18}`
        // so value for `L=1e18` is `2 * sqrt{price/1e18} * L`
        // then
        // `(value of virtual liquidity) = 2 * sqrt{price/1e18}*1e18 = 2 * sqrt{price * 1e18 / PRICE_SCALER}`
        // Since variance is multiplied by 2 in advance, final formula is below.

        uint256 price = PriceHelper.decodeSqrtPriceX96(_isMarginZero, _sqrtPrice);

        value = value.add((PredyMath.sqrt(price.mul(1e18 / PriceHelper.PRICE_SCALER)).mul(_variance)).div(1e18));
    }

    function calculateRangeVariance(
        YearlyPremiumParams storage _params,
        IUniswapV3Pool uniPool,
        DataType.PerpStatus memory _perpState,
        uint256 _utilizationRatio
    ) internal view returns (uint256) {
        uint256 activeRatio = getRangeActiveRatio(_params, uniPool, _perpState.lowerTick, _perpState.upperTick);

        return calculateInterestRate(_params.premiumParams, _utilizationRatio).mul(activeRatio) / Constants.ONE;
    }

    function getRangeActiveRatio(
        YearlyPremiumParams storage _params,
        IUniswapV3Pool _uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (uint256) {
        (uint256 secondsPerLiquidityInside, uint256 secondsPerLiquidity) = getSecondsPerLiquidity(
            _uniPool,
            _lowerTick,
            _upperTick
        );

        bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

        if (
            secondsPerLiquidityInside <= _params.snapshots[key].lastSecondsPerLiquidityInside ||
            secondsPerLiquidity <= _params.snapshots[key].lastSecondsPerLiquidity
        ) {
            return 0;
        }

        uint256 activeRatio = (secondsPerLiquidityInside - _params.snapshots[key].lastSecondsPerLiquidityInside).mul(
            Constants.ONE
        ) / (secondsPerLiquidity - _params.snapshots[key].lastSecondsPerLiquidity);

        if (activeRatio >= Constants.ONE) {
            return Constants.ONE;
        }

        return activeRatio;
    }

    function takeSnapshot(
        YearlyPremiumParams storage _params,
        IUniswapV3Pool _uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) internal {
        (uint256 secondsPerLiquidityInside, uint256 secondsPerLiquidity) = getSecondsPerLiquidity(
            _uniPool,
            _lowerTick,
            _upperTick
        );

        bytes32 key = keccak256(abi.encodePacked(_lowerTick, _upperTick));

        _params.snapshots[key].lastSecondsPerLiquidityInside = secondsPerLiquidityInside;
        _params.snapshots[key].lastSecondsPerLiquidity = secondsPerLiquidity;
    }

    function getSecondsPerLiquidity(
        IUniswapV3Pool uniPool,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (uint256 secondsPerLiquidityInside, uint256 secondsPerLiquidity) {
        uint32[] memory secondsAgos = new uint32[](1);

        (, uint160[] memory secondsPerLiquidityCumulativeX128s) = uniPool.observe(secondsAgos);

        secondsPerLiquidity = secondsPerLiquidityCumulativeX128s[0];

        (, , , , , , , bool initializedLower) = uniPool.ticks(_lowerTick);
        (, , , , , , , bool initializedUpper) = uniPool.ticks(_upperTick);

        if (initializedLower && initializedUpper) {
            (, secondsPerLiquidityInside, ) = uniPool.snapshotCumulativesInside(_lowerTick, _upperTick);
        }
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
}
