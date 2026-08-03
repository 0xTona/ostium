# Omission of soft limit checks in execution callbacks allows pending limit orders to bypass updated collateral and leverage constraints

## Summary

The `getAutomationOpenOrderCancelReason` and `getOpenTradeMarketCancelReason` functions in `TradingCallbacksLib.sol` fail to re-validate `pairMinLeverage`, `maxAllowedCollateral`, and `pairMinLevPos`. If governance updates these parameters while a limit order is pending, the order will execute using the outdated limits, opening an unallowed trade that violates the current protocol constraints.

## Root cause

When a user places a trade via `OstiumTrading.sol#openTrade`, the parameters `pairMinLeverage`, `maxAllowedCollateral`, and `pairMinLevPos` are correctly validated. The trade is then stored as a pending limit order or pending market order.

- https://github.com/0xOstium/smart-contracts-public/blob/8390ce497f68fb128900840e0ec30683afa945d3/src/lib/TradingLib.sol#L52-L76

```solidity
    function getOpenTradeRevert(...) external view {
        // ...
@>      if (t.leverage == 0 || t.leverage < pairsStored.pairMinLeverage(t.pairIndex) || t.leverage > maxLeverage) {
            revert IOstiumTrading.WrongLeverage(t.leverage);
        }

@>      if (t.collateral > maxAllowedCollateral) {
            revert IOstiumTrading.AboveMaxAllowedCollateral();
        }
        // ...
@>      if ((t.collateral - totalMaxFees) * t.leverage / 100 < pairsStored.pairMinLevPos(t.pairIndex)) {
            revert IOstiumTrading.BelowMinLevPos();
        }
    }
```

When the pending order is executed by a keeper, `OstiumTradingCallbacks` delegates the validation `getOpenTradeMarketCancelReason()` for market orders. However, these callbacks completely omit these checks.

- https://github.com/0xOstium/smart-contracts-public/blob/8390ce497f68fb128900840e0ec30683afa945d3/src/lib/TradingCallbacksLib.sol#L249-L293

Because limit orders can remain pending for `maxOrderAgeSeconds`, any governance updates to `pairMinLeverage`, `maxAllowedCollateral`, or `pairMinLevPos` during this period will be entirely bypassed.

## Impact

An unallowed trade can be successfully opened that directly violates the active risk parameters of the protocol.

## Likelihood

- Anyone with a pending limit order will inadvertently trigger this when the order hits its target price.
- It requires governance to update the parameters while the limit order is pending in the system.

## Proof of Concept

1. Governance sets `maxAllowedCollateral` to 100,000 USDC.
2. User places a `LIMIT_OPEN` order with 100,000 USDC collateral.
3. Market volatility increases; Governance lowers `maxAllowedCollateral` to 10,000 USDC to restrict maximum position sizes and protect the vault.
4. The asset price hits the user's limit order target.
5. The keeper executes `executeAutomationOpenOrderCallback`.
6. Result: The trade successfully opens with 100,000 USDC collateral, entirely bypassing the new 10,000 USDC limit and forcing the protocol to accept an unallowed trade size.

## Recommended Mitigation

Add the missing limit checks in `getOpenTradeMarketCancelReason` to ensure the trade complies with all current parameters at the exact time of execution.
