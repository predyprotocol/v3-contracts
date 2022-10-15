//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "../interfaces/IControllerHelper.sol";
import "../interfaces/IReader.sol";
import "../interfaces/IVaultNFT.sol";
import "../libraries/LPTMath.sol";
import "../libraries/Constants.sol";
import "./SateliteLib.sol";
import "./FutureMarketLib.sol";

/**
 * FM0: caller is not vault owner
 * FM1: vault must be safe
 * FM2: vault must not be safe
 */
contract FutureMarket is ERC20, IERC721Receiver, Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for int256;

    int256 private constant FUNDING_PERIOD = 1 days;

    IControllerHelper internal immutable controller;

    IReader internal immutable reader;

    address internal immutable usdc;

    address private vaultNFT;

    uint256 public vaultId;

    struct Range {
        uint256 id;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
    }

    struct PoolPosition {
        int256 positionAmount;
        uint256 entryPrice;
        int256 entryFundingFee;
        uint256 usdcAmount;
    }

    mapping(uint256 => Range) private ranges;

    mapping(uint256 => FutureMarketLib.FutureVault) private futureVaults;

    uint256 public futureVaultCount;

    uint256 private currentRangeId;

    PoolPosition public poolPosition;

    int256 private fundingFeePerPosition;

    uint256 private lastTradeTimestamp;

    event MarginUpdated(uint256 indexed vaultId, address trader, int256 marginAmount);

    event PositionUpdated(
        uint256 indexed vaultId,
        address trader,
        int256 tradeAmount,
        uint256 tradePrice,
        int256 fundingFeePerPosition,
        int256 deltaUsdcPosition
    );

    event Liquidated(
        uint256 indexed vaultId,
        address liquidator,
        int256 tradeAmount,
        uint256 tradePrice,
        int256 fundingFeePerPosition,
        int256 deltaUsdcPosition,
        uint256 liquidationPenalty
    );

    constructor(
        address _controller,
        address _reader,
        address _usdc,
        address _vaultNFT
    ) ERC20("PredyFutureLP", "PFLP") {
        controller = IControllerHelper(_controller);
        reader = IReader(_reader);
        usdc = _usdc;
        vaultNFT = _vaultNFT;

        ERC20(_usdc).approve(address(_controller), type(uint256).max);

        futureVaultCount = 1;

        lastTradeTimestamp = block.timestamp;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setRange(
        uint256 _id,
        int24 _lowerTick,
        int24 _upperTick
    ) external onlyOwner {
        uint128 liquidity = SateliteLib.getBaseLiquidity(reader.isMarginZero(), _lowerTick, _upperTick);

        ranges[_id] = Range(_id, liquidity, _lowerTick, _upperTick);
    }

    function setCurrentRangeId(uint256 _currentRangeId) external onlyOwner {
        currentRangeId = _currentRangeId;
    }

    function getLPTokenPrice() external view returns (uint256) {
        return (Constants.ONE * getPoolValue(reader.getTWAP())) / totalSupply();
    }

    function deposit(uint256 _amount) external returns (uint256 mintAmount) {
        updateFundingPaidPerPosition();

        uint256 poolValue = getPoolValue(reader.getTWAP());

        if (poolValue == 0) {
            mintAmount = _amount;
        } else {
            mintAmount = (_amount * totalSupply()) / poolValue;
        }

        poolPosition.usdcAmount += _amount;

        TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), _amount);

        _mint(msg.sender, mintAmount);
    }

    function withdraw(uint256 _amount) external returns (uint256 burnAmount) {
        updateFundingPaidPerPosition();

        uint256 poolValue = getPoolValue(reader.getTWAP());

        burnAmount = (_amount * totalSupply()) / poolValue;

        poolPosition.usdcAmount = poolPosition.usdcAmount.sub(_amount);

        TransferHelper.safeTransfer(usdc, msg.sender, _amount);

        _burn(msg.sender, burnAmount);
    }

    function getPoolValue(uint256 _price) internal view returns (uint256) {
        int256 positionValue = int256(_price)
            .sub(int256(poolPosition.entryPrice).add(fundingFeePerPosition.sub(poolPosition.entryFundingFee)))
            .mul(poolPosition.positionAmount) / 1e18;

        int256 vaultValue = controller.getVaultValue(vaultId);

        return positionValue.add(vaultValue).add(int256(poolPosition.usdcAmount)).toUint256();
    }

    function updateMargin(uint256 _vaultId, int256 _marginAmount) external returns (uint256 traderVaultId) {
        require(_marginAmount != 0);

        FutureMarketLib.FutureVault storage futureVault;

        (traderVaultId, futureVault) = _createOrGetVault(_vaultId, false);

        futureVault.marginAmount = PredyMath.addDelta(futureVault.marginAmount, _marginAmount);

        require(isVaultSafe(futureVault), "FM1");

        if (_marginAmount > 0) {
            TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), uint256(_marginAmount));
        } else if (_marginAmount < 0) {
            TransferHelper.safeTransfer(usdc, msg.sender, uint256(-_marginAmount));
        }

        emit MarginUpdated(traderVaultId, msg.sender, _marginAmount);
    }

    function trade(
        uint256 _vaultId,
        int256 _amount,
        bool _quoterMode
    ) external returns (uint256 traderVaultId) {
        updateFundingPaidPerPosition();

        uint256 entryPrice = _updatePoolPosition(_amount);

        if (_quoterMode) {
            revertEntryPrice(entryPrice);
        }

        FutureMarketLib.FutureVault storage futureVault;

        (traderVaultId, futureVault) = _createOrGetVault(_vaultId, _quoterMode);

        int256 deltaUsdcPosition = _updateTraderPosition(futureVault, _amount, entryPrice);

        emit PositionUpdated(traderVaultId, msg.sender, _amount, entryPrice, fundingFeePerPosition, deltaUsdcPosition);
    }

    function liquidationCall(uint256 _vaultId) external {
        updateFundingPaidPerPosition();

        FutureMarketLib.FutureVault storage futureVault = futureVaults[_vaultId];

        require(!isVaultSafe(futureVault), "FM2");

        int256 tradeAmount = -futureVaults[_vaultId].positionAmount;

        uint256 entryPrice = _updatePoolPosition(tradeAmount);

        int256 deltaUsdcPosition = _updateTraderPosition(futureVault, tradeAmount, entryPrice);

        uint256 liquidationPenalty = _decreaesLiquidationPenalty(futureVault, tradeAmount, entryPrice);

        emit Liquidated(
            _vaultId,
            msg.sender,
            tradeAmount,
            entryPrice,
            fundingFeePerPosition,
            deltaUsdcPosition,
            liquidationPenalty
        );
    }

    function rebalance() external {
        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            true,
            int256(getMarginValue(0)),
            Constants.MARGIN_STAY,
            bytes("")
        );

        DataType.OpenPositionOption memory openPositionOption = DataType.OpenPositionOption(0, type(uint256).max, 500);

        DataType.PositionUpdate[] memory positionUpdates = _rebalance(
            controller.getSqrtPrice(),
            PredyMath.abs(poolPosition.positionAmount)
        );

        positionUpdates[positionUpdates.length - 1] = _cover(poolPosition.positionAmount);

        int256 requiredAmount0;
        int256 requiredAmount1;

        (vaultId, requiredAmount0, requiredAmount1, ) = controller.updatePositionInVault(
            vaultId,
            positionUpdates,
            tradeOption,
            openPositionOption
        );

        poolPosition.usdcAmount = PredyMath.addDelta(
            poolPosition.usdcAmount,
            reader.isMarginZero() ? -requiredAmount0 : -requiredAmount1
        );
    }

    function getVaultStatus(uint256 _vaultId)
        internal
        view
        returns (
            int256,
            uint256,
            uint256
        )
    {
        FutureMarketLib.FutureVault memory futureVault = futureVaults[_vaultId];

        uint256 twap = reader.getTWAP();

        uint256 minCollateral = FutureMarketLib.calculateMinCollateral(futureVault, twap);

        int256 vaultValue = getVaultValue(futureVault, twap);

        return (vaultValue, futureVault.marginAmount, minCollateral);
    }

    function getMarginValue(int256 _amount) internal view returns (uint256 marginValue) {
        uint256 currentPrice = reader.getPrice();

        marginValue = (currentPrice * PredyMath.abs(poolPosition.positionAmount + _amount)) / 1e18 / 3;
    }

    function _updatePoolPosition(int256 _amount) internal returns (uint256 entryPrice) {
        {
            DataType.TradeOption memory tradeOption = DataType.TradeOption(
                false,
                true,
                false,
                true,
                int256(getMarginValue(_amount)),
                Constants.MARGIN_STAY,
                bytes("")
            );

            entryPrice = _coverAndRebalance(poolPosition.positionAmount, _amount, tradeOption);
        }

        {
            int256 deltaMarginAmount;

            {
                (int256 newEntryPrice, int256 profitValue) = FutureMarketLib.updateEntryPrice(
                    int256(poolPosition.entryPrice),
                    poolPosition.positionAmount,
                    int256(entryPrice),
                    _amount
                );

                poolPosition.entryPrice = newEntryPrice.toUint256();
                deltaMarginAmount = deltaMarginAmount.add(profitValue);
            }

            {
                (int256 entryFundingFee, int256 profitValue) = FutureMarketLib.updateEntryPrice(
                    int256(poolPosition.entryFundingFee),
                    poolPosition.positionAmount,
                    int256(fundingFeePerPosition),
                    _amount
                );

                poolPosition.entryFundingFee = entryFundingFee;
                deltaMarginAmount = deltaMarginAmount.add(profitValue);
            }

            poolPosition.usdcAmount = PredyMath.addDelta(poolPosition.usdcAmount, deltaMarginAmount);
        }

        poolPosition.positionAmount = poolPosition.positionAmount.sub(_amount);
    }

    function _updateTraderPosition(
        FutureMarketLib.FutureVault storage _futureVault,
        int256 _amount,
        uint256 _entryPrice
    ) internal returns (int256 deltaMarginAmount) {
        {
            (int256 newEntryPrice, int256 profitValue) = FutureMarketLib.updateEntryPrice(
                int256(_futureVault.entryPrice),
                _futureVault.positionAmount,
                int256(_entryPrice),
                _amount
            );

            _futureVault.entryPrice = newEntryPrice.toUint256();
            deltaMarginAmount = deltaMarginAmount.add(profitValue);
        }

        {
            (int256 entryFundingFee, int256 profitValue) = FutureMarketLib.updateEntryPrice(
                int256(_futureVault.entryFundingFee),
                _futureVault.positionAmount,
                int256(fundingFeePerPosition),
                _amount
            );

            _futureVault.entryFundingFee = entryFundingFee;
            deltaMarginAmount = deltaMarginAmount.add(profitValue);
        }

        _futureVault.positionAmount = _futureVault.positionAmount.add(_amount);

        _futureVault.marginAmount = PredyMath.addDelta(_futureVault.marginAmount, deltaMarginAmount);

        require(isVaultSafe(_futureVault), "FM1");
    }

    function _decreaesLiquidationPenalty(
        FutureMarketLib.FutureVault storage _futureVault,
        int256 _tradeAmount,
        uint256 _entryPrice
    ) internal returns (uint256 penaltyAmount) {
        penaltyAmount = (PredyMath.abs(_tradeAmount) * _entryPrice) / (1e18 * 500);

        _futureVault.marginAmount = _futureVault.marginAmount.sub(penaltyAmount);
    }

    function isVaultSafe(FutureMarketLib.FutureVault memory _futureVault) internal view returns (bool) {
        if (_futureVault.positionAmount == 0) {
            return true;
        }

        // TODO: use chainlink
        uint256 twap = reader.getTWAP();

        uint256 minCollateral = FutureMarketLib.calculateMinCollateral(_futureVault, twap);

        int256 vaultValue = getVaultValue(_futureVault, twap);

        return vaultValue > int256(minCollateral);
    }

    function getVaultValue(FutureMarketLib.FutureVault memory _futureVault, uint256 _price)
        internal
        view
        returns (int256)
    {
        int256 positionValue = int256(_price)
            .sub(int256(_futureVault.entryPrice).add(fundingFeePerPosition.sub(_futureVault.entryFundingFee)))
            .mul(_futureVault.positionAmount) / 1e18;

        return positionValue.add(int256(_futureVault.marginAmount));
    }

    function _createOrGetVault(uint256 _vaultId, bool _quoterMode)
        internal
        returns (uint256 futureVaultId, FutureMarketLib.FutureVault storage)
    {
        if (_vaultId == 0) {
            futureVaultId = IVaultNFT(vaultNFT).mintNFT(msg.sender);
        } else {
            futureVaultId = _vaultId;

            require(IVaultNFT(vaultNFT).ownerOf(futureVaultId) == msg.sender || _quoterMode, "FM0");
        }

        return (futureVaultId, futureVaults[futureVaultId]);
    }

    function _coverAndRebalance(
        int256 _poolPosition,
        int256 _amount,
        DataType.TradeOption memory tradeOption
    ) internal returns (uint256 entryPrice) {
        DataType.OpenPositionOption memory openPositionOption = DataType.OpenPositionOption(0, type(uint256).max, 500);

        DataType.PositionUpdate[] memory positionUpdates = _rebalanceUpdate(
            int256(PredyMath.abs(_poolPosition.add(_amount))).sub(int256(PredyMath.abs(_poolPosition)))
        );

        positionUpdates[positionUpdates.length - 1] = _cover(poolPosition.positionAmount);

        int256 requiredAmount0;
        int256 requiredAmount1;

        (vaultId, requiredAmount0, requiredAmount1, entryPrice) = controller.updatePositionInVault(
            vaultId,
            positionUpdates,
            tradeOption,
            openPositionOption
        );

        poolPosition.usdcAmount = PredyMath.addDelta(
            poolPosition.usdcAmount,
            reader.isMarginZero() ? -requiredAmount0 : -requiredAmount1
        );
    }

    function _cover(int256 _poolPosition) internal view returns (DataType.PositionUpdate memory) {
        uint256 delta = calculateDelta(PredyMath.abs(_poolPosition));

        int256 amount = _poolPosition.add(int256(delta));
        bool isMarginZero = reader.isMarginZero();

        if (amount > 0) {
            return
                DataType.PositionUpdate(
                    DataType.PositionUpdateType.BORROW_TOKEN,
                    0,
                    false,
                    0,
                    0,
                    0,
                    isMarginZero ? 0 : uint256(amount),
                    isMarginZero ? uint256(amount) : 0
                );
        } else if (amount < 0) {
            return
                DataType.PositionUpdate(
                    DataType.PositionUpdateType.DEPOSIT_TOKEN,
                    0,
                    false,
                    0,
                    0,
                    0,
                    isMarginZero ? 0 : uint256(-amount),
                    isMarginZero ? uint256(-amount) : 0
                );
        } else {
            return DataType.PositionUpdate(DataType.PositionUpdateType.NOOP, 0, false, 0, 0, 0, 0, 0);
        }
    }

    function _rebalance(uint160 _sqrtPrice, uint256 _poolPosition)
        internal
        view
        returns (DataType.PositionUpdate[] memory positionUpdates)
    {
        int24 currentTick = TickMath.getTickAtSqrtRatio(_sqrtPrice);

        if (ranges[currentRangeId].lowerTick > currentTick && ranges[currentRangeId - 1].liquidity > 0) {
            return _rebalanceSwitch(currentRangeId, currentRangeId - 1, _poolPosition);
        }

        if (ranges[currentRangeId].upperTick < currentTick && ranges[currentRangeId + 1].liquidity > 0) {
            return _rebalanceSwitch(currentRangeId, currentRangeId + 1, _poolPosition);
        }
    }

    function _rebalanceUpdate(int256 _amount) internal view returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](2);

        if (_amount > 0) {
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.DEPOSIT_LPT,
                0,
                false,
                uint128(uint256(_amount).mul(ranges[currentRangeId].liquidity) / 1e18),
                ranges[currentRangeId].lowerTick,
                ranges[currentRangeId].upperTick,
                0,
                0
            );
        } else if (_amount < 0) {
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.WITHDRAW_LPT,
                0,
                false,
                uint128(uint256(-_amount).mul(ranges[currentRangeId].liquidity) / 1e18),
                ranges[currentRangeId].lowerTick,
                ranges[currentRangeId].upperTick,
                0,
                0
            );
        }
    }

    function _rebalanceSwitch(
        uint256 _prevRangeId,
        uint256 _nextRangeId,
        uint256 _amount
    ) internal view returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](3);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_LPT,
            0,
            false,
            uint128(_amount.mul(ranges[_prevRangeId].liquidity) / 1e18),
            ranges[_prevRangeId].lowerTick,
            ranges[_prevRangeId].upperTick,
            0,
            0
        );
        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            0,
            false,
            uint128(_amount.mul(ranges[_nextRangeId].liquidity) / 1e18),
            ranges[_nextRangeId].lowerTick,
            ranges[_nextRangeId].upperTick,
            0,
            0
        );
    }

    function calculateDelta(uint256 _poolPosition) internal view returns (uint256 delta) {
        Range memory range = ranges[currentRangeId];

        (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidity(
            controller.getSqrtPrice(),
            range.lowerTick,
            range.upperTick,
            uint128((range.liquidity * _poolPosition) / 1e18)
        );

        if (reader.isMarginZero()) {
            return amount1;
        } else {
            return amount0;
        }
    }

    function updateFundingPaidPerPosition() internal {
        updateFundingPaidPerPosition(reader.getTWAP(), calculateFundingRate());
    }

    function updateFundingPaidPerPosition(uint256 twap, int256 fundingRate) internal {
        int256 fundingPaid = (int256(twap) * fundingRate) / 1e18;

        fundingFeePerPosition = fundingFeePerPosition.add(
            int256(block.timestamp - lastTradeTimestamp).mul(fundingPaid) / FUNDING_PERIOD
        );
        lastTradeTimestamp = block.timestamp;
    }

    function calculateFundingRate() internal view returns (int256) {
        if (poolPosition.positionAmount > 0) {
            return 1e14;
        } else {
            return -1e14;
        }
    }

    function revertEntryPrice(uint256 _entryPrice) internal pure {
        assembly {
            let ptr := mload(0x20)
            mstore(ptr, _entryPrice)
            revert(ptr, 32)
        }
    }
}
