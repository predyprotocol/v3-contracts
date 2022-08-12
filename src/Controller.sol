//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@uniswap/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";

import "./interfaces/IController.sol";
import "./interfaces/IPricingModule.sol";
import {BaseToken} from "./libraries/BaseToken.sol";
import "./libraries/DataType.sol";
import "./libraries/VaultLib.sol";
import "./libraries/PredyMath.sol";
import "./libraries/PositionUpdator.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/InterestCalculator.sol";
import "./Constants.sol";


contract Controller is IController, Ownable, Constants {
    using BaseToken for BaseToken.TokenState;
    using SafeMath for uint256;
    using SafeMath for uint128;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using VaultLib for DataType.Vault;

    uint256 public lastTouchedTimestamp;

    mapping(bytes32 => DataType.PerpStatus) private ranges;

    uint256 public vaultIdCount;

    mapping(uint256 => DataType.Vault) public vaults;

    DataType.Context public context;
    InterestCalculator.IRMParams private irmParams;
    InterestCalculator.DPMParams private dpmParams;

    event VaultCreated(uint256 vaultId);

    modifier onlyVaultOwner(uint256 _vaultId) {
        require(vaults[_vaultId].owner == msg.sender);
        _;
    }

    constructor(
        address _token0,
        address _token1,
        bool _isMarginZero,
        address _positionManager,
        address _factory,
        address _swapRouter
    ) {
        context.feeTier = FEE_TIER;
        context.token0 = _token0;
        context.token1 = _token1;
        context.isMarginZero = _isMarginZero;
        context.positionManager = _positionManager;
        context.swapRouter = _swapRouter;

        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({token0: context.token0, token1: context.token1, fee: FEE_TIER});

        context.uniswapPool = PoolAddress.computeAddress(_factory, poolKey);

        vaultIdCount = 1;

        ERC20(context.token0).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token1).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token0).approve(address(_swapRouter), type(uint256).max);
        ERC20(context.token1).approve(address(_swapRouter), type(uint256).max);

        context.tokenState0.initialize();
        context.tokenState1.initialize();

        lastTouchedTimestamp = block.timestamp;
    }

    function updateIRMParams(
        uint256 _base,
        uint256 _kink,
        uint256 _slope1,
        uint256 _slope2
    ) external onlyOwner {
        irmParams.baseRate = _base;
        irmParams.kinkRate = _kink;
        irmParams.slope1 = _slope1;
        irmParams.slope2 = _slope2;
    }

    // User API

    /**
     * @notice Opens new position.
     */
    function updatePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _buffer0,
        uint256 _buffer1
    ) external override returns (uint256 vaultId) {
        applyPerpFee(_vaultId);

        DataType.Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId);

        TransferHelper.safeTransferFrom(context.token0, msg.sender, address(this), _buffer0);
        TransferHelper.safeTransferFrom(context.token1, msg.sender, address(this), _buffer1);

        // update position
        (int256 amount0, int256 amount1) = PositionUpdator.updatePosition(
            vault,
            context,
            ranges,
            _positionUpdates,
            false
        );


        require(!checkLiquidatable(vaultId), "P3");

        require(int256(_buffer0) >= amount0);
        require(int256(_buffer1) >= amount1);

        if (int256(_buffer0) > amount0) {
            TransferHelper.safeTransfer(context.token0, msg.sender, uint256(int256(_buffer0) - amount0));
        }
        if (int256(_buffer1) > amount1) {
            TransferHelper.safeTransfer(context.token1, msg.sender, uint256(int256(_buffer1) - amount1));
        }
    }

    function _reducePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _penaltyAmount0,
        uint256 _penaltyAmount1
    ) internal {
        applyPerpFee(_vaultId);

        DataType.Vault storage vault = vaults[_vaultId];

        // update position
        (int256 amount0, int256 amount1) = PositionUpdator.updatePosition(
            vault,
            context,
            ranges,
            _positionUpdates,
            true
        );

        require(!checkLiquidatable(_vaultId), "P3");

        require(0 >= amount0);
        require(0 >= amount1);

        if (0 > amount0) {
            context.tokenState0.addCollateral(vault.balance0, uint256(-amount0) - _penaltyAmount0, false);
        }
        if (0 > amount1) {
            context.tokenState1.addCollateral(vault.balance1, uint256(-amount1) - _penaltyAmount1, false);
        }
    }

    /**
     * Liquidates if 75% of collateral value is less than debt value.
     */
    function liquidate(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates
    ) external {
        applyPerpFee(_vaultId);

        // check liquidation
        require(checkLiquidatable(_vaultId));

        (uint160 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), 1 minutes);

        // calculate reward
        (uint256 amount0, uint256 amount1) = getDebtPositionAmounts(_vaultId, sqrtPrice);

        // close position
        _reducePosition(_vaultId, _positionUpdates, amount0 / 100, amount1 / 100);

        sendReward(msg.sender, amount0 / 100, amount1 / 100);
    }

    function checkLiquidatable(uint256 _vaultId) internal view returns (bool) {
        (uint160 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), 1 minutes);

        // calculate value using TWAP price
        int256 requiredCollateral = PositionCalculator.calculateRequiredCollateral(getPosition(_vaultId), sqrtPrice, context.isMarginZero);

        return requiredCollateral > 0;
    }

    function forceClose(bytes[] memory _data) external onlyOwner {
        for (uint256 i = 0; i < _data.length; i++) {
            (uint256 vaultId, DataType.PositionUpdate[] memory _positionUpdates) = abi.decode(
                _data[i],
                (uint256,  DataType.PositionUpdate[])
            );

            applyPerpFee(vaultId);

            _reducePosition(vaultId, _positionUpdates, 0, 0);
        }
    }

    // Getter Functions

    function getIsMarginZero() external view returns (bool) {
        return context.isMarginZero;
    }

    function getRange(bytes32 _rangeId) external view returns (DataType.PerpStatus memory) {
        return ranges[_rangeId];
    }

    function getVaultStatus(uint256 _vaultId)
        external
        returns (
            uint256,
            uint256
        )
    {
        uint160 sqrtPriceX96 = getSqrtPrice();

        applyPerpFee(_vaultId);

        (uint256 collateralValue, uint256 debtValue) = getPositionValue(_vaultId, sqrtPriceX96);

        return (collateralValue, debtValue);
    }

    // Private Functions

    function createOrGetVault(uint256 _vaultId) internal returns (uint256 vaultId, DataType.Vault storage) {
        if (_vaultId == 0) {
            vaultId = vaultIdCount;
            vaultIdCount++;
            vaults[vaultId].owner = msg.sender;
            
            emit VaultCreated(vaultId);
        } else {
            vaultId = _vaultId;
            require(vaults[vaultId].owner == msg.sender, "P4");
        }

        return (vaultId, vaults[vaultId]);
    }

    function sendReward(address _liquidator, uint256 _reward) internal {
        TransferHelper.safeTransfer(context.isMarginZero ? context.token0 : context.token1, _liquidator, _reward);
    }

    function sendReward(
        address _liquidator,
        uint256 _reward0,
        uint256 _reward1
    ) internal {
        TransferHelper.safeTransfer(context.token0, _liquidator, _reward0);
        TransferHelper.safeTransfer(context.token1, _liquidator, _reward1);
    }

    function applyPerpFee(uint256 _vaultId) internal {
        DataType.Vault memory vault = vaults[_vaultId];

        // calculate fee for perps
        for (uint256 i = 0; i < vault.lpts.length; i++) {
            InterestCalculator.applyDailyPremium(dpmParams, context, ranges[vault.lpts[i].rangeId]);
        }

        // updateInterest();
        lastTouchedTimestamp = InterestCalculator.applyInterest(context, irmParams, lastTouchedTimestamp);
    }

    function getPerpUR(bytes32 _rangeId) internal view returns (uint256) {
        return PredyMath.mulDiv(ranges[_rangeId].borrowedLiquidity, ONE, getTotalLiquidityAmount(_rangeId));
    }

    function getUR() internal view returns (uint256) {
        if (context.tokenState0.totalDeposited == 0) {
            return ONE;
        }
        return PredyMath.mulDiv(context.tokenState0.totalBorrowed, ONE, context.tokenState0.totalDeposited);
    }

    /**
     * Gets current price of underlying token by margin token.
     */
    function getPrice() external view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(context.isMarginZero, getSqrtPrice());
    }

    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(context.uniswapPool).slot0();
    }

    /**
     * Gets Time Weighted Average Price of underlying token by margin token.
     */
    function getTWAP() external view returns (uint256) {
        (uint256 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), 1 minutes);

        return LPTMath.decodeSqrtPriceX96(context.isMarginZero, sqrtPrice);

    }

    function getTotalLiquidityAmount(bytes32 _rangeId) internal view returns (uint256) {
        (, , , , , , , uint128 liquidity, , , , ) = INonfungiblePositionManager(context.positionManager).positions(ranges[_rangeId].tokenId);

        return liquidity;
    }

    /**
     * returns collateral and debt value scaled by margin token's decimal
     */
    function getPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256, uint256) {
        return (getCollateralPositionValue(_vaultId, _sqrtPrice), getDebtPositionValue(_vaultId, _sqrtPrice));
    }

    function getCollateralPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256) {
        DataType.Vault memory vault = vaults[_vaultId];

        (uint256 collateralAmount0, uint256 collateralAmount1) =  getCollateralPositionAmounts(_vaultId, _sqrtPrice);
        uint256 earnedPremium = vault.getEarnedDailyPremium(ranges);        

        uint256 price = LPTMath.decodeSqrtPriceX96(context.isMarginZero, _sqrtPrice);

        if (context.isMarginZero) {
            return (PredyMath.mulDiv(collateralAmount1, price, ONE) + collateralAmount0 + earnedPremium);
        } else {
            return (PredyMath.mulDiv(collateralAmount0, price, ONE) + collateralAmount1 + earnedPremium);
        }
    }

    function getDebtPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256) {
        DataType.Vault memory vault = vaults[_vaultId];

        (uint256 debtAmount0, uint256 debtAmount1) = getDebtPositionAmounts(_vaultId, _sqrtPrice);
        uint256 paidPremium = vault.getPaidDailyPremium(ranges);        

        uint256 price = LPTMath.decodeSqrtPriceX96(context.isMarginZero, _sqrtPrice);

        if (context.isMarginZero) {
            return (PredyMath.mulDiv(debtAmount1, price, ONE) + debtAmount0 - paidPremium);
        } else {
            return (PredyMath.mulDiv(debtAmount0, price, ONE) + debtAmount1 - paidPremium);
        }
    }


    function getCollateralPositionAmounts(uint256 _vaultId, uint160 _sqrtPrice)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getCollateralPositionAmounts(ranges, context.tokenState0, context.tokenState1, _sqrtPrice);
    }

    function getDebtPositionAmounts(uint256 _vaultId, uint160 _sqrtPrice)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getDebtPositionAmounts(ranges, context.tokenState0, context.tokenState1, _sqrtPrice);
    }

    function getPosition(uint256 _vaultId) public view returns (DataType.Position memory position) {
        DataType.Vault memory vault = vaults[_vaultId];

        DataType.LPT[] memory lpts = new DataType.LPT[](vault.lpts.length);

        for (uint256 i = 0; i < vault.lpts.length; i++) {
            bytes32 rangeId = vault.lpts[i].rangeId;
            DataType.PerpStatus memory range = ranges[rangeId];
            lpts[i] = DataType.LPT(vault.lpts[i].isCollateral, vault.lpts[i].liquidityAmount, range.lowerTick, range.upperTick);
        }

        position = DataType.Position(
            context.tokenState0.getCollateralValue(vault.balance0),
            context.tokenState1.getCollateralValue(vault.balance1),
            context.tokenState0.getDebtValue(vault.balance0),
            context.tokenState1.getDebtValue(vault.balance1),
            lpts
        );
    }

    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }
}
