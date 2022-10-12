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
import "../libraries/LPTMath.sol";
import "../libraries/Constants.sol";
import "./BlackScholes.sol";
import "./SateliteLib.sol";

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

    uint256 public vaultId;

    struct Range {
        uint256 id;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
    }

    struct FutureVault {
        uint256 id;
        address owner;
        int256 positionAmount;
        uint256 entryPrice;
        int256 entryFundingFee;
        uint256 marginAmount;
    }

    struct PoolPosition {
        int256 positionAmount;
        uint256 entryPrice;
        int256 entryFundingFee;
        uint256 usdcAmount;
    }

    mapping(uint256 => Range) ranges;

    mapping(uint256 => FutureVault) futureVaults;

    uint256 public futureVaultCount;

    uint256 currentRangeId;

    PoolPosition public poolPosition;

    int256 private fundingPaidPerPosition;

    uint256 private lastTradeTimestamp;

    constructor(
        address _controller,
        address _reader,
        address _usdc
    ) ERC20("", "") {
        controller = IControllerHelper(_controller);
        reader = IReader(_reader);
        usdc = _usdc;

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
        return (Constants.ONE * poolPosition.usdcAmount) / totalSupply();
    }

    function deposit(uint256 _amount) external returns (uint256 mintAmount) {
        updateFundingPaidPerPosition();

        if (poolPosition.usdcAmount == 0) {
            mintAmount = _amount;
        } else {
            mintAmount = (_amount * totalSupply()) / poolPosition.usdcAmount;
        }

        poolPosition.usdcAmount += _amount;

        TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), _amount);

        _mint(msg.sender, mintAmount);
    }

    function withdraw(uint256 _amount) external returns (uint256 burnAmount) {
        updateFundingPaidPerPosition();

        burnAmount = (_amount * totalSupply()) / poolPosition.usdcAmount;

        poolPosition.usdcAmount = poolPosition.usdcAmount.sub(_amount);

        TransferHelper.safeTransfer(usdc, msg.sender, _amount);

        _burn(msg.sender, burnAmount);
    }

    function updateMargin(uint256 _vaultId, int256 _marginAmount) external returns (uint256 traderVaultId) {
        require(_marginAmount != 0);

        FutureVault storage futureVault;

        (traderVaultId, futureVault) = _createOrGetVault(_vaultId, false);

        futureVault.marginAmount = PredyMath.addDelta(futureVault.marginAmount, _marginAmount);

        require(isVaultSafe(futureVault), "FM1");

        if (_marginAmount > 0) {
            TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), uint256(_marginAmount));
        } else if (_marginAmount < 0) {
            TransferHelper.safeTransfer(usdc, msg.sender, uint256(-_marginAmount));
        }
    }

    function trade(uint256 _vaultId, int256 _amount) external returns (uint256 traderVaultId) {
        updateFundingPaidPerPosition();

        uint256 entryPrice = _updatePoolPosition(_amount);

        FutureVault storage futureVault;

        (traderVaultId, futureVault) = _createOrGetVault(_vaultId, false);

        _updateTraderPosition(futureVault, _amount, entryPrice);
    }

    function liquidationCall(uint256 _vaultId) external {
        updateFundingPaidPerPosition();

        FutureVault storage futureVault = futureVaults[_vaultId];

        require(!isVaultSafe(futureVault), "FM2");

        int256 tradeAmount = -futureVaults[_vaultId].positionAmount;

        uint256 entryPrice = _updatePoolPosition(tradeAmount);

        _updateTraderPosition(futureVault, tradeAmount, entryPrice);
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

            uint256 beforeSqrtPrice = controller.getSqrtPrice();

            _coverAndRebalance(uint160(beforeSqrtPrice), poolPosition.positionAmount, _amount, tradeOption);

            uint256 afterSqrtPrice = controller.getSqrtPrice();

            entryPrice = SateliteLib.getTradePrice(reader.isMarginZero(), beforeSqrtPrice, afterSqrtPrice);
        }

        {
            int256 deltaMarginAmount;

            {
                (int256 newEntryPrice, int256 profitValue) = updateEntryPrice(
                    int256(poolPosition.entryPrice),
                    poolPosition.positionAmount,
                    int256(entryPrice),
                    _amount
                );

                poolPosition.entryPrice = newEntryPrice.toUint256();
                deltaMarginAmount += profitValue;
            }

            {
                (int256 entryFundingFee, int256 profitValue) = updateEntryPrice(
                    int256(poolPosition.entryFundingFee),
                    poolPosition.positionAmount,
                    int256(fundingPaidPerPosition),
                    _amount
                );

                poolPosition.entryFundingFee = entryFundingFee;
                deltaMarginAmount += profitValue;
            }

            poolPosition.usdcAmount = PredyMath.addDelta(poolPosition.usdcAmount, deltaMarginAmount);
        }

        poolPosition.positionAmount -= _amount;
    }

    function _updateTraderPosition(
        FutureVault storage _futureVault,
        int256 _amount,
        uint256 _entryPrice
    ) internal {
        int256 deltaMarginAmount;

        {
            (int256 newEntryPrice, int256 profitValue) = updateEntryPrice(
                int256(_futureVault.entryPrice),
                _futureVault.positionAmount,
                int256(_entryPrice),
                _amount
            );

            _futureVault.entryPrice = newEntryPrice.toUint256();
            deltaMarginAmount += profitValue;
        }

        {
            (int256 entryFundingFee, int256 profitValue) = updateEntryPrice(
                int256(_futureVault.entryFundingFee),
                _futureVault.positionAmount,
                int256(fundingPaidPerPosition),
                _amount
            );

            _futureVault.entryFundingFee = entryFundingFee;
            deltaMarginAmount += profitValue;
        }

        _futureVault.positionAmount += _amount;

        require(int256(_futureVault.marginAmount) >= -deltaMarginAmount, "A");
        _futureVault.marginAmount = PredyMath.addDelta(_futureVault.marginAmount, deltaMarginAmount);

        require(isVaultSafe(_futureVault), "FM1");
    }

    function isVaultSafe(FutureVault memory _futureVault) internal view returns (bool) {
        if (_futureVault.positionAmount == 0) {
            return true;
        }

        uint256 twap = reader.getTWAP();

        uint256 minCollateral = (twap * PredyMath.abs(_futureVault.positionAmount)) / 1e19;

        int256 positionValue = getPositionValue(_futureVault, twap);

        return positionValue > int256(minCollateral);
    }

    function getPositionValue(FutureVault memory _futureVault, uint256 _price) internal pure returns (int256) {
        return
            ((int256(_price) - int256(_futureVault.entryPrice)) * _futureVault.positionAmount) /
            1e18 +
            int256(_futureVault.marginAmount);
    }

    function _createOrGetVault(uint256 _vaultId, bool _quoterMode)
        internal
        returns (uint256 futureVaultId, FutureVault storage)
    {
        if (_vaultId == 0) {
            futureVaultId = futureVaultCount;

            futureVaults[futureVaultId].owner = msg.sender;

            futureVaultCount += 1;
        } else {
            futureVaultId = _vaultId;

            require(futureVaults[futureVaultId].owner == msg.sender || _quoterMode, "FM0");
        }

        return (futureVaultId, futureVaults[futureVaultId]);
    }

    function updateEntryPrice(
        int256 _entryPrice,
        int256 _position,
        int256 _tradePrice,
        int256 _positionTrade
    ) internal pure returns (int256 newEntryPrice, int256 profitValue) {
        int256 newPosition = _position.add(_positionTrade);
        if (_position == 0 || (_position > 0 && _positionTrade > 0) || (_position < 0 && _positionTrade < 0)) {
            newEntryPrice = (
                _entryPrice.mul(int256(PredyMath.abs(_position))).add(
                    _tradePrice.mul(int256(PredyMath.abs(_positionTrade)))
                )
            ).div(int256(PredyMath.abs(_position.add(_positionTrade))));
        } else if (
            (_position > 0 && _positionTrade < 0 && newPosition > 0) ||
            (_position < 0 && _positionTrade > 0 && newPosition < 0)
        ) {
            newEntryPrice = _entryPrice;
            profitValue = (-_positionTrade).mul(_tradePrice.sub(_entryPrice)) / 1e18;
        } else {
            if (newPosition != 0) {
                newEntryPrice = _tradePrice;
            }

            profitValue = _position.mul(_tradePrice.sub(_entryPrice)) / 1e18;
        }
    }

    function _coverAndRebalance(
        uint160 _sqrtPrice,
        int256 _poolPosition,
        int256 _amount,
        DataType.TradeOption memory tradeOption
    ) internal returns (int256 requiredAmount) {
        DataType.OpenPositionOption memory openPositionOption = DataType.OpenPositionOption(0, type(uint256).max, 500);

        DataType.PositionUpdate[] memory positionUpdates = _rebalance(
            _sqrtPrice,
            PredyMath.abs(_poolPosition),
            PredyMath.abs(_poolPosition + _amount)
        );

        positionUpdates[positionUpdates.length - 1] = _cover(poolPosition.positionAmount);

        (vaultId, requiredAmount, ) = controller.updatePosition(
            vaultId,
            positionUpdates,
            tradeOption,
            openPositionOption
        );

        require(int256(poolPosition.usdcAmount) >= requiredAmount, "B");
        poolPosition.usdcAmount = PredyMath.addDelta(poolPosition.usdcAmount, -requiredAmount);
    }

    function _cover(int256 _poolPosition) internal view returns (DataType.PositionUpdate memory) {
        uint256 delta = calculateDelta(PredyMath.abs(_poolPosition));

        int256 amount = _poolPosition + int256(delta);
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
        }
    }

    function _rebalance(
        uint160 _sqrtPrice,
        uint256 _poolPosition,
        uint256 _poolPositionAfter
    ) internal view returns (DataType.PositionUpdate[] memory positionUpdates) {
        int24 currentTick = TickMath.getTickAtSqrtRatio(_sqrtPrice);

        if (ranges[currentRangeId].lowerTick > currentTick) {
            return _rebalanceSwitch(currentRangeId, currentRangeId - 1, _poolPosition, _poolPositionAfter);
        }

        if (ranges[currentRangeId].upperTick < currentTick) {
            return _rebalanceSwitch(currentRangeId, currentRangeId + 1, _poolPosition, _poolPositionAfter);
        }

        return _rebalanceUpdate(int256(_poolPositionAfter) - int256(_poolPosition));
    }

    function _rebalanceUpdate(int256 _amount) internal view returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](2);

        if (_amount > 0) {
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.DEPOSIT_LPT,
                0,
                true,
                uint128((ranges[currentRangeId].liquidity * _amount) / 1e18),
                ranges[currentRangeId].lowerTick,
                ranges[currentRangeId].upperTick,
                0,
                0
            );
        } else if (_amount < 0) {
            positionUpdates[0] = DataType.PositionUpdate(
                DataType.PositionUpdateType.WITHDRAW_LPT,
                0,
                true,
                uint128((ranges[currentRangeId].liquidity * _amount) / 1e18),
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
        uint256 _amountBefore,
        uint256 _amountAfter
    ) internal view returns (DataType.PositionUpdate[] memory positionUpdates) {
        positionUpdates = new DataType.PositionUpdate[](3);

        positionUpdates[0] = DataType.PositionUpdate(
            DataType.PositionUpdateType.WITHDRAW_LPT,
            0,
            true,
            uint128((ranges[_prevRangeId].liquidity * _amountBefore) / 1e18),
            ranges[_prevRangeId].lowerTick,
            ranges[_prevRangeId].upperTick,
            0,
            0
        );
        positionUpdates[1] = DataType.PositionUpdate(
            DataType.PositionUpdateType.DEPOSIT_LPT,
            0,
            true,
            uint128((ranges[_nextRangeId].liquidity * _amountAfter) / 1e18),
            ranges[_nextRangeId].lowerTick,
            ranges[_nextRangeId].upperTick,
            0,
            0
        );
    }

    function calculateDelta(uint256 _poolPosition) internal view returns (uint256 delta) {
        Range memory range = ranges[currentRangeId];

        (delta, ) = LPTMath.getAmountsForLiquidity(
            controller.getSqrtPrice(),
            range.lowerTick,
            range.upperTick,
            uint128((range.liquidity * _poolPosition) / 1e18)
        );
    }

    function calculateUSDValue(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    ) internal view returns (uint256 amount) {
        uint160 lowerSqrtPrice = TickMath.getSqrtRatioAtTick(_lowerTick);
        uint160 upperSqrtPrice = TickMath.getSqrtRatioAtTick(_upperTick);

        if (reader.isMarginZero()) {
            amount = LiquidityAmounts.getAmount0ForLiquidity(lowerSqrtPrice, upperSqrtPrice, _liquidity);
        } else {
            amount = LiquidityAmounts.getAmount1ForLiquidity(lowerSqrtPrice, upperSqrtPrice, _liquidity);
        }
    }

    function getPosition(
        uint256 subVaultIndex,
        uint256 asset0,
        uint256 asset1,
        uint256 debt0,
        uint256 debt1,
        DataType.LPT[] memory lpts
    ) internal view returns (DataType.Position memory) {
        if (reader.isMarginZero()) {
            return DataType.Position(subVaultIndex, asset0, asset1, debt0, debt1, lpts);
        } else {
            return DataType.Position(subVaultIndex, asset0, asset1, debt0, debt1, lpts);
        }
    }

    function updateFundingPaidPerPosition() internal {
        updateFundingPaidPerPosition(reader.getTWAP(), calculateFundingRate());
    }

    function updateFundingPaidPerPosition(uint256 twap, int256 fundingRate) internal {
        int256 fundingPaid = (int256(twap) * fundingRate) / 1e18;

        fundingPaidPerPosition += (int256(block.timestamp - lastTradeTimestamp) * fundingPaid) / FUNDING_PERIOD;
        lastTradeTimestamp = block.timestamp;
    }

    function calculateFundingRate() internal returns (int256) {
        if (poolPosition.positionAmount > 0) {
            return 1e14;
        } else {
            return -1e14;
        }
    }
}
