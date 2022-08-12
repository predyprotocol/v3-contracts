PredyV3
=====

![](https://github.com/predyprotocol/v3-draft/workflows/test/badge.svg)



ControllerHelper
* closePosition(limitPrice)
* liquidate(limitPrice)

Controller
* updatePosition
->PricingModule.applyFee
->PositionManager.updatePosition
  ->RangeLib.mintLPT
  ->VaultLib.depositLPT
->PositionCalculator.liquidationCheck

* liquidate
->PricingModule
->PositionManager
  ->RangeLib
  ->VaultLib
->PositionCalculator

* forceClose
->PricingModule
->PositionManager
  ->RangeLib
  ->VaultLib
->PositionCalculator

* getter



PricingModule.applyFee(vaultId)

// uni and a range
PricingModule.applyFee(range)

// tokenStates
PricingModule.updateInterest()

// uni, a vault and ranges and tokenStates
PositionManager.updatePosition


// a range
RangeLib
// a vault
VaultLib
// tokenState
BaseToken

// a vault and ranges and tokenState
PositionCalculator.liquidationCheck
