//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Initializable} from "@openzeppelin/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@uniswap/v3-periphery/libraries/PoolAddress.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IVaultNFT} from "./interfaces/IVaultNFT.sol";
import {BaseToken} from "./libraries/BaseToken.sol";
import "./libraries/DataType.sol";
import "./libraries/VaultLib.sol";
import "./libraries/PredyMath.sol";
import "./libraries/PositionUpdater.sol";
import "./libraries/InterestCalculator.sol";
import "./libraries/PositionLib.sol";
import "./libraries/logic/LiquidationLogic.sol";
import "./libraries/logic/UpdatePositionLogic.sol";
import "./libraries/Constants.sol";

/**
 * Error Codes
 * P1: caller must be vault owner
 * P2: vault does not exists
 * P3: caller must be operator
 * P4: cannot create vault with 0 amount
 * P5: paused
 * P6: unpaused
 * P7: tx too old
 * P8: too much slippage
 * P9: invalid interest rate model
 */
contract Controller is Initializable, IUniswapV3MintCallback, IUniswapV3SwapCallback {
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

    bool public isSystemPaused;

    event OperatorUpdated(address operator);
    event VaultCreated(uint256 vaultId, address owner);
    event Paused();
    event UnPaused();
    event ProtocolFeeWithdrawn(uint256 withdrawnFee0, uint256 withdrawnFee1);

    modifier notPaused() {
        require(!isSystemPaused, "P5");
        _;
    }

    modifier isPaused() {
        require(isSystemPaused, "P6");
        _;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "P3");
        _;
    }

    modifier checkVaultExists(uint256 _vaultId) {
        require(_vaultId < IVaultNFT(vaultNFT).nextId(), "P2");
        _;
    }

    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "P7");
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

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        require(msg.sender == context.uniswapPool);
        if (amount0Delta > 0) TransferHelper.safeTransfer(context.token0, msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) TransferHelper.safeTransfer(context.token1, msg.sender, uint256(amount1Delta));
    }

    function initialize(
        DataType.InitializationParams memory _initializationParams,
        address _factory,
        address _chainlinkPriceFeed,
        address _vaultNFT
    ) public initializer {
        require(_vaultNFT != address(0));
        context.feeTier = _initializationParams.feeTier;
        context.token0 = _initializationParams.token0;
        context.token1 = _initializationParams.token1;
        context.isMarginZero = _initializationParams.isMarginZero;
        context.chainlinkPriceFeed = _chainlinkPriceFeed;

        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: context.token0,
            token1: context.token1,
            fee: context.feeTier
        });

        context.uniswapPool = PoolAddress.computeAddress(_factory, poolKey);

        vaultNFT = _vaultNFT;

        context.nextSubVaultId = 1;

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

        emit OperatorUpdated(_newOperator);
    }

    /**
     * @notice Updates interest rate model parameter.
     * @dev Only operator can call this function.
     * @param _irmParams New interest rate model parameter
     */
    function updateIRMParams(InterestCalculator.IRMParams memory _irmParams) external onlyOperator {
        validateIRMParams(_irmParams);
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
        validateIRMParams(_irmParams);
        validateIRMParams(_premiumParams);
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
        require(context.accumulatedProtocolFee0 >= _amount0 && context.accumulatedProtocolFee1 >= _amount1, "P8");

        context.accumulatedProtocolFee0 -= _amount0;
        context.accumulatedProtocolFee1 -= _amount1;

        if (_amount0 > 0) {
            TransferHelper.safeTransfer(context.token0, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            TransferHelper.safeTransfer(context.token1, msg.sender, _amount1);
        }

        emit ProtocolFeeWithdrawn(_amount0, _amount1);
    }

    /**
     * @notice pause the contract
     */
    function pause() external onlyOperator notPaused {
        isSystemPaused = true;

        emit Paused();
    }

    /**
     * @notice unpause the contract
     */
    function unPause() external onlyOperator isPaused {
        isSystemPaused = false;

        emit UnPaused();
    }

    // User API

    /**
     * @notice Opens new position.
     * @param _vaultId The id of the vault. 0 means that it creates new vault.
     * @param _position Position to open
     * @param _tradeOption Trade parameters
     * @param _openPositionOptions Option parameters to open position
     */
    function openPosition(
        uint256 _vaultId,
        DataType.Position memory _position,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    )
        external
        returns (
            uint256 vaultId,
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TokenAmounts memory swapAmounts
        )
    {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToOpen(
            _position,
            _tradeOption.isQuoteZero,
            getSqrtPrice(),
            _openPositionOptions.swapRatio
        );

        (vaultId, requiredAmounts, swapAmounts) = updatePosition(
            _vaultId,
            positionUpdates,
            _tradeOption,
            _openPositionOptions
        );
    }

    function updatePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory positionUpdates,
        DataType.TradeOption memory _tradeOption,
        DataType.OpenPositionOption memory _openPositionOptions
    )
        public
        notPaused
        checkDeadline(_openPositionOptions.deadline)
        returns (
            uint256 vaultId,
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TokenAmounts memory swapAmounts
        )
    {
        (vaultId, requiredAmounts, swapAmounts) = _updatePosition(_vaultId, positionUpdates, _tradeOption);

        _checkPrice(_openPositionOptions.lowerSqrtPrice, _openPositionOptions.upperSqrtPrice);
    }

    /**
     * @notice Closes all positions in a vault.
     * @param _vaultId The id of the vault
     * @param _tradeOption Trade parameters
     * @param _closePositionOptions Option parameters to close position
     */
    function closeVault(
        uint256 _vaultId,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    )
        external
        notPaused
        returns (DataType.TokenAmounts memory requiredAmounts, DataType.TokenAmounts memory swapAmounts)
    {
        return closePosition(_vaultId, _getPosition(_vaultId), _tradeOption, _closePositionOptions);
    }

    /**
     * @notice Closes all positions in sub-vault.
     * @param _vaultId The id of the vault
     * @param _subVaultId The id of the sub-vault
     * @param _tradeOption Trade parameters
     * @param _closePositionOptions Option parameters to close position
     */
    function closeSubVault(
        uint256 _vaultId,
        uint256 _subVaultId,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    )
        external
        notPaused
        returns (DataType.TokenAmounts memory requiredAmounts, DataType.TokenAmounts memory swapAmounts)
    {
        DataType.Position[] memory positions = new DataType.Position[](1);

        positions[0] = _getPositionOfSubVault(_subVaultId);

        return closePosition(_vaultId, positions, _tradeOption, _closePositionOptions);
    }

    /**
     * @notice Closes position partially.
     * @param _vaultId The id of the vault
     * @param _positions Positions to close
     * @param _tradeOption Trade parameters
     * @param _closePositionOptions Option parameters to close position
     */
    function closePosition(
        uint256 _vaultId,
        DataType.Position[] memory _positions,
        DataType.TradeOption memory _tradeOption,
        DataType.ClosePositionOption memory _closePositionOptions
    )
        public
        notPaused
        checkDeadline(_closePositionOptions.deadline)
        returns (DataType.TokenAmounts memory requiredAmounts, DataType.TokenAmounts memory swapAmounts)
    {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            _positions,
            _tradeOption.isQuoteZero,
            getSqrtPrice(),
            _closePositionOptions.swapRatio,
            _closePositionOptions.closeRatio
        );

        (, requiredAmounts, swapAmounts) = _updatePosition(_vaultId, positionUpdates, _tradeOption);

        _checkPrice(_closePositionOptions.lowerSqrtPrice, _closePositionOptions.upperSqrtPrice);
    }

    /**
     * @notice Liquidates a vault.
     * @param _vaultId The id of the vault
     * @param _liquidationOption option parameters for liquidation call
     */
    function liquidate(uint256 _vaultId, DataType.LiquidationOption memory _liquidationOption) external notPaused {
        DataType.PositionUpdate[] memory positionUpdates = PositionLib.getPositionUpdatesToClose(
            getPosition(_vaultId),
            context.isMarginZero,
            getSqrtPrice(),
            _liquidationOption.swapRatio,
            _liquidationOption.closeRatio
        );

        _liquidate(_vaultId, positionUpdates);
    }

    /**
     * @notice Update position in a vault.
     * @param _vaultId The id of the vault. 0 means that it creates new vault.
     * @param _positionUpdates Operation list to update position
     * @param _tradeOption trade parameters
     */
    function _updatePosition(
        uint256 _vaultId,
        DataType.PositionUpdate[] memory _positionUpdates,
        DataType.TradeOption memory _tradeOption
    )
        internal
        checkVaultExists(_vaultId)
        returns (
            uint256 vaultId,
            DataType.TokenAmounts memory requiredAmounts,
            DataType.TokenAmounts memory swapAmounts
        )
    {
        applyPerpFee(_vaultId, _positionUpdates);

        DataType.Vault storage vault;
        (vaultId, vault) = createOrGetVault(_vaultId, _tradeOption.quoterMode);

        DataType.PositionUpdateResult memory positionUpdateResult = UpdatePositionLogic.updatePosition(
            vault,
            subVaults,
            context,
            ranges,
            _positionUpdates,
            _tradeOption,
            IVaultNFT(vaultNFT).ownerOf(vaultId)
        );

        requiredAmounts = positionUpdateResult.requiredAmounts;
        swapAmounts = positionUpdateResult.swapAmounts;

        if (_vaultId == 0) {
            // non 0 amount of tokens required to create new vault.
            if (context.isMarginZero) {
                require(requiredAmounts.amount0 >= Constants.MIN_MARGIN_AMOUNT, "P4");
            } else {
                require(requiredAmounts.amount1 >= Constants.MIN_MARGIN_AMOUNT, "P4");
            }
        }
    }

    /**
     * @notice Anyone can liquidates the vault if its vault value is less than Min. Deposit.
     * @param _vaultId The id of the vault
     * @param _positionUpdates Operation list to update position
     */
    function _liquidate(uint256 _vaultId, DataType.PositionUpdate[] memory _positionUpdates)
        internal
        checkVaultExists(_vaultId)
    {
        require(_vaultId > 0);

        applyPerpFee(_vaultId, _positionUpdates);

        LiquidationLogic.execLiquidation(vaults[_vaultId], subVaults, _positionUpdates, context, ranges);
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
            context.accumulatedProtocolFee0,
            context.accumulatedProtocolFee1
        );
    }

    /**
     * @notice Returns a Liquidity Provider Token (LPT) data
     * @param _rangeId The id of the LPT
     */
    function getRange(bytes32 _rangeId) external returns (DataType.PerpStatus memory) {
        InterestCalculator.updatePremiumGrowth(ypParams, context, ranges[_rangeId], getSqrtIndexPrice());

        InterestCalculator.updateFeeGrowthForRange(context, ranges[_rangeId]);

        return ranges[_rangeId];
    }

    /**
     * @notice Returns the utilization ratio of Liquidity Provider Token (LPT).
     * @param _rangeId The id of the LPT
     */
    function getUtilizationRatio(bytes32 _rangeId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (ranges[_rangeId].lastTouchedTimestamp == 0) {
            return (0, 0, 0);
        }

        if (ranges[_rangeId].borrowedLiquidity == 0) {
            return (LPTStateLib.getTotalLiquidityAmount(address(this), context.uniswapPool, ranges[_rangeId]), 0, 0);
        }

        return LPTStateLib.getPerpStatus(address(this), context.uniswapPool, ranges[_rangeId]);
    }

    /**
     * @notice Returns the status of supplied tokens.
     */
    function getTokenState() external returns (BaseToken.TokenState memory, BaseToken.TokenState memory) {
        applyInterest();

        return (context.tokenState0, context.tokenState1);
    }

    /**
     * @notice Returns the flag whether a vault is safe or not.
     * @param _vaultId vault id
     * @return isSafe true if the vault is safe, false if the vault can be liquidated.
     */
    function isVaultSafe(uint256 _vaultId) external returns (bool isSafe) {
        applyPerpFee(_vaultId);

        return LiquidationLogic.isVaultSafe(vaults[_vaultId], subVaults, context, ranges);
    }

    /**
     * @notice Returns values and token amounts of the vault.
     * @param _vaultId The id of the vault
     */
    function getVaultStatus(uint256 _vaultId, uint160 _sqrtPriceX96) external returns (DataType.VaultStatus memory) {
        applyPerpFee(_vaultId);

        return vaults[_vaultId].getVaultStatus(subVaults, ranges, context, _sqrtPriceX96);
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

    function calculateLPTBorrowerAndLenderPremium(
        bytes32 _rangeId,
        uint256 _perpUr,
        uint256 _elapsed
    )
        external
        view
        returns (
            uint256 premiumGrowthForBorrower,
            uint256 premiumGrowthForLender,
            uint256 protocolFeePerLiquidity
        )
    {
        return
            InterestCalculator.calculateLPTBorrowerAndLenderPremium(
                ypParams,
                context,
                ranges[_rangeId],
                getSqrtIndexPrice(),
                _perpUr,
                _elapsed
            );
    }

    // Private Functions

    function validateIRMParams(InterestCalculator.IRMParams memory _irmParams) internal pure {
        require(
            _irmParams.baseRate <= 1e18 &&
                _irmParams.kinkRate <= 1e18 &&
                _irmParams.slope1 <= 1e18 &&
                _irmParams.slope2 <= 10 * 1e18,
            "P9"
        );
    }

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

            require(IVaultNFT(vaultNFT).ownerOf(vaultId) == msg.sender || _quoterMode, "P1");
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
        applyInterest();

        DataType.Vault memory vault = vaults[_vaultId];

        InterestCalculator.updatePremiumGrowthForVault(
            vault,
            subVaults,
            ranges,
            context,
            _positionUpdates,
            ypParams,
            getSqrtIndexPrice()
        );

        InterestCalculator.updateFeeGrowth(context, vault, subVaults, ranges, _positionUpdates);
    }

    function applyInterest() internal {
        lastTouchedTimestamp = InterestCalculator.applyInterest(context, irmParams, lastTouchedTimestamp);
    }

    function _checkPrice(uint256 _lowerSqrtPrice, uint256 _upperSqrtPrice) internal view {
        uint256 sqrtPrice = getSqrtPrice();

        require(_lowerSqrtPrice <= sqrtPrice && sqrtPrice <= _upperSqrtPrice, "P8");
    }

    /**
     * Gets square root of current underlying token price by quote token.
     */
    function getSqrtPrice() public view returns (uint160 sqrtPriceX96) {
        return UniHelper.getSqrtPrice(context.uniswapPool);
    }

    function getSqrtIndexPrice() public view returns (uint160) {
        return LiquidationLogic.getSqrtIndexPrice(context);
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

    function _getPositionOfSubVault(uint256 _subVaultId) internal view returns (DataType.Position memory) {
        return VaultLib.getPositionOfSubVault(subVaults[_subVaultId], ranges, context);
    }
}
