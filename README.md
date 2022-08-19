Predy V3
=====

![](https://github.com/predyprotocol/v3-draft/workflows/test/badge.svg)

## Overview

Predy V3 is an oracle-free derivative protocol.
This Protocol enables perpetual options by lending and borrowing Uniswap V3's Liquidity Provider Token(LPT).

### Contracts

`Controller.sol` is entry point of traders.

`ContractHelper.sol` has helper functions for creating transaction to update positions.

### Libraries

`BaseToken.sol` has functions to handle deposit and borrowing tokens.

`InterestCalculator.sol` has functions to calculate interest and daily premium.

`PositionCalculator.sol` has functions to calculate required collateral for positions.

`PositionUpdator.sol` has functions to update vault and LPT state.

`PositionLib.sol` has functions to calculate required token amounts and parameters which is required to update position.

`VaultLib.sol` has functions to manage vault state.

`LPTStateLib.sol` has functions to manage LPT state.

`LPTMath.sol` has wrapper functions of LiquidityAmounts library from uniswap core.
