//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Initializable} from "@openzeppelin/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/PoolAddress.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./interfaces/IController.sol";
import {IVaultNFT} from "./interfaces/IVaultNFT.sol";
import {BaseToken} from "./libraries/BaseToken.sol";
import "./libraries/DataType.sol";
import "./libraries/VaultLib.sol";
import "./libraries/PredyMath.sol";
import "./libraries/PositionUpdater.sol";
import "./libraries/InterestCalculator.sol";
import "./libraries/PositionLib.sol";
import "./libraries/logic/LiquidationLogic.sol";
import "./libraries/Constants.sol";

/**
 * Error Codes
 * P1: caller must be vault owner
 * P2: caller must be vault owner
 * P3: must not be liquidatable
 * P4: must be liquidatable
 */
contract Controller is IController, Initializable, IUniswapV3MintCallback {
    using BaseToken for BaseToken.TokenState;
    using SignedSafeMath for int256;
    using VaultLib for DataType.Vault;

    uint256 public lastTouchedTimestamp;

    mapping(bytes32 => DataType.PerpStatus) internal ranges;

    mapping(uint256 => DataType.Vault) internal vaults;
    mapping(uint256 => DataType.SubVault) internal subVaults;

    DataType.Context internal context;
    InterestCalculator.IRMParams public irmParams;
    InterestCalculator.YearlyPremiumParams public ypParams;

    address public operator;

    address private vaultNFT;

    event VaultCreated(uint256 vaultId, address owner);
    event PositionUpdated(uint256 vaultId, int256 a0, int256 a1, uint256 averagePrice, bytes metadata);

    modifier onlyOperator() {
        require(operator == msg.sender, "caller must be operator");
        _;
    }

    constructor() {}

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == context.uniswapPool);
        if (amount0 > 0) TransferHelper.safeTransfer(context.token0, msg.sender, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(context.token1, msg.sender, amount1);
    }

    function initialize(
        DataType.InitializationParams memory _initializationParams,
        address _factory,
        address _swapRouter,
        address _vaultNFT
    ) public initializer {
        context.feeTier = _initializationParams.feeTier;
        context.token0 = _initializationParams.token0;
        context.token1 = _initializationParams.token1;
        context.isMarginZero = _initializationParams.isMarginZero;
        context.swapRouter = _swapRouter;

        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: context.token0,
            token1: context.token1,
            fee: context.feeTier
        });

        context.uniswapPool = PoolAddress.computeAddress(_factory, poolKey);

        vaultNFT = _vaultNFT;

        context.nextSubVaultId = 1;

        ERC20(context.token0).approve(address(_swapRouter), type(uint256).max);
        ERC20(context.token1).approve(address(_swapRouter), type(uint256).max);

        context.tokenState0.initialize();
        context.tokenState1.initialize();

        lastTouchedTimestamp = block.timestamp;

        operator = msg.sender;
    }

    /**
     * @notice Sets new operator
     * @dev Only operator can call this function.
     * @param _newOperator The address of new operator
     */
    function setOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0));
        operator = _newOperator;
    }

    /**
     * @notice Updates interest rate model parameter.
     * @dev Only operator can call this function.
     * @param _irmParams New interest rate model parameter
     */
    function updateIRMParams(InterestCalculator.IRMParams memory _irmParams) external onlyOperator {
        irmParams = _irmParams;
    }

    /**
     * @notice Updates interest rate model parameters for premium calculation.
     * @dev Only operator can call this function.
     * @param _irmParams New interest rate model parameter
     * @param _premiumParams New interest rate model parameter for variance calculation
     */
    function updateYearlyPremiumParams(
        InterestCalculator.IRMParams memory _irmParams,
        InterestCalculator.IRMParams memory _premiumParams
    ) external onlyOperator {
        ypParams.irmParams = _irmParams;
        ypParams.premiumParams = _premiumParams;
    }

    /**
     * @notice Withdraws accumulated protocol fee.
     * @dev Only operator can call this function.
     * @param _amount0 amount of token0 to withdraw
     * @param _amount1 amount of token1 to withdraw
     */
    function withdrawProtocolFee(uint256 _amount0, uint256 _amount1) external onlyOperator {
        require(context.accumuratedProtocolFee0 >= _amount0 && context.accumuratedProtocolFee1 >= _amount1, "P8");

        context.accumuratedProtocolFee0 -= _amount0;
        context.accumuratedProtocolFee1 -= _amount1;

        if (_amount0 > 0) {
            TransferHelper.safeTransfer(context.token0, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            TransferHelper.safeTransfer(context.token1, msg.sender, _amount1);
        }
    }

    // User API

    /**
     * @notice Update position in a vault.
     * @param _vaultId The id of the vault. 0 means that it creates new vault.
     * @param _positionUpdates Operation list to update position
     * @param _tradeOption trade parameters
     */
    function updatePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        DataType.TradeOption memory _tradeOption
    )
        public
        override
        returns (
            uint256 vaultId,
            int256 requiredAmount0,
            int256 requiredAmount1,
            uint256 averagePrice
        )
    {
        applyPerpFee(_vaultId, _positionUpdates);

        DataType.Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId, _tradeOption.quoterMode);

        uint256 beforeSqrtPrice = getSqrtPrice();

        // update position in the vault
        (requiredAmount0, requiredAmount1) = PositionUpdater.updatePosition(
            vault,
            subVaults,
            context,
            ranges,
            _positionUpdates,
            _tradeOption
        );

        averagePrice = UniHelper.getAveragePrice(context.isMarginZero, beforeSqrtPrice, getSqrtPrice());

        if (_tradeOption.quoterMode) {
            revertRequiredAmounts(requiredAmount0, requiredAmount1, averagePrice);
        }

        // check the vault is safe
        require(!LiquidationLogic.checkLiquidatable(vault, subVaults, context, ranges), "P3");

        if (requiredAmount0 > 0) {
            TransferHelper.safeTransferFrom(context.token0, msg.sender, address(this), uint256(requiredAmount0));
        } else if (requiredAmount0 < 0) {
            TransferHelper.safeTransfer(context.token0, msg.sender, uint256(-requiredAmount0));
        }

        if (requiredAmount1 > 0) {
            TransferHelper.safeTransferFrom(context.token1, msg.sender, address(this), uint256(requiredAmount1));
        } else if (requiredAmount1 < 0) {
            TransferHelper.safeTransfer(context.token1, msg.sender, uint256(-requiredAmount1));
        }

        emit PositionUpdated(vaultId, requiredAmount0, requiredAmount1, averagePrice, _tradeOption.metadata);
    }

    /**
     * @notice Anyone can liquidates the vault if its vault value is less than Min. Deposit.
     * @param _vaultId The id of the vault
     * @param _positionUpdates Operation list to update position
     */
    function liquidate(uint256 _vaultId, DataType.PositionUpdate[] memory _positionUpdates) internal {
        applyPerpFee(_vaultId, _positionUpdates);

        LiquidationLogic.execLiquidation(vaults[_vaultId], subVaults, _positionUpdates, context, ranges);
    }

    /**
     * @notice Contract owner can close positions
     * @param _data Vaults data to close position
     */
    function forceClose(bytes[] memory _data) external onlyOperator {
        for (uint256 i = 0; i < _data.length; i++) {
            (uint256 vaultId, DataType.PositionUpdate[] memory _positionUpdates) = abi.decode(
                _data[i],
                (uint256, DataType.PositionUpdate[])
            );

            applyPerpFee(vaultId, _positionUpdates);

            LiquidationLogic.reducePosition(vaults[vaultId], subVaults, context, ranges, _positionUpdates, 0);
        }
    }

    // Getter Functions

    function getContext()
        external
        view
        returns (
            bool,
            uint256,
            address,
            uint256,
            uint256
        )
    {
        return (
            context.isMarginZero,
            context.nextSubVaultId,
            context.uniswapPool,
            context.accumuratedProtocolFee0,
            context.accumuratedProtocolFee1
        );
    }

    /**
     * @notice Returns a Liquidity Provider Token (LPT) data
     * @param _rangeId The id of the LPT
     */
    function getRange(bytes32 _rangeId) external view returns (DataType.PerpStatus memory) {
        return ranges[_rangeId];
    }

    /**
     * @notice Returns the status of supplied tokens.
     */
    function getTokenState() external view returns (BaseToken.TokenState memory, BaseToken.TokenState memory) {
        return (context.tokenState0, context.tokenState1);
    }

    /**
     * @notice Returns the flag whether a vault can be liquidated or not.
     * @param _vaultId vault id
     * @return isLiquidatable true if the vault is liquidatable, false if the vault is safe.
     */
    function checkLiquidatable(uint256 _vaultId) external returns (bool) {
        applyPerpFee(_vaultId);

        return LiquidationLogic.checkLiquidatable(vaults[_vaultId], subVaults, context, ranges);
    }

    /**
     * @notice Returns values and token amounts of the vault.
     * @param _vaultId The id of the vault
     */
    function getVaultStatus(uint256 _vaultId) external returns (DataType.VaultStatus memory) {
        uint160 sqrtPriceX96 = getSqrtPrice();

        applyPerpFee(_vaultId);

        return vaults[_vaultId].getVaultStatus(subVaults, ranges, context, sqrtPriceX96);
    }

    function getVaultValue(uint256 _vaultId) external view returns (int256) {
        return LiquidationLogic.getVaultValue(vaults[_vaultId], subVaults, context, ranges);
    }

    /**
     * @notice Returns a vault data
     * @param _vaultId The id of the vault
     */
    function getVault(uint256 _vaultId) external view returns (DataType.Vault memory) {
        return vaults[_vaultId];
    }

    /**
     * @notice Returns a sub-vault data
     * @param _subVaultId The id of the sub-vault
     */
    function getSubVault(uint256 _subVaultId) external view returns (DataType.SubVault memory) {
        return subVaults[_subVaultId];
    }

    /**
     * @notice Returns yearly premium to borrow Liquidity Provider Token (LPT).
     * The function can return yearly premium with specific utilization ratio.
     * @param _rangeId The id of the range
     * @param _utilizationRatio Utilization ratio of LPT
     */
    function calculateYearlyPremium(bytes32 _rangeId, uint256 _utilizationRatio) external view returns (uint256) {
        if (ranges[_rangeId].lastTouchedTimestamp == 0) {
            return 0;
        }

        return
            InterestCalculator.calculateYearlyPremium(
                ypParams,
                context,
                ranges[_rangeId],
                getSqrtPrice(),
                _utilizationRatio
            );
    }

    // Private Functions

    function createOrGetVault(uint256 _vaultId, bool _quoterMode)
        internal
        returns (uint256 vaultId, DataType.Vault storage)
    {
        if (_vaultId == 0) {
            vaultId = IVaultNFT(vaultNFT).mintNFT(msg.sender);

            vaults[vaultId].vaultId = vaultId;

            emit VaultCreated(vaultId, msg.sender);
        } else {
            vaultId = _vaultId;

            require(IVaultNFT(vaultNFT).ownerOf(vaultId) == msg.sender || _quoterMode, "P2");
        }

        return (vaultId, vaults[vaultId]);
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
            ypParams,
            getSqrtPrice()
        );

        lastTouchedTimestamp = InterestCalculator.applyInterest(context, irmParams, lastTouchedTimestamp);

        PositionUpdater.updateFeeGrowth(context, vault, subVaults, ranges, _positionUpdates);
    }

    function applyInterest() internal {
        lastTouchedTimestamp = InterestCalculator.applyInterest(context, irmParams, lastTouchedTimestamp);
    }

    /**
     * Gets square root of current underlying token price by quote token.
     */
    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(context.uniswapPool).slot0();
    }

    function getPosition(uint256 _vaultId) public view returns (DataType.Position[] memory) {
        return _getPosition(_vaultId);
    }

    function _getPosition(uint256 _vaultId) internal view returns (DataType.Position[] memory) {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getPositions(subVaults, ranges, context);
    }

    function getPositionCalculatorParams(uint256 _vaultId)
        public
        view
        returns (PositionCalculator.PositionCalculatorParams memory)
    {
        DataType.Vault memory vault = vaults[_vaultId];

        return vault.getPositionCalculatorParams(subVaults, ranges, context);
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

    function revertRequiredAmounts(
        int256 _requiredAmount0,
        int256 _requiredAmount1,
        uint256 _averagePrice
    ) internal pure {
        assembly {
            let ptr := mload(0x20)
            mstore(ptr, _requiredAmount0)
            mstore(add(ptr, 0x20), _requiredAmount1)
            mstore(add(ptr, 0x40), _averagePrice)
            revert(ptr, 96)
        }
    }
}
