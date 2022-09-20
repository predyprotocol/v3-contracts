//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {TransferHelper} from "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "../interfaces/IControllerHelper.sol";
import "../interfaces/IReader.sol";
import "../libraries/LPTMath.sol";
import "../libraries/Constants.sol";
import "./BlackScholes.sol";

/**
 * OM0: caller is not option holder
 * OM1: board has not been expired
 * OM2: board has not been exercised
 */
contract OptionMarket is ERC20, IERC721Receiver {
    IControllerHelper internal controller;

    IReader internal reader;

    address internal usdc;

    uint256 private constant Q96 = 0x1000000000000000000000000;

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
        uint256 amount;
        bool isPut;
        address owner;
        uint256 premium;
    }

    uint256 public vaultId;

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
        controller = IControllerHelper(_controller);
        reader = IReader(_reader);
        usdc = _usdc;

        ERC20(usdc).approve(address(controller), type(uint256).max);

        strikeCount = 1;
        boardCount = 1;
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function createBoard(
        uint256 _expiration,
        int24[] memory _lowerTicks,
        int24[] memory _upperTicks
    ) external returns (uint256) {
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

        (uint128 liquidity, , ) = LPTMath.getLiquidityAndAmountToBorrow(true, 1e18, _lowerTick, _lowerTick, _upperTick);

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

        totalLiquidityAmount -= _amount;

        TransferHelper.safeTransfer(usdc, msg.sender, _amount);

        _burn(msg.sender, burnAmount);
    }

    function buy(
        uint256 _strikeId,
        uint256 _amount,
        uint256 _buffer,
        bool _isPut
    ) external returns (uint256 optionId) {
        TransferHelper.safeTransferFrom(usdc, msg.sender, address(this), _buffer);

        uint256 marginValue = getMarginValue(strikes[_strikeId].strikePrice, _amount, _isPut);

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            true,
            int256(marginValue),
            Constants.MARGIN_STAY,
            bytes("")
        );

        DataType.OpenPositionOption memory openPositionOption = DataType.OpenPositionOption(
            0,
            type(uint256).max,
            500
        );

        if (_isPut) {
            strikes[_strikeId].putPositionAmount += int256(_amount);
        } else {
            strikes[_strikeId].callPositionAmount += int256(_amount);
        }

        // cover
        (uint256 premium, int256 requiredAmount) = _buy(
            _strikeId,
            getPredyPosition(_strikeId, _amount, _isPut),
            tradeOption,
            openPositionOption,
            _isPut
        );

        boards[strikes[_strikeId].boardId].unrealizedProfit += int256(premium) - requiredAmount;

        optionId = createOptionPosition(_strikeId, _amount, _isPut, premium);

        TransferHelper.safeTransfer(usdc, msg.sender, _buffer - premium);
    }

    function sell(uint256 _positionId, uint256 _amount) external {
        OptionPosition storage optionPosition = optionPositions[_positionId];

        require(optionPosition.owner == msg.sender, "OM0");

        DataType.Position memory position = getPredyPosition(optionPosition.strikeId, _amount, optionPosition.isPut);

        DataType.TradeOption memory tradeOption = DataType.TradeOption(
            false,
            true,
            false,
            true,
            Constants.MARGIN_STAY,
            Constants.MARGIN_STAY,
            bytes("")
        );

        DataType.ClosePositionOption memory closePositionOption = DataType.ClosePositionOption(
            0,
            type(uint256).max,
            100,
            500
        );

        if (optionPosition.isPut) {
            strikes[optionPosition.strikeId].putPositionAmount -= int256(_amount);
        } else {
            strikes[optionPosition.strikeId].callPositionAmount -= int256(_amount);
        }

        // cover
        (uint256 premium, ) = _sell(
            optionPosition.strikeId,
            position,
            tradeOption,
            closePositionOption,
            optionPosition.isPut
        );

        optionPosition.amount -= _amount;

        boards[strikes[optionPosition.strikeId].boardId].unrealizedProfit -= int256(premium);

        TransferHelper.safeTransfer(usdc, msg.sender, premium);
    }

    function exicise(uint256 _boardId, uint256 _swapRatio) external {
        require(boards[_boardId].expiration <= block.timestamp, "OM1");

        DataType.TradeOption memory tradeOption = DataType.TradeOption(false, true, false, true, 0, 0, bytes(""));

        DataType.ClosePositionOption memory closePositionOption = DataType.ClosePositionOption(
            0,
            type(uint256).max,
            _swapRatio,
            500
        );

        {
            (uint256 indexPrice, int256 requiredAmount) = _exercise(tradeOption, closePositionOption);

            boards[_boardId].indexPrice = indexPrice;

            int256 totalProfit;

            for (uint256 i = 0; i < boards[_boardId].strikeIds.length; i++) {
                uint256 strikeId = boards[_boardId].strikeIds[i];

                totalProfit += getProfit(
                    indexPrice,
                    strikes[strikeId].strikePrice,
                    strikes[strikeId].callPositionAmount,
                    false
                );

                totalProfit += getProfit(
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

        int256 profit = getProfit(
            board.indexPrice,
            strikes[optionPosition.strikeId].strikePrice,
            int256(optionPosition.amount),
            optionPosition.isPut
        );

        optionPosition.amount = 0;

        TransferHelper.safeTransfer(usdc, msg.sender, uint256(profit));
    }

    function _buy(
        uint256 _strikeId,
        DataType.Position memory position,
        DataType.TradeOption memory tradeOption,
        DataType.OpenPositionOption memory openPositionOption,
        bool _isPut
    ) internal returns (uint256 premium, int256 requiredAmount) {
        Strike memory strike = strikes[_strikeId];

        uint256 beforeSqrtPrice = controller.getSqrtPrice();
        (vaultId, requiredAmount, ) = controller.openPosition(vaultId, position, tradeOption, openPositionOption);
        uint256 afterSqrtPrice = controller.getSqrtPrice();

        uint256 entryPrice = getTradePrice(beforeSqrtPrice, afterSqrtPrice);

        uint256 timeToMaturity = boards[strike.boardId].expiration - block.timestamp;

        premium = BlackScholes.calculatePrice(
            entryPrice,
            strike.strikePrice,
            timeToMaturity,
            getIV(_isPut ? strike.putPositionAmount : strike.callPositionAmount),
            _isPut
        );
    }

    function _sell(
        uint256 _strikeId,
        DataType.Position memory position,
        DataType.TradeOption memory tradeOption,
        DataType.ClosePositionOption memory closePositionOption,
        bool _isPut
    ) internal returns (uint256 premium, int256 requiredAmount) {
        Strike memory strike = strikes[_strikeId];

        DataType.Position[] memory positions = new DataType.Position[](1);

        positions[0] = position;

        uint256 beforeSqrtPrice = controller.getSqrtPrice();
        (requiredAmount, ) = controller.closePosition(vaultId, positions, tradeOption, closePositionOption);
        uint256 afterSqrtPrice = controller.getSqrtPrice();

        uint256 entryPrice = getTradePrice(beforeSqrtPrice, afterSqrtPrice);

        uint256 timeToMaturity = boards[strike.boardId].expiration - block.timestamp;

        premium = BlackScholes.calculatePrice(
            entryPrice,
            strike.strikePrice,
            timeToMaturity,
            getIV(_isPut ? strike.putPositionAmount : strike.callPositionAmount),
            _isPut
        );
    }

    function _exercise(DataType.TradeOption memory tradeOption, DataType.ClosePositionOption memory closePositionOption)
        internal
        returns (uint256 indexPrice, int256 requiredAmount)
    {
        uint256 beforeSqrtPrice = controller.getSqrtPrice();
        (requiredAmount, ) = controller.closeSubVault(vaultId, 0, tradeOption, closePositionOption);
        uint256 afterSqrtPrice = controller.getSqrtPrice();

        indexPrice = getTradePrice(beforeSqrtPrice, afterSqrtPrice);
    }

    function getPredyPosition(
        uint256 _strikeId,
        uint256 _amount,
        bool _isPut
    ) internal view returns (DataType.Position memory) {
        Strike memory strike = strikes[_strikeId];

        DataType.LPT[] memory lpts = new DataType.LPT[](1);

        lpts[0] = DataType.LPT(false, uint128((strike.liquidity * _amount) / 1e8), strike.lowerTick, strike.upperTick);

        if (_isPut) {
            return DataType.Position(0, (strike.strikePrice * _amount) / 1e8, 0, 0, 0, lpts);
        } else {
            return DataType.Position(0, 0, (1e18 * _amount) / 1e8, 0, 0, lpts);
        }
    }

    function createOptionPosition(
        uint256 _strikeId,
        uint256 _amount,
        bool _isPut,
        uint256 _premium
    ) internal returns (uint256) {
        uint256 id = optionPositionCount;

        optionPositions[id] = OptionPosition(id, _strikeId, _amount, _isPut, msg.sender, _premium);

        optionPositionCount += 1;

        return id;
    }

    function getTradePrice(uint256 beforeSqrtPrice, uint256 afterSqrtPrice) internal pure returns (uint256) {
        uint256 entryPrice = (1e18 * Q96) / afterSqrtPrice;

        return (entryPrice * Q96) / beforeSqrtPrice;
    }

    function calculateStrikePrice(int24 _lowerTick, int24 _upperTick) internal pure returns (uint256) {
        uint160 sqrtPrice = TickMath.getSqrtRatioAtTick((_lowerTick + _upperTick) / 2);

        return LPTMath.decodeSqrtPriceX96(true, sqrtPrice);
    }

    function getMarginValue(
        uint256 strikePrice,
        uint256 _amount,
        bool _isPut
    ) internal view returns (uint256 marginValue) {
        uint256 currentPrice = reader.getPrice();

        uint256 instinctValue;

        if (_isPut && strikePrice > currentPrice) {
            instinctValue = strikePrice - currentPrice;
        }

        if (!_isPut && strikePrice < currentPrice) {
            instinctValue = currentPrice - strikePrice;
        }

        marginValue = (currentPrice * _amount) / 1e8 / 5;
    }

    function getProfit(
        uint256 indexPrice,
        uint256 strikePrice,
        int256 _amount,
        bool _isPut
    ) internal pure returns (int256) {
        uint256 instinctValue;

        if (_isPut && strikePrice > indexPrice) {
            instinctValue = strikePrice - indexPrice;
        }

        if (!_isPut && strikePrice < indexPrice) {
            instinctValue = indexPrice - strikePrice;
        }

        return (int256(instinctValue) * _amount) / 1e8;
    }

    function getIV(int256 _poolPositionAmount) internal pure returns (uint256) {
        return 100 * 1e6;
    }
}