//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Initializable} from "@openzeppelin/contracts/proxy/Initializable.sol";
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
import {BaseToken} from "./libraries/BaseToken.sol";
import "./libraries/DataType.sol";
import "./libraries/VaultLib.sol";
import "./libraries/PredyMath.sol";
import "./libraries/PositionUpdater.sol";
import "./libraries/PositionCalculator.sol";
import "./libraries/InterestCalculator.sol";
import "./Constants.sol";

import "forge-std/console.sol";

/**
 * Error Codes
 * P1: caller must be vault owner
 * P2: caller must be vault owner
 * P3: must not be liquidatable
 * P4: must be liquidatable
 * P5: no enough token0
 * P6: no enough token1
 * P7: debt must be 0
 */
contract Controller is IController, Constants, Initializable {
    using BaseToken for BaseToken.TokenState;
    using SafeMath for uint256;
    using SafeMath for uint128;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using VaultLib for DataType.Vault;

    uint256 public oraclePeriod;

    uint256 public lastTouchedTimestamp;

    mapping(bytes32 => DataType.PerpStatus) private ranges;

    uint256 public vaultIdCount;

    mapping(uint256 => DataType.Vault) public vaults;

    DataType.Context public context;
    InterestCalculator.IRMParams private irmParams;
    InterestCalculator.DPMParams private dpmParams;

    address public operator;

    event VaultCreated(uint256 vaultId, address owner);

    modifier onlyOperator() {
        require(operator == msg.sender, "caller must be operator");
        _;
    }

    modifier onlyVaultOwner(uint256 _vaultId) {
        require(vaults[_vaultId].owner == msg.sender, "P1");
        _;
    }

    constructor(
        DataType.InitializationParams memory _initializationParams,
        address _positionManager,
        address _factory,
        address _swapRouter
    ) {
        context.feeTier = _initializationParams.feeTier;
        context.token0 = _initializationParams.token0;
        context.token1 = _initializationParams.token1;
        context.isMarginZero = _initializationParams.isMarginZero;
        context.positionManager = _positionManager;
        context.swapRouter = _swapRouter;

        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: context.token0,
            token1: context.token1,
            fee: context.feeTier
        });

        context.uniswapPool = PoolAddress.computeAddress(_factory, poolKey);

        vaultIdCount = 1;

        ERC20(context.token0).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token1).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token0).approve(address(_swapRouter), type(uint256).max);
        ERC20(context.token1).approve(address(_swapRouter), type(uint256).max);

        context.tokenState0.initialize();
        context.tokenState1.initialize();

        lastTouchedTimestamp = block.timestamp;

        operator = msg.sender;

        oraclePeriod = 1 minutes;
    }

    function setOperator(address _newOperator) external onlyOperator {
        operator = _newOperator;
    }

    function setOperator(uint256 _oraclePeriod) external onlyOperator {
        oraclePeriod = _oraclePeriod;
    }

    function updateIRMParams(InterestCalculator.IRMParams memory _irmParams) external onlyOperator {
        irmParams = _irmParams;
    }

    function updateDRMParams(
        InterestCalculator.IRMParams memory _irmParams,
        InterestCalculator.IRMParams memory _premiumParams
    ) external onlyOperator {
        dpmParams.irmParams = _irmParams;
        dpmParams.premiumParams = _premiumParams;
    }

    // User API
    /**
     * @notice Update position in a vault.
     * @param _vaultId vault id
     * @param _positionUpdates parameters to update position
     * @param _buffer0 max amount of token0 to send
     * @param _buffer1 max amount of token1 to send
     */
    function updatePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _buffer0,
        uint256 _buffer1,
        DataType.TradeOption memory _tradeOption
    ) public override returns (uint256 vaultId) {
        applyPerpFee(_vaultId);

        DataType.Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId, _tradeOption.quoterMode);

        if (_buffer0 > 0) {
            TransferHelper.safeTransferFrom(context.token0, msg.sender, address(this), _buffer0);
        }
        if (_buffer1 > 0) {
            TransferHelper.safeTransferFrom(context.token1, msg.sender, address(this), _buffer1);
        }

        // update position
        (int256 requiredAmount0, int256 requiredAmount1) = PositionUpdater.updatePosition(
            vault,
            context,
            ranges,
            _positionUpdates,
            _tradeOption
        );

        if (_tradeOption.quoterMode) {
            revertRequiredAmounts(requiredAmount0, requiredAmount1);
        }

        require(!_checkLiquidatable(vaultId), "P3");

        require(int256(_buffer0) >= requiredAmount0, "P5");
        require(int256(_buffer1) >= requiredAmount1, "P6");

        if (int256(_buffer0) > requiredAmount0) {
            TransferHelper.safeTransfer(context.token0, msg.sender, uint256(int256(_buffer0).sub(requiredAmount0)));
        }
        if (int256(_buffer1) > requiredAmount1) {
            TransferHelper.safeTransfer(context.token1, msg.sender, uint256(int256(_buffer1).sub(requiredAmount1)));
        }
    }

    function _reducePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _penaltyAmount,
        bool _swapAnyway
    ) internal returns (uint256 penaltyAmount) {
        applyPerpFee(_vaultId);

        DataType.Vault storage vault = vaults[_vaultId];

        // reduce debt
        (int256 surplusAmount0, int256 surplusAmount1) = PositionUpdater.updatePosition(
            vault,
            context,
            ranges,
            _positionUpdates,
            // reduce only
            DataType.TradeOption(true, _swapAnyway, false, context.isMarginZero)
        );
        surplusAmount0 = -surplusAmount0;
        surplusAmount1 = -surplusAmount1;

        require(0 <= surplusAmount0, "P5");
        require(0 <= surplusAmount1, "P6");

        if (context.isMarginZero) {
            (surplusAmount0, penaltyAmount) = PredyMath.subReward(surplusAmount0, _penaltyAmount);
        } else {
            (surplusAmount1, penaltyAmount) = PredyMath.subReward(surplusAmount1, _penaltyAmount);
        }

        if (0 < surplusAmount0) {
            context.tokenState0.addCollateral(vault.balance0, uint256(surplusAmount0), false);
        }
        if (0 < surplusAmount1) {
            context.tokenState1.addCollateral(vault.balance1, uint256(surplusAmount1), false);
        }
    }

    /**
     * @notice Anyone can liquidates the vault if its required collateral value is positive.
     * @param _vaultId vault id
     * @param _positionUpdates parameters to update position
     */
    function liquidate(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        bool _swapAnyway
    ) public override {
        applyPerpFee(_vaultId);

        // check liquidation
        require(_checkLiquidatable(_vaultId), "P4");

        (uint160 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), oraclePeriod);

        // calculate penalty
        uint256 debtValue = vaults[_vaultId].getDebtPositionValue(ranges, context, sqrtPrice);

        // close position
        uint256 penaltyAmount = _reducePosition(_vaultId, _positionUpdates, debtValue / 200, _swapAnyway);

        require(vaults[_vaultId].getDebtPositionValue(ranges, context, sqrtPrice) == 0, "P7");

        sendReward(msg.sender, penaltyAmount);
    }

    /**
     * @notice Contract owner can close positions
     * @param _data vaults data to close position
     */
    function forceClose(bytes[] memory _data) external onlyOperator {
        for (uint256 i = 0; i < _data.length; i++) {
            (uint256 vaultId, DataType.PositionUpdate[] memory _positionUpdates) = abi.decode(
                _data[i],
                (uint256, DataType.PositionUpdate[])
            );

            applyPerpFee(vaultId);

            _reducePosition(vaultId, _positionUpdates, 0, false);
        }
    }

    // Getter Functions

    function getIsMarginZero() external view returns (bool) {
        return context.isMarginZero;
    }

    function getRange(bytes32 _rangeId) external view returns (DataType.PerpStatus memory) {
        return ranges[_rangeId];
    }

    /**
     * @notice Returns the flag whether a vault can be liquidated or not.
     * @param _vaultId vault id
     */
    function checkLiquidatable(uint256 _vaultId) external returns (bool) {
        applyPerpFee(_vaultId);

        return _checkLiquidatable(_vaultId);
    }

    /**
     * @notice Returns collateral value and debt value.
     * @param _vaultId vault id
     */
    function getVaultStatus(uint256 _vaultId) external returns (uint256, uint256) {
        uint160 sqrtPriceX96 = getSqrtPrice();

        applyPerpFee(_vaultId);

        (uint256 collateralValue, uint256 debtValue) = getPositionValue(_vaultId, sqrtPriceX96);

        return (collateralValue, debtValue);
    }

    function getVault(uint256 _vaultId) external view returns (DataType.Vault memory) {
        return vaults[_vaultId];
    }

    // Private Functions

    function _checkLiquidatable(uint256 _vaultId) internal view returns (bool) {
        (uint160 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), oraclePeriod);

        // calculate value using TWAP price
        int256 requiredCollateral = PositionCalculator.calculateRequiredCollateral(
            _getPosition(_vaultId),
            sqrtPrice,
            context.isMarginZero
        );

        return requiredCollateral > 0;
    }

    function createOrGetVault(uint256 _vaultId, bool _quoterMode)
        internal
        returns (uint256 vaultId, DataType.Vault storage)
    {
        if (_vaultId == 0) {
            vaultId = vaultIdCount;
            vaultIdCount++;

            vaults[vaultId].vaultId = vaultId;
            vaults[vaultId].owner = msg.sender;

            emit VaultCreated(vaultId, vaults[vaultId].owner);
        } else {
            vaultId = _vaultId;
            require(vaults[vaultId].owner == msg.sender || _quoterMode, "P2");
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
        DataType.Vault storage vault = vaults[_vaultId];

        // calculate fee for perps
        for (uint256 i = 0; i < vault.lpts.length; i++) {
            InterestCalculator.applyDailyPremium(dpmParams, context, ranges[vault.lpts[i].rangeId], getSqrtPrice());
        }

        lastTouchedTimestamp = InterestCalculator.applyInterest(context, irmParams, lastTouchedTimestamp);

        PositionUpdater.collectFeeAndPremium(context, vault, ranges);
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

    function getCurrentTick() external view returns (int24 tick) {
        (, tick, , , , , ) = IUniswapV3Pool(context.uniswapPool).slot0();
    }

    /**
     * Gets Time Weighted Average Price of underlying token by margin token.
     */
    function getTWAP() external view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(context.isMarginZero, getTWAPSqrtPrice());
    }

    function getTWAPSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), oraclePeriod);
    }

    /**
     * returns collateral and debt value scaled by margin token's decimal
     */
    function getPositionValue(uint256 _vaultId, uint160 _sqrtPrice) internal view returns (uint256, uint256) {
        DataType.Vault memory vault = vaults[_vaultId];

        return (
            vault.getCollateralPositionValue(ranges, context, _sqrtPrice),
            vault.getDebtPositionValue(ranges, context, _sqrtPrice)
        );
    }

    function getPosition(uint256 _vaultId) public returns (DataType.Position memory position) {
        applyPerpFee(_vaultId);

        return _getPosition(_vaultId);
    }

    function _getPosition(uint256 _vaultId) internal view returns (DataType.Position memory position) {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getPosition(ranges, context);
    }

    function revertRequiredAmounts(int256 _requiredAmount0, int256 _requiredAmount1) internal pure {
        assembly {
            let ptr := mload(0x20)
            mstore(ptr, _requiredAmount0)
            mstore(add(ptr, 0x20), _requiredAmount1)
            revert(ptr, 64)
        }
    }
}
