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
import "./libraries/PositionLib.sol";
import "./Constants.sol";

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

    uint256 internal constant ORACLE_PERIOD = 1 minutes;

    uint256 public lastTouchedTimestamp;

    mapping(bytes32 => DataType.PerpStatus) internal ranges;

    uint256 internal vaultIdCount;

    mapping(uint256 => DataType.Vault) internal vaults;
    mapping(uint256 => DataType.SubVault) internal subVaults;

    DataType.Context internal context;
    InterestCalculator.IRMParams public irmParams;
    InterestCalculator.DPMParams public dpmParams;

    address public operator;

    event VaultCreated(uint256 vaultId, address owner);
    event PositionUpdated(uint256 vaultId, int256 a0, int256 a1, uint160 sqrtPrice, DataType.MetaData metadata);

    modifier onlyOperator() {
        require(operator == msg.sender, "caller must be operator");
        _;
    }

    modifier onlyVaultOwner(uint256 _vaultId) {
        require(vaults[_vaultId].owner == msg.sender, "P1");
        _;
    }

    constructor() {}

    function initialize(
        DataType.InitializationParams memory _initializationParams,
        address _positionManager,
        address _factory,
        address _swapRouter
    ) public initializer {
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
        context.nextSubVaultId = 1;

        ERC20(context.token0).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token1).approve(address(_positionManager), type(uint256).max);
        ERC20(context.token0).approve(address(_swapRouter), type(uint256).max);
        ERC20(context.token1).approve(address(_swapRouter), type(uint256).max);

        context.tokenState0.initialize();
        context.tokenState1.initialize();

        lastTouchedTimestamp = block.timestamp;

        operator = msg.sender;
    }

    function setOperator(address _newOperator) external onlyOperator {
        operator = _newOperator;
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
        DataType.TradeOption memory _tradeOption,
        DataType.MetaData memory _metadata
    ) public override returns (uint256 vaultId) {
        if (_buffer0 > 0) {
            TransferHelper.safeTransferFrom(context.token0, msg.sender, address(this), uint256(_buffer0));
        }
        if (_buffer1 > 0) {
            TransferHelper.safeTransferFrom(context.token1, msg.sender, address(this), uint256(_buffer1));
        }

        applyPerpFee(_vaultId, _positionUpdates);

        DataType.Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId, _tradeOption.quoterMode);

        // update position in the vault
        (int256 requiredAmount0, int256 requiredAmount1) = PositionUpdater.updatePosition(
            vault,
            subVaults,
            context,
            ranges,
            _positionUpdates,
            _tradeOption
        );

        if (_tradeOption.quoterMode) {
            revertRequiredAmounts(requiredAmount0, requiredAmount1);
        }

        // check the vault is safe
        require(!_checkLiquidatable(vaultId), "P3");

        require(int256(_buffer0) >= requiredAmount0, "P5");
        require(int256(_buffer1) >= requiredAmount1, "P6");

        if (int256(_buffer0) > requiredAmount0) {
            uint256 amount0 = uint256(int256(_buffer0).sub(requiredAmount0));

            TransferHelper.safeTransfer(context.token0, msg.sender, amount0);
        }
        if (int256(_buffer1) > requiredAmount1) {
            uint256 amount1 = uint256(int256(_buffer1).sub(requiredAmount1));

            TransferHelper.safeTransfer(context.token1, msg.sender, amount1);
        }

        emit PositionUpdated(vaultId, requiredAmount0, requiredAmount1, getSqrtPrice(), _metadata);
    }

    function _reducePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        uint256 _penaltyAmount,
        bool _swapAnyway
    ) internal returns (uint256 penaltyAmount) {
        DataType.Vault storage vault = vaults[_vaultId];

        // reduce position
        (int256 surplusAmount0, int256 surplusAmount1) = PositionUpdater.updatePosition(
            vault,
            subVaults,
            context,
            ranges,
            _positionUpdates,
            // reduce only
            DataType.TradeOption(true, _swapAnyway, false, context.isMarginZero, -2, -2)
        );

        require(0 == surplusAmount0, "P5");
        require(0 == surplusAmount1, "P6");

        if (context.isMarginZero) {
            (vault.marginAmount0, penaltyAmount) = PredyMath.subReward(vault.marginAmount0, _penaltyAmount);
        } else {
            (vault.marginAmount1, penaltyAmount) = PredyMath.subReward(vault.marginAmount1, _penaltyAmount);
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
    ) internal {
        applyPerpFee(_vaultId, _positionUpdates);

        // check liquidation
        require(_checkLiquidatable(_vaultId), "P4");

        (uint160 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), ORACLE_PERIOD);

        // calculate penalty
        uint256 debtValue = vaults[_vaultId].getDebtPositionValue(subVaults, ranges, context, sqrtPrice);

        // close position
        uint256 penaltyAmount = _reducePosition(_vaultId, _positionUpdates, debtValue / 200, _swapAnyway);

        require(vaults[_vaultId].getDebtPositionValue(subVaults, ranges, context, sqrtPrice) == 0, "P7");

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

            applyPerpFee(vaultId, _positionUpdates);

            _reducePosition(vaultId, _positionUpdates, 0, false);
        }
    }

    // Getter Functions

    function getContext()
        external
        view
        returns (
            bool,
            uint256,
            uint256
        )
    {
        return (context.isMarginZero, vaultIdCount, context.nextSubVaultId);
    }

    function getRange(bytes32 _rangeId) external view returns (DataType.PerpStatus memory) {
        return ranges[_rangeId];
    }

    function getAssetStatus()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            BaseToken.getTotalCollateralValue(context.tokenState0),
            BaseToken.getTotalDebtValue(context.tokenState0),
            BaseToken.getUtilizationRatio(context.tokenState0),
            BaseToken.getTotalCollateralValue(context.tokenState1),
            BaseToken.getTotalDebtValue(context.tokenState1),
            BaseToken.getUtilizationRatio(context.tokenState1)
        );
    }

    function getLPTStatus(bytes32 _rangeId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return LPTStateLib.getPerpStatus(context, ranges[_rangeId]);
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
    function getVaultStatus(uint256 _vaultId) external returns (DataType.VaultStatus memory) {
        uint160 sqrtPriceX96 = getSqrtPrice();

        applyPerpFee(_vaultId);

        return vaults[_vaultId].getVaultStatus(subVaults, ranges, context, sqrtPriceX96);
    }

    function getVault(uint256 _vaultId) external view returns (DataType.Vault memory) {
        return vaults[_vaultId];
    }

    function getSubVault(uint256 _subVaultId) external view returns (DataType.SubVault memory) {
        return subVaults[_subVaultId];
    }

    function calculateYearlyPremium(bytes32 _rangeId) external view returns (uint256) {
        return InterestCalculator.calculateYearlyPremium(dpmParams, context, ranges[_rangeId], getSqrtPrice());
    }

    // Private Functions

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

    function _checkLiquidatable(uint256 _vaultId) internal view returns (bool) {
        (uint160 sqrtPrice, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), ORACLE_PERIOD);

        // calculate Min Collateral by using TWAP.
        int256 minCollateral = PositionCalculator.calculateMinCollateral(
            PositionLib.concat(_getPosition(_vaultId)),
            sqrtPrice,
            context.isMarginZero
        );

        return minCollateral > int256(vaults[_vaultId].getMarginValue(context));
    }

    function sendReward(address _liquidator, uint256 _reward) internal {
        TransferHelper.safeTransfer(context.isMarginZero ? context.token0 : context.token1, _liquidator, _reward);
    }

    /**
     * @notice apply interest, premium and trade fee for ranges that the vault has.
     */
    function applyPerpFee(uint256 _vaultId) internal {
        applyPerpFee(_vaultId, new DataType.PositionUpdate[](0));
    }

    /**
     * @notice apply interest, premium and trade fee for ranges that the vault and positionUpdates have.
     */
    function applyPerpFee(uint256 _vaultId, DataType.PositionUpdate[] memory _positionUpdates) internal {
        DataType.Vault memory vault = vaults[_vaultId];

        InterestCalculator.updatePremiumGrowthForVault(
            vault,
            subVaults,
            ranges,
            context,
            _positionUpdates,
            dpmParams,
            getSqrtPrice()
        );

        lastTouchedTimestamp = InterestCalculator.applyInterest(context, irmParams, lastTouchedTimestamp);

        PositionUpdater.updateFeeGrowth(context, vault, subVaults, ranges);
    }

    /**
     * Gets current price of underlying token by margin token.
     */
    function getPrice() public view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(context.isMarginZero, getSqrtPrice());
    }

    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(context.uniswapPool).slot0();
    }

    /**
     * Gets Time Weighted Average Price of underlying token by margin token.
     */
    function getTWAP() external view returns (uint256) {
        return LPTMath.decodeSqrtPriceX96(context.isMarginZero, getTWAPSqrtPrice());
    }

    function getTWAPSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, ) = LPTMath.callUniswapObserve(IUniswapV3Pool(context.uniswapPool), ORACLE_PERIOD);
    }

    function getPosition(uint256 _vaultId) public returns (DataType.Position[] memory) {
        applyPerpFee(_vaultId);

        return _getPosition(_vaultId);
    }

    function _getPosition(uint256 _vaultId) internal view returns (DataType.Position[] memory) {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getPositions(subVaults, ranges, context);
    }

    function _getPositionOfSubVault(uint256 _vaultId, uint256 _subVaultIndex)
        internal
        view
        returns (DataType.Position memory)
    {
        DataType.Vault memory vault = vaults[_vaultId];

        return
            VaultLib.getPositionOfSubVault(_subVaultIndex, subVaults[vault.subVaults[_subVaultIndex]], ranges, context);
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
