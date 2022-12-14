//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "../interfaces/IController.sol";
import "../interfaces/IReader.sol";
import "../libraries/PriceHelper.sol";
import "../libraries/Constants.sol";
import "./BlackScholes.sol";
import "./SateliteLib.sol";

/**
 * OM0: caller is not option holder
 * OM1: board has not been expired
 * OM2: board has not been exercised
 */
contract OptionMarket is ERC20, IERC721Receiver, Ownable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;

    IController internal controller;

    IReader internal reader;

    address internal usdc;

    struct Strike {
        uint256 id;
        uint256 strikePrice;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        int256 callPositionAmount;
        int256 putPositionAmount;
        uint256 boardId;
    }

    struct Board {
        uint256 id;
        uint256 expiration;
        uint256 indexPrice;
        bool isExpired;
        int256 unrealizedProfit;
        uint256[] strikeIds;
    }

    struct OptionPosition {
        uint256 id;
        uint256 strikeId;
        int256 amount;
        bool isPut;
        address owner;
        uint256 premium;
        uint256 collateralAmount;
    }

    struct OptionTradeParams {
        bool isPut;
        bool isLong;
        bool isOpen;
    }

    uint256 public vaultId;

    uint256 public subVaultId;

    uint256 private strikeCount;

    uint256 private boardCount;

    uint256 private optionPositionCount;

    mapping(uint256 => Strike) internal strikes;

    mapping(uint256 => Board) internal boards;

    mapping(uint256 => OptionPosition) internal optionPositions;

    uint256 private totalLiquidityAmount;

    constructor(
        address _controller,
        address _reader,
        address _usdc
    ) ERC20("", "") {
        controller = IController(_controller);
        reader = IReader(_reader);
        usdc = _usdc;

        ERC20(usdc).approve(address(controller), type(uint256).max);

        strikeCount = 1;
        boardCount = 1;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice Creates new option board.
     * @param _expiration The timestamp when the board expires.
     * @param _lowerTicks The array of lower ticks indicates strike prices.
     * @param _upperTicks The array of upper ticks indicates strike prices.
     */
    function createBoard(
        uint256 _expiration,
        int24[] memory _lowerTicks,
        int24[] memory _upperTicks
    ) external onlyOwner returns (uint256) {
        uint256 id = boardCount;

        uint256[] memory strikeIds = new uint256[](_lowerTicks.length);

        for (uint256 i = 0; i < _lowerTicks.length; i++) {
            strikeIds[i] = createStrike(id, _lowerTicks[i], _upperTicks[i]);
        }

        boards[id] = Board(id, _expiration, 0, false, 0, strikeIds);

        boardCount += 1;

        return id;
    }

    function createStrike(
        uint256 _boardId,
        int24 _lowerTick,
        int24 _upperTick
    ) internal returns (uint256) {
        uint256 id = strikeCount;

        uint128 liquidity = SateliteLib.getBaseLiquidity(reader.isMarginZero(), _lowerTick, _upperTick);

        strikes[id] = Strike(
            id,
            calculateStrikePrice(_lowerTick, _upperTick),
            liquidity,
            _lowerTick,
            _upperTick,
            0,
            0,
            _boardId
        );

        strikeCount += 1;

        return id;
    }

    function getLPTokenPrice() external view returns (uint256) {
        return (Constants.ONE * totalLiquidityAmount) / totalSupply();
    }

    function deposit(uint256 _amount) external returns (uint256 mintAmount) {
        if (totalLiquidityAmount == 0) {
            mintAmount = _amount;
        } else {
            mintAmount = (_amount * totalSupply()) / totalLiquidityAmount;
        }

        totalLiquidityAmount += _amount;

        TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), _amount);

        _mint(msg.sender, mintAmount);
    }

    function withdraw(uint256 _amount) external returns (uint256 burnAmount) {
        burnAmount = (_amount * totalSupply()) / totalLiquidityAmount;

        totalLiquidityAmount = totalLiquidityAmount.sub(_amount);

        TransferHelper.safeTransfer(usdc, msg.sender, _amount);

        _burn(msg.sender, burnAmount);
    }

    /**
     * @notice Opens new position
     * @param _strikeId The id of the option series
     * @param _amount amount of options
     * @param _isPut is put option or call option
     * @param _collateralAmount amount of collateral
     */
    function openPosition(
        uint256 _strikeId,
        int256 _amount,
        bool _isPut,
        uint256 _collateralAmount
    ) external returns (uint256 optionId) {
        uint256 marginValue = getMarginValue(strikes[_strikeId], _amount, _isPut);

        int256 vaultValue = controller.getVaultValue(vaultId);

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            true,
            Constants.MARGIN_USE,
            Constants.MARGIN_STAY,
            int256(marginValue) - vaultValue,
            0,
            bytes("")
        );

        // cover
        (uint256 premium, int256 requiredAmount) = _trade(_strikeId, _amount, tradeOption, _isPut);

        if (_isPut) {
            strikes[_strikeId].putPositionAmount += _amount;
        } else {
            strikes[_strikeId].callPositionAmount += _amount;
        }

        boards[strikes[_strikeId].boardId].unrealizedProfit += int256(premium).sub(requiredAmount);

        optionId = createOptionPosition(_strikeId, _amount, _isPut, premium, _collateralAmount);

        require(isVaultSafe(optionPositions[optionId]), "OM8");

        if (_amount > 0) {
            TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), premium);
        } else if (_amount < 0) {
            // TODO: optimize
            TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), _collateralAmount);
            TransferHelper.safeTransfer(usdc, msg.sender, premium);
        }
    }

    // close position
    function closePosition(uint256 _positionId, uint256 _amount) external {
        OptionPosition storage optionPosition = optionPositions[_positionId];

        require(optionPosition.owner == msg.sender, "OM0");

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            true,
            Constants.MARGIN_STAY,
            Constants.MARGIN_STAY,
            0,
            0,
            bytes("")
        );

        int256 tradeAmount;

        if (optionPosition.amount > 0) {
            tradeAmount = -int256(_amount);

            require(optionPosition.amount >= -tradeAmount, "OM4");
        } else if (optionPosition.amount < 0) {
            tradeAmount = int256(_amount);

            require(-optionPosition.amount >= tradeAmount, "OM4");
        } else {
            revert("OM5");
        }

        // cover
        (uint256 premium, int256 requiredAmount) = _trade(
            optionPosition.strikeId,
            tradeAmount,
            tradeOption,
            optionPosition.isPut
        );

        if (optionPosition.isPut) {
            strikes[optionPosition.strikeId].putPositionAmount -= int256(_amount);
        } else {
            strikes[optionPosition.strikeId].callPositionAmount -= int256(_amount);
        }

        optionPosition.amount += tradeAmount;

        boards[strikes[optionPosition.strikeId].boardId].unrealizedProfit -= int256(premium) - requiredAmount;

        if (tradeAmount > 0) {
            TransferHelper.safeTransfer(usdc, msg.sender, optionPosition.collateralAmount - premium);
        } else if (tradeAmount < 0) {
            TransferHelper.safeTransfer(usdc, msg.sender, premium);
        }
    }

    /**
     * @notice Anyone can liquidate an unsafe short position.
     * @param _positionId The id of the position.
     */
    function liquidationCall(uint256 _positionId) external {
        OptionPosition storage optionPosition = optionPositions[_positionId];

        require(!isVaultSafe(optionPosition), "OM6");

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            true,
            Constants.MARGIN_STAY,
            Constants.MARGIN_STAY,
            0,
            0,
            bytes("")
        );

        int256 tradeAmount = -optionPosition.amount;

        (uint256 premium, int256 requiredAmount) = _trade(
            optionPosition.strikeId,
            tradeAmount,
            tradeOption,
            optionPosition.isPut
        );

        if (optionPosition.isPut) {
            strikes[optionPosition.strikeId].putPositionAmount += tradeAmount;
        } else {
            strikes[optionPosition.strikeId].callPositionAmount += tradeAmount;
        }

        optionPosition.amount = 0;

        boards[strikes[optionPosition.strikeId].boardId].unrealizedProfit -= int256(premium) - requiredAmount;

        // TODO: safeMath
        if (optionPosition.collateralAmount >= premium) {
            TransferHelper.safeTransfer(usdc, optionPosition.owner, optionPosition.collateralAmount - premium);
        }

        // TODO: liquidation reward
    }

    function isVaultSafe(OptionPosition memory _optionPosition) internal view returns (bool) {
        if (_optionPosition.amount >= 0) {
            return true;
        }

        uint256 twap = reader.getIndexPrice() / PriceHelper.PRICE_SCALER;

        Strike memory strike = strikes[_optionPosition.strikeId];

        uint256 timeToMaturity = boards[strike.boardId].expiration - block.timestamp;

        uint256 premium = BlackScholes.calculatePrice(
            twap,
            strike.strikePrice,
            timeToMaturity,
            getIV(_optionPosition.isPut ? strike.putPositionAmount : strike.callPositionAmount),
            _optionPosition.isPut
        );

        return (premium * 3) / 2 < _optionPosition.collateralAmount;
    }

    /**
     * @notice Exercise option board
     * anyone can exercise option board after expiration.
     * @param _boardId The id of the option board
     * @param _swapRatio todo
     */
    function exercise(uint256 _boardId, uint256 _swapRatio) external {
        require(boards[_boardId].expiration <= block.timestamp, "OM1");

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            true,
            Constants.MARGIN_USE,
            Constants.MARGIN_USE,
            Constants.FULL_WITHDRAWAL,
            Constants.FULL_WITHDRAWAL,
            bytes("")
        );

        DataType.ClosePositionOption memory closePositionOption = DataType.ClosePositionOption(
            0,
            type(uint256).max,
            _swapRatio,
            1e4,
            block.timestamp
        );

        {
            (uint256 indexPrice, int256 requiredAmount) = _exercise(tradeOption, closePositionOption);

            boards[_boardId].indexPrice = indexPrice;

            int256 totalProfit;

            for (uint256 i = 0; i < boards[_boardId].strikeIds.length; i++) {
                uint256 strikeId = boards[_boardId].strikeIds[i];

                totalProfit += SateliteLib.getProfit(
                    indexPrice,
                    strikes[strikeId].strikePrice,
                    strikes[strikeId].callPositionAmount,
                    false
                );

                totalProfit += SateliteLib.getProfit(
                    indexPrice,
                    strikes[strikeId].strikePrice,
                    strikes[strikeId].putPositionAmount,
                    true
                );
            }

            boards[_boardId].unrealizedProfit -= totalProfit + requiredAmount;
        }

        totalLiquidityAmount = PredyMath.addDelta(totalLiquidityAmount, boards[_boardId].unrealizedProfit);

        boards[_boardId].isExpired = true;
    }

    function claimProfit(uint256 _positionId) external {
        OptionPosition storage optionPosition = optionPositions[_positionId];
        Board memory board = boards[strikes[optionPosition.strikeId].boardId];

        require(optionPosition.owner == msg.sender, "OM0");
        require(board.isExpired, "OM2");

        int256 profit = SateliteLib.getProfit(
            board.indexPrice,
            strikes[optionPosition.strikeId].strikePrice,
            optionPosition.amount,
            optionPosition.isPut
        );

        uint256 collateralAmount = optionPosition.collateralAmount;

        optionPosition.amount = 0;
        optionPosition.collateralAmount = 0;

        // TODO: SafeMath
        TransferHelper.safeTransfer(usdc, msg.sender, uint256(int256(collateralAmount) + profit));
    }

    function _trade(
        uint256 _strikeId,
        int256 _amount,
        DataType.TradeOption memory tradeOption,
        bool _isPut
    ) internal returns (uint256 premium, int256 requiredAmount) {
        Strike memory strike = strikes[_strikeId];

        int256 poolAmount;

        if (_isPut) {
            poolAmount = strike.putPositionAmount;
        } else {
            poolAmount = strike.callPositionAmount;
        }

        uint256 beforeSqrtPrice = controller.getSqrtPrice();

        if (0 <= poolAmount && 0 < _amount) {
            requiredAmount = _addLong(_strikeId, uint256(_amount), tradeOption, _isPut);
        }
        if (0 <= poolAmount && 0 > _amount) {
            if (poolAmount < -_amount) {
                _removeLong(_strikeId, uint256(poolAmount), tradeOption, _isPut);
                requiredAmount = _addShort(_strikeId, uint256(-_amount - poolAmount), tradeOption, _isPut);
            } else {
                requiredAmount = _removeLong(_strikeId, uint256(-_amount), tradeOption, _isPut);
            }
        }

        if (0 > poolAmount && 0 > _amount) {
            requiredAmount = _addShort(_strikeId, uint256(-_amount), tradeOption, _isPut);
        }
        if (0 > poolAmount && 0 < _amount) {
            if (-poolAmount < _amount) {
                _removeShort(_strikeId, uint256(-poolAmount), tradeOption, _isPut);
                requiredAmount = _addLong(_strikeId, uint256(_amount + poolAmount), tradeOption, _isPut);
            } else {
                requiredAmount = _removeShort(_strikeId, uint256(_amount), tradeOption, _isPut);
            }
        }

        uint256 afterSqrtPrice = controller.getSqrtPrice();

        uint256 entryPrice = SateliteLib.getTradePrice(reader.isMarginZero(), beforeSqrtPrice, afterSqrtPrice);

        uint256 timeToMaturity = boards[strike.boardId].expiration - block.timestamp;

        premium = BlackScholes.calculatePrice(
            entryPrice,
            strike.strikePrice,
            timeToMaturity,
            getIV(_isPut ? strike.putPositionAmount : strike.callPositionAmount),
            _isPut
        );
    }

    function _addLong(
        uint256 _strikeId,
        uint256 _amount,
        DataType.TradeOption memory tradeOption,
        bool _isPut
    ) internal returns (int256 requiredAmount) {
        DataType.Position memory position = getPredyPosition(_strikeId, _amount, _isPut, true);

        DataType.OpenPositionOption memory openPositionOption = DataType.OpenPositionOption(
            0,
            type(uint256).max,
            100,
            block.timestamp
        );

        DataType.TokenAmounts memory requiredAmounts;

        (vaultId, requiredAmounts, ) = controller.openPosition(vaultId, position, tradeOption, openPositionOption);

        updateSubVaultId();

        if (reader.isMarginZero()) {
            return requiredAmounts.amount0;
        } else {
            return requiredAmounts.amount1;
        }
    }

    function _addShort(
        uint256 _strikeId,
        uint256 _amount,
        DataType.TradeOption memory tradeOption,
        bool _isPut
    ) internal returns (int256 requiredAmount) {
        DataType.Position memory position = getPredyPosition(_strikeId, _amount, _isPut, false);

        DataType.OpenPositionOption memory openPositionOption = DataType.OpenPositionOption(
            0,
            type(uint256).max,
            100,
            block.timestamp
        );

        DataType.TokenAmounts memory requiredAmounts;

        (vaultId, requiredAmounts, ) = controller.openPosition(vaultId, position, tradeOption, openPositionOption);

        updateSubVaultId();

        if (reader.isMarginZero()) {
            return requiredAmounts.amount0;
        } else {
            return requiredAmounts.amount1;
        }
    }

    function _removeLong(
        uint256 _strikeId,
        uint256 _amount,
        DataType.TradeOption memory tradeOption,
        bool _isPut
    ) internal returns (int256 requiredAmount) {
        DataType.Position[] memory positions = new DataType.Position[](1);

        positions[0] = getPredyPosition(_strikeId, _amount, _isPut, true);

        DataType.ClosePositionOption memory closePositionOption = DataType.ClosePositionOption(
            0,
            type(uint256).max,
            100,
            1e4,
            block.timestamp
        );

        DataType.TokenAmounts memory requiredAmounts;

        (requiredAmounts, ) = controller.closePosition(vaultId, positions, tradeOption, closePositionOption);

        updateSubVaultId();

        if (reader.isMarginZero()) {
            return requiredAmounts.amount0;
        } else {
            return requiredAmounts.amount1;
        }
    }

    function _removeShort(
        uint256 _strikeId,
        uint256 _amount,
        DataType.TradeOption memory tradeOption,
        bool _isPut
    ) internal returns (int256 requiredAmount) {
        DataType.Position[] memory positions = new DataType.Position[](1);

        positions[0] = getPredyPosition(_strikeId, _amount, _isPut, false);

        DataType.ClosePositionOption memory closePositionOption = DataType.ClosePositionOption(
            0,
            type(uint256).max,
            100,
            1e4,
            block.timestamp
        );

        DataType.TokenAmounts memory requiredAmounts;

        (requiredAmounts, ) = controller.closePosition(vaultId, positions, tradeOption, closePositionOption);

        updateSubVaultId();

        if (reader.isMarginZero()) {
            return requiredAmounts.amount0;
        } else {
            return requiredAmounts.amount1;
        }
    }

    function updateSubVaultId() internal {
        // Set SubVault ID
        DataType.Vault memory vault = controller.getVault(vaultId);

        if (vault.subVaults.length > 0) {
            subVaultId = vault.subVaults[0];
        } else {
            // if subVault removed
            subVaultId = 0;
        }
    }

    function _exercise(DataType.TradeOption memory tradeOption, DataType.ClosePositionOption memory closePositionOption)
        internal
        returns (uint256 indexPrice, int256 requiredAmount)
    {
        DataType.TokenAmounts memory requiredAmounts;
        DataType.TokenAmounts memory swapAmounts;

        DataType.Vault memory vault = controller.getVault(vaultId);

        (requiredAmounts, swapAmounts) = controller.closeSubVault(
            vaultId,
            vault.subVaults[0],
            tradeOption,
            closePositionOption
        );

        indexPrice = SateliteLib.getEntryPrice(reader.isMarginZero(), swapAmounts);

        if (reader.isMarginZero()) {
            requiredAmount = requiredAmounts.amount0;
        } else {
            requiredAmount = requiredAmounts.amount1;
        }
    }

    function getPredyPosition(
        uint256 _strikeId,
        uint256 _amount,
        bool _isPut,
        bool _isLong
    ) internal view returns (DataType.Position memory) {
        Strike memory strike = strikes[_strikeId];

        DataType.LPT[] memory lpts = new DataType.LPT[](1);

        uint256 baseUsdcAmount = calculateUSDValue(strike.lowerTick, strike.upperTick, strike.liquidity);

        if (_isLong) {
            lpts[0] = DataType.LPT(
                false,
                uint128((strike.liquidity * _amount) / 1e8),
                strike.lowerTick,
                strike.upperTick
            );

            if (_isPut) {
                return getPosition((baseUsdcAmount * _amount) / 1e8, 0, 0, 0, lpts);
            } else {
                return getPosition(0, (1e18 * _amount) / 1e8, 0, 0, lpts);
            }
        } else {
            lpts[0] = DataType.LPT(
                true,
                uint128((strike.liquidity * _amount) / 1e8),
                strike.lowerTick,
                strike.upperTick
            );

            if (_isPut) {
                return getPosition(0, 0, ((baseUsdcAmount * _amount) * 75) / 1e10, 0, lpts);
            } else {
                return getPosition(((baseUsdcAmount * _amount) * 25) / 1e10, 0, 0, (1e18 * _amount) / 1e8, lpts);
            }
        }
    }

    function createOptionPosition(
        uint256 _strikeId,
        int256 _amount,
        bool _isPut,
        uint256 _premium,
        uint256 _collateralAmount
    ) internal returns (uint256) {
        uint256 id = optionPositionCount;

        optionPositions[id] = OptionPosition(id, _strikeId, _amount, _isPut, msg.sender, _premium, _collateralAmount);

        optionPositionCount += 1;

        return id;
    }

    function getTradePrice(uint256 beforeSqrtPrice, uint256 afterSqrtPrice) internal pure returns (uint256) {
        uint256 entryPrice = (1e18 * Constants.Q96) / afterSqrtPrice;

        return (entryPrice * Constants.Q96) / beforeSqrtPrice;
    }

    function calculateStrikePrice(int24 _lowerTick, int24 _upperTick) internal pure returns (uint256) {
        uint160 sqrtPrice = TickMath.getSqrtRatioAtTick((_lowerTick + _upperTick) / 2);

        return PriceHelper.decodeSqrtPriceX96(true, sqrtPrice) / PriceHelper.PRICE_SCALER;
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

    function getMarginValue(
        Strike memory _strike,
        int256 _amount,
        bool _isPut
    ) internal view returns (uint256 marginValue) {
        uint256 currentPrice = reader.getPrice() / PriceHelper.PRICE_SCALER;

        uint256 instinctValue;

        if (_isPut && _strike.strikePrice > currentPrice) {
            instinctValue = _strike.strikePrice - currentPrice;
        }

        if (!_isPut && _strike.strikePrice < currentPrice) {
            instinctValue = currentPrice - _strike.strikePrice;
        }

        int256 poolAmount;

        if (_isPut) {
            poolAmount = _strike.putPositionAmount;
        } else {
            poolAmount = _strike.callPositionAmount;
        }

        marginValue = (currentPrice * PredyMath.abs(poolAmount + _amount)) / 1e8 / 2;
    }

    function getIV(int256 _poolPositionAmount) internal pure returns (uint256) {
        return 100 * 1e6;
    }

    function getPosition(
        uint256 asset0,
        uint256 asset1,
        uint256 debt0,
        uint256 debt1,
        DataType.LPT[] memory lpts
    ) internal view returns (DataType.Position memory) {
        if (reader.isMarginZero()) {
            return DataType.Position(subVaultId, asset0, asset1, debt0, debt1, lpts);
        } else {
            return DataType.Position(subVaultId, asset0, asset1, debt0, debt1, lpts);
        }
    }
}
