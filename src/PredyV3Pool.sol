// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;


import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./libraries/Position.sol";
import "./libraries/Math.sol";

contract PredyV3Pool {
    address public immutable token0;
    address public immutable token1;

    struct PerpOption {
        int256 longLiquidity;
        uint256 cumulativePerpFee;
    }

    struct Tick {
        int128 liquidityNet;
        int256 shortLiquidity;
        mapping(uint256 => PerpOption) perpOptions;
    }

    mapping(int24 => Tick) public ticks;
    mapping(bytes32 => Position.Info) public override positions;

    uint256 currentTickId;
    uint256 currentEpoch;
    uint256 volatility;

    uint256 constant EPOCH_TIME = 8 hours;

    uint256 lastTradeTime = 0;
    uint256 price;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;

        currentTick = 0;

        volatility = 10;
    }

    /**
     * @notice
     * 1/sqrt{p_a} - 1/sqrt{p_b}: p < p_a
     * 1/sqrt{p} - 1/sqrt{p_b}
     * 0: p_b < p
     */
    function addLiquidity(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external {
        require(_tickId < 1024, "P0");

        ticks[_tickId] += _amount;
    }

    /**
     * 0 : p < p_a
     * sqrt{p} - sqrt{p_a}
     * sqrt{p_b} - sqrt{p_a}: p_b < p
     */
    function removeLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount        
    ) external {
        require(_tickId < 1024, "P0");

        ticks[_tickId] -= _amount;
    }

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override returns (uint128 amount0, uint128 amount1) {
    }

    function bindToEpoch(
        uint256 _lptId,
        int24[] _tickIds,
        uint256 _epochId
    ) external {
        // calculate liquidity for tick
        uint256 l = 0;
        ticks[_tickIds[0]].perpOptions[_epochId].shortLiquidity += l;
    }

    function unbindFromEpoch(
        uint256 _lptId,
        uint256 _epochId
    ) external {
        // check epoch has beed ended
        // calculate liquidity for tick
        uint256 l = 0;
        ticks[_tickIds[0]].perpOptions[_epochId].shortLiquidity -= l;

    }

    /**
     * 0: p < p_a
     * 1/sqrt{p_a} - 1/sqrt{p}
     * 1/sqrt{p_a} - 1/sqrt{p_b}: p_b < p
     */
    function mintPerpOption(
        address _recipient,
        int24 _tickId,
        uint256 _epochId,
        uint128 _amount,
        bytes calldata data
    ) external {

    }

    /**
     * sqrt{p_b} - sqrt{p_a} : p < p_a
     * sqrt{p_b} - sqrt{p}
     * 0: p_b < p
     */
    function burnPerpOption(
        int24 _tickId,
        uint128 _amount
    ) external {

    }

    /**
     * swap
     */
    function swap(
        address _recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        // check ticks
        // swap token0 to token1 or token1 to token0
        // calculate perp option
        Tick currentTick = ticks[currentTickId];

        int256 liquidity = currentTick.shortLiquidity - currentTick.longLiquidity[currentEpoch];

        //
        // L = L_short
        // nextSqrtP = L * sqrtPX96 / (L +- amount * sqrtPX96),
        //
        // Δsqrt{p} = Δy/(L_short)
        // Δ1/sqrt{p} = Δx/(L_short)

        // Δy = (sqrt{p} - sqrt{p_a}) * (L_short - L_long)
        // Δx = (1/sqrt{p_a} - 1/sqrt{p}) * (L_short - L_long)
        //

        // Fee
        // cumulativeFeeForLocked += fee * (lock - currentTick.longLiquidity) / (currentTick.shortLiquidity - currentTick.longLiquidity)

        // Fee
        // cumulativeTradeFee += fee * (currentTick.shortLiquidity - lock) / (currentTick.shortLiquidity - currentTick.longLiquidity)

        ERC20(token0).transfer(_recipient, amount0);
    }

    /**
     * @notice trade fee is 5 bps
     * @return tradeFee
     */
    function getTradeFee() internal pure returns(uint256) {
        return 5;
    }
}
