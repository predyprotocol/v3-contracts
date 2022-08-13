Predy V3
=====

![](https://github.com/predyprotocol/v3-draft/workflows/test/badge.svg)

## Overview

Predy V3 is an oracle-free derivative protocol.


### Contracts

`Controller.sol` is entry point.
`ContractHelper.sol` has helper functions for creating transaction to update positions.

### Libraries

`BaseToken.sol` has basic functions to handle interest.

`InterestCalculator.sol` calculates interest and daily premium.

`PositionCalculator.sol` calculates required collateral for specific position.

`PositionUpdator.sol` updates vault and LPT state.

`VaultLib.sol` has functions to manage vault state.

`LPTStateLib.sol` has functions to manage LPT state.
