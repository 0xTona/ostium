// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ChainUtils.sol";

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../interfaces/IOstiumTrading.sol";
import "../interfaces/IOstiumPairInfos.sol";

library TradingLib {
    using SafeCast for uint256;
    using SafeCast for uint192;

    uint64 constant PRECISION_18 = 1e18;
    uint32 constant PRECISION_6 = 1e6;
    uint16 constant PERCENT_BASE = 100e2; // 100% in precision 2 and also the MAX_SLIPPAGE_P

    function getOpenTradeRevert(
        IOstiumTradingStorage storageT,
        IOstiumPairsStorage pairsStored,
        address sender,
        IOstiumTradingStorage.Trade memory t,
        uint256 maxAllowedCollateral,
        uint32 takerFeeP,
        uint32 makerFeeP,
        IOstiumTradingStorage.BuilderFee memory bf
    ) external view {
        //@note
        //Intention
        //  1) Guard:
        //      revert if max user's trades per pair reached: `openTradesCount + pendingMarketOpenCount + openLimitOrdersCount > maxTradesPerPair`
        //      revert if max pending market orders reached: `pendingOrderIds[sender].length > maxPendingMarketOrders`
        //      revert if `leverage == 0 || leverage NOT IN (minLeverage, maxLeverage)`
        //      revert if `collateral > maxAllowedCollateral`
        //  2) Guard: revert if totalMaxFees >= collateral
        //       totalMaxFees = oracleFee + builderFee + maxOpeningFee
        //  3) Guard: revert if (collateral - totalMaxFees) * leverage < minLevPos
        //  4) Guard: revert if TP/SL prices are wrong relative to openPrice:
        //      Long  -> tp <= openPrice || sl >= openPrice
        //      Short -> tp <= openPrice || sl >= openPrice
        //Audit
        //  2) scale down can lead to insolvency later
        //  3) `collateral - totalMaxFees` is not the actual remaining collateral because fee can smaller than totalMaxFees
        //Follow-up
        //  A) 2) `/ PRECISION_6 / 100` instead of `/ PRECISION_6`?
        //      -> scale by 1e6, however % is further scaled by 1e2 later (poor convention of protocol)
        //      E.x: `builderFee` is scaled by 1e6
        //           MAX_BUILDER_FEE_PERCENT = 500_000 = 0.5% instead of = 0.5
        //

        //1 {
        if (
            storageT.openTradesCount(sender, t.pairIndex) + storageT.pendingMarketOpenCount(sender, t.pairIndex)
                    + storageT.openLimitOrdersCount(sender, t.pairIndex) >= storageT.maxTradesPerPair()
        ) revert IOstiumTrading.MaxTradesPerPairReached(sender, t.pairIndex);

        if (storageT.pendingOrderIdsCount(sender) >= storageT.maxPendingMarketOrders()) {
            revert IOstiumTrading.MaxPendingMarketOrdersReached(sender);
        }

        if (
            t.leverage == 0 || t.leverage < pairsStored.pairMinLeverage(t.pairIndex)
                || t.leverage > pairsStored.pairMaxLeverage(t.pairIndex)
        ) revert IOstiumTrading.WrongLeverage(t.leverage);

        if (t.collateral > maxAllowedCollateral) {
            revert IOstiumTrading.AboveMaxAllowedCollateral();
        }
        //} 1

        //2 {
        uint256 preFeeNotional = (t.collateral * t.leverage) / 100;

        uint256 oracleFee = pairsStored.pairOracleFee(t.pairIndex);

        uint256 builderFee = 0;
        if (bf.builder != address(0) && bf.builderFee > 0) {
            builderFee = (bf.builderFee * preFeeNotional) / PRECISION_6 / 100;
        }

        uint256 maxOpeningFee = (preFeeNotional * takerFeeP) / PRECISION_6 / 100;

        uint256 totalMaxFees = maxOpeningFee + oracleFee + builderFee;

        if (totalMaxFees >= t.collateral) {
            revert IOstiumTrading.BelowFees();
        }
        //} 2

        //3 {
        if (((t.collateral - totalMaxFees) * t.leverage) / 100 < pairsStored.pairMinLevPos(t.pairIndex)) {
            revert IOstiumTrading.BelowMinLevPos();
        }
        //} 3

        //4 {
        if (t.tp != 0 && (t.buy ? t.tp <= t.openPrice : t.tp >= t.openPrice)) {
            revert IOstiumTrading.WrongTP();
        }

        if (t.sl != 0 && (t.buy ? t.sl >= t.openPrice : t.sl <= t.openPrice)) {
            revert IOstiumTrading.WrongSL();
        }
        //} 4
    }

    function getCloseTradeRevert(
        IOstiumTradingStorage storageT,
        IOstiumPairsStorage pairsStorage,
        address sender,
        IOstiumTradingStorage.Trade memory t,
        IOstiumTradingStorage.TradeInfo memory i,
        uint256 triggerTimeout,
        uint16 closePercentage
    ) external view {
        //@note
        //Intention
        //  1) trade existed
        //  2) don't exceed maxPendingMarketOrders
        //  3) no pending triggers
        //      Note: in any orderType
        //  4) market is not closed
        //  5) only fully close OR partially close but remainning notional > minLevPos

        //1 {
        if (t.leverage == 0) {
            revert IOstiumTrading.NoTradeFound(sender, t.pairIndex, t.index);
        }
        //} 1

        //2 {
        if (storageT.pendingOrderIdsCount(sender) >= storageT.maxPendingMarketOrders()) {
            revert IOstiumTrading.MaxPendingMarketOrdersReached(sender);
        }
        //} 2

        //3 {
        if (!checkNoPendingTriggers(storageT, sender, t.pairIndex, t.index, triggerTimeout)) {
            revert IOstiumTrading.TriggerPending(sender, t.pairIndex, t.index);
        }
        //} 3

        //4 {
        if (i.beingMarketClosed) {
            revert IOstiumTrading.AlreadyMarketClosed(sender, t.pairIndex, t.index);
        }
        //} 4

        //5 {
        uint256 remainingCollateral = (t.collateral * (PERCENT_BASE - closePercentage)) / 100e2;
        if (
            closePercentage != PERCENT_BASE
                && (remainingCollateral * t.leverage) / 100 < pairsStorage.pairMinLevPos(t.pairIndex)
        ) {
            revert IOstiumTrading.BelowMinLevPos();
        }
        //} 5
    }

    function getUpdateOpenLimitOrderRevert(
        IOstiumTradingStorage storageT,
        address sender,
        IOstiumTradingStorage.OpenLimitOrder memory o,
        uint16 pairIndex,
        uint8 index,
        uint256 triggerTimeout
    ) external view {
        if (o.tp != 0 && (o.buy ? o.tp <= o.targetPrice : o.tp >= o.targetPrice)) {
            revert IOstiumTrading.WrongTP();
        }

        if (o.sl != 0 && (o.buy ? o.sl >= o.targetPrice : o.sl <= o.targetPrice)) {
            revert IOstiumTrading.WrongSL();
        }

        if (!checkNoPendingTrigger(
                storageT, sender, pairIndex, index, IOstiumTradingStorage.LimitOrder.OPEN, triggerTimeout
            )) {
            revert IOstiumTrading.TriggerPending(sender, pairIndex, index);
        }
    }

    function getCancelOpenLimitOrderRevert(
        IOstiumTradingStorage storageT,
        address sender,
        uint16 pairIndex,
        uint8 index,
        uint256 triggerTimeout
    ) external view {
        if (!storageT.hasOpenLimitOrder(sender, pairIndex, index)) {
            revert IOstiumTrading.NoLimitFound(sender, pairIndex, index);
        }

        if (!checkNoPendingTrigger(
                storageT, sender, pairIndex, index, IOstiumTradingStorage.LimitOrder.OPEN, triggerTimeout
            )) {
            revert IOstiumTrading.TriggerPending(sender, pairIndex, index);
        }
    }

    function checkNoPendingTrigger(
        IOstiumTradingStorage storageT,
        address trader,
        uint16 pairIndex,
        uint8 index,
        IOstiumTradingStorage.LimitOrder orderType,
        uint256 triggerTimeout
    ) public view returns (bool) {
        //@note
        //Intention
        //  triggerBlock == 0 || within `triggerTimeout` since `last triggerBlock`

        uint256 triggerBlock = storageT.orderTriggerBlock(trader, pairIndex, index, orderType);

        if (triggerBlock == 0 || (triggerBlock > 0 && ChainUtils.getBlockNumber() - triggerBlock >= triggerTimeout)) {
            return true;
        }
        return false;
    }

    function checkNoPendingTriggers(
        IOstiumTradingStorage storageT,
        address trader,
        uint16 pairIndex,
        uint8 index,
        uint256 triggerTimeout
    ) public view returns (bool) {
        return checkNoPendingTrigger(
            storageT, trader, pairIndex, index, IOstiumTradingStorage.LimitOrder.TP, triggerTimeout
        )
            && checkNoPendingTrigger(
            storageT, trader, pairIndex, index, IOstiumTradingStorage.LimitOrder.SL, triggerTimeout
        )
            && checkNoPendingTrigger(
            storageT, trader, pairIndex, index, IOstiumTradingStorage.LimitOrder.LIQ, triggerTimeout
        )
            && checkNoPendingTrigger(
            storageT, trader, pairIndex, index, IOstiumTradingStorage.LimitOrder.CLOSE_DAY_TRADE, triggerTimeout
        )
            && checkNoPendingTrigger(
            storageT, trader, pairIndex, index, IOstiumTradingStorage.LimitOrder.REMOVE_COLLATERAL, triggerTimeout
        );
    }
}
