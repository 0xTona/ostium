// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

<<<<<<< HEAD
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "../interfaces/IOstiumTradingStorage.sol";
import "../interfaces/IOstiumPairInfos.sol";
import "../interfaces/IOstiumRegistry.sol";
import "../interfaces/IOstiumVault.sol";
import "../interfaces/IOstiumPairsStorage.sol";
import "../interfaces/IOstiumTradingCallbacks.sol";
=======
import '@openzeppelin/contracts/utils/math/SafeCast.sol';
import '@openzeppelin/contracts/utils/math/SignedMath.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '../interfaces/IOstiumTradingStorage.sol';
import '../interfaces/IOstiumPairInfos.sol';
import '../interfaces/IOstiumRegistry.sol';
import '../interfaces/IOstiumVault.sol';
import '../interfaces/IOstiumPairsStorage.sol';
import '../interfaces/IOstiumTradingCallbacks.sol';
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3

library TradingCallbacksLib {
    using SafeCast for uint256;
    using SafeCast for uint192;

    uint256 constant PRECISION_27 = 1e27;
    uint64 constant PRECISION_18 = 1e18;
    uint64 constant PRECISION_10 = 1e10;
    uint32 constant PRECISION_6 = 1e6;
    uint16 constant MAX_GAIN_P = 900; // 900% PnL (10x)
    uint64 constant MAX_DECAY_FACTOR = 3e18; // 18 decimals

    struct PriceImpactResult {
        uint256 priceImpactP;
        uint256 priceAfterImpact;
        bool isDynamic;
    }

    struct TradeValueResult {
        uint256 tradeValue;
        uint256 liqMarginValue;
        int256 rolloverFees;
        int256 fundingFees;
        int256 profitP;
    }

    function _getTradePriceImpact(int192 price, int192 ask, int192 bid, bool isOpen, bool isLong)
        internal
        pure
        returns (uint256 priceImpactP, uint256 priceAfterImpact)
    {
        //@note
        //Intention
        //  1) Open long or close short => usedPrice = ask
        //     Else                     => usedPrice = bid
        //  2) priceImpactP = |price - usedPrice| * 1e18 / price * 100

        if (price == 0) {
            return (0, 0);
        }
        bool aboveSpot = (isOpen == isLong);

        int192 usedPrice = aboveSpot ? ask : bid;

<<<<<<< HEAD
        priceImpactP = (((SignedMath.abs(price - usedPrice) * PRECISION_18) / uint192(price)) * 100);
=======
        priceImpactP = (SignedMath.abs(price - usedPrice) * PRECISION_18 * 100 / uint192(price));
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3

        return (priceImpactP, uint192(usedPrice));
    }

    function _currentPercentProfit(
        int256 openPrice,
        int256 currentPrice,
        bool buy,
        int32 leverage,
        int32 initialLeverage
    ) internal pure returns (int256 p, int256 maxPnlP) {
        //@note
        //Intention
        //  maxPnlP = 900% * leverage / max(leverage, initialLeverage)
        //  p = |currentPrice - openPrice| * leverage / openPrice
        //  p = max(p, maxPnlP)
        //Audit
        //  round down to zero?

        maxPnlP = (int16(MAX_GAIN_P) * int32(PRECISION_6) * int256(leverage))
            / (leverage > initialLeverage ? leverage : initialLeverage);

        p = ((buy ? currentPrice - openPrice : openPrice - currentPrice) * int32(PRECISION_6) * leverage) / openPrice;

        p = p > maxPnlP ? maxPnlP : p;
    }

    function currentPercentProfit(
        int256 openPrice,
        int256 currentPrice,
        bool buy,
        int32 leverage,
        int32 initialLeverage
    ) public pure returns (int256 p, int256 maxPnlP) {
        return _currentPercentProfit(openPrice, currentPrice, buy, leverage, initialLeverage);
    }

    function correctTp(uint192 openPrice, uint192 tp, uint32 leverage, uint32 initialLeverage, bool buy)
        public
        pure
        returns (uint192)
    {
        //@note
        //Intention
        //  If tp == 0 || p == maxPnlP:
        //      tpDiff = (openPrice * |maxPnlP|) / leverage
        //          tpDiff is the distance between openPrice and price that trader win maxPnlP
        //      If buy -> return openPrice + tpDiff
        //      Else   -> return max(openPrice - tpDiff, 0)
        //Audit
        //  Bypass if  p != maxPnlP?

        (int256 p, int256 maxPnlP) =
            _currentPercentProfit(openPrice.toInt256(), tp.toInt256(), buy, int32(leverage), int32(initialLeverage));

        if (tp == 0 || p == maxPnlP) {
            uint256 tpDiff = (openPrice * SignedMath.abs(maxPnlP)) / PRECISION_6 / leverage;
            return (buy ? openPrice + tpDiff : (tpDiff <= openPrice ? openPrice - tpDiff : 0)).toUint192();
        }
        return tp;
    }

    function correctSl(uint192 openPrice, uint192 sl, uint32 leverage, uint32 initialLeverage, bool buy, uint8 maxSl_P)
        public
        pure
        returns (uint192)
    {
        (int256 p,) =
            _currentPercentProfit(openPrice.toInt256(), sl.toInt256(), buy, int32(leverage), int32(initialLeverage));
        if (sl > 0 && p < int8(maxSl_P) * int32(PRECISION_6) * -1) {
            uint256 slDiff = (openPrice * maxSl_P) / leverage;
            return (buy ? openPrice - slDiff : openPrice + slDiff).toUint192();
        }
        return sl;
    }

    function correctToNullSl(
        uint192 openPrice,
        uint192 sl,
        uint32 leverage,
        uint32 initialLeverage,
        bool buy,
        uint8 maxSl_P
    ) external pure returns (uint192) {
<<<<<<< HEAD
        //@note
        //Audit
        //  N) Unsafe cast int8(maxSl_P)
        //      -> max 100 is 1100100b

        (int256 p,) =
            _currentPercentProfit(openPrice.toInt256(), sl.toInt256(), buy, int32(leverage), int32(initialLeverage));
=======
        (int256 p,) = _currentPercentProfit(
            openPrice.toInt256(), sl.toInt256(), buy, int32(leverage), int32(initialLeverage)
        );
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
        if (sl > 0 && p < int8(maxSl_P) * int32(PRECISION_6) * -1) {
            return 0;
        }
        return sl;
    }

    /// @notice Returns the effective max leverage for a trade based on whether it's a day trade or overnight trade
    /// @dev When overnightMaxLeverage is 0, all trades are overnight and use pairMaxLeverage
    ///      When overnightMaxLeverage > 0, day trades use pairMaxLeverage, overnight trades use overnightMaxLeverage
    /// @dev Duplicated in TradingLib, update it there as well.
    function getEffectiveMaxLeverage(uint16 pairIndex, bool isDayTrade, IOstiumPairsStorage pairsStorage)
        public
        view
        returns (uint32)
    {
        uint32 overnightMaxLeverage = pairsStorage.pairOvernightMaxLeverage(pairIndex);
        return isDayTrade
            ? pairsStorage.pairMaxLeverage(pairIndex)
            : (overnightMaxLeverage > 0 ? overnightMaxLeverage : pairsStorage.pairMaxLeverage(pairIndex));
    }

    function withinMaxLeverage(uint16 pairIndex, uint256 leverage, bool isDayTrade, IOstiumPairsStorage pairsStorage)
        public
        view
        returns (bool)
    {
        return leverage <= getEffectiveMaxLeverage(pairIndex, isDayTrade, pairsStorage);
    }

    function withinExposureLimits(
        uint16 pairIndex,
        bool buy,
        uint256 collateral,
        uint32 leverage,
        uint256 price,
        IOstiumPairsStorage pairsStorage,
        IOstiumTradingStorage tradingStorage
    ) public view returns (bool) {
<<<<<<< HEAD
        //@note
        //Intention
        //  Enforce MaxExposure
        //      1) currentOI (in notional terms) + newNotional <= maxOpenInterest
        //          Where:
        //              openInterest(pairIndex, 0) = current long OI
        //              openInterest(pairIndex, 1) = current short OI
        //              openInterest(pairIndex, 2) = maxOpenInterest
        //              newNotional = collateral * leverage / 100
        //      2) current group collateral + newCollateral  <= maxGroupCollateral
        //Follow-up
        //  A) 1) PRECISION_18 / 1e12?
        //      -> Notional is scaled 1e6 and openInterest * price is scaled 1e36

        return (tradingStorage.openInterest(pairIndex, buy ? 0 : 1) * price) / PRECISION_18 / 1e12
                    + (collateral * leverage) / 100 <= tradingStorage.openInterest(pairIndex, 2)
=======
        return tradingStorage.openInterest(pairIndex, buy ? 0 : 1) * price / PRECISION_18 / 1e12 + collateral * leverage
                    / 100 <= tradingStorage.openInterest(pairIndex, 2)
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
            && pairsStorage.groupCollateral(pairIndex, buy) + collateral <= pairsStorage.groupMaxCollateral(pairIndex);
    }

    function getTradeAndPriceData(
        IOstiumPriceUpKeep.PriceUpKeepAnswer calldata a,
        IOstiumTradingStorage.Trade calldata t,
        IOstiumPairInfos pairInfos,
        uint32 initialLeverage,
        uint32 maxLeverage,
        uint256 collateral,
        bool isMarketPrice
    ) external returns (TradeValueResult memory, PriceImpactResult memory) {
        PriceImpactResult memory result =
            getDynamicTradePriceImpact(a.price, a.ask, a.bid, false, t, pairInfos, collateral);

        (int256 profitP,) = currentPercentProfit(
            t.openPrice.toInt256(),
            isMarketPrice ? a.price : result.priceAfterImpact.toInt256(),
            t.buy,
            int32(t.leverage),
            int32(initialLeverage)
        );

        (uint256 tradeValue, uint256 liqMarginValue, int256 rolloverFees, int256 fundingFees) =
            pairInfos.getTradeValue(t.trader, t.pairIndex, t.index, t.buy, collateral, t.leverage, profitP, maxLeverage);

        return (
            TradeValueResult({
                tradeValue: tradeValue,
                liqMarginValue: liqMarginValue,
                rolloverFees: rolloverFees,
                fundingFees: fundingFees,
                profitP: profitP
            }),
            result
        );
    }

    function getOpenTradeMarketCancelReason(
        bool isPaused,
        uint256 wantedPrice,
        uint256 slippageP,
        uint192 a_price,
        IOstiumTradingStorage.Trade memory trade,
        uint256 priceImpactP,
        IOstiumPairInfos pairInfos,
        IOstiumPairsStorage pairsStorage,
        IOstiumTradingStorage tradingStorage
    ) external view returns (IOstiumTradingCallbacks.CancelReason) {
        uint256 maxSlippage = (wantedPrice * slippageP) / 100 / 100;

        if (isPaused) return IOstiumTradingCallbacks.CancelReason.PAUSED;

        // Check slippage
        if (trade.buy ? trade.openPrice > wantedPrice + maxSlippage : trade.openPrice < wantedPrice - maxSlippage) {
            return IOstiumTradingCallbacks.CancelReason.SLIPPAGE;
        }

        // Check if TP is reached
        if (trade.tp != 0 && (trade.buy ? trade.openPrice >= trade.tp : trade.openPrice <= trade.tp)) {
            return IOstiumTradingCallbacks.CancelReason.TP_REACHED;
        }

        // Check if SL is reached
        if (trade.sl != 0 && (trade.buy ? trade.openPrice <= trade.sl : trade.openPrice >= trade.sl)) {
            return IOstiumTradingCallbacks.CancelReason.SL_REACHED;
        }

        // Check exposure limits
        if (!withinExposureLimits(
                trade.pairIndex, trade.buy, trade.collateral, trade.leverage, a_price, pairsStorage, tradingStorage
            )) {
            return IOstiumTradingCallbacks.CancelReason.EXPOSURE_LIMITS;
        }

        // Check price impact
        if ((priceImpactP * trade.leverage) / 100 / PRECISION_18 > pairInfos.maxNegativePnlOnOpenP()) {
            return IOstiumTradingCallbacks.CancelReason.PRICE_IMPACT;
        }

        // Check max leverage
        if (!withinMaxLeverage(trade.pairIndex, trade.leverage, trade.isDayTrade, pairsStorage)) {
            return IOstiumTradingCallbacks.CancelReason.MAX_LEVERAGE;
        }

        return IOstiumTradingCallbacks.CancelReason.NONE;
    }

    function getAutomationOpenOrderCancelReason(
        IOstiumTradingStorage.OpenLimitOrder memory o,
        uint256 priceAfterImpact,
        uint256 a_price,
        uint256 priceImpactP,
        IOstiumPairInfos pairInfos,
        IOstiumPairsStorage pairsStorage,
        IOstiumTradingStorage tradingStorage
    ) external view returns (IOstiumTradingCallbacks.CancelReason) {
        // Check if price target is hit based on order type
        bool isNotHit = o.orderType == IOstiumTradingStorage.OpenOrderType.LIMIT
            ? (o.buy ? priceAfterImpact > o.targetPrice : priceAfterImpact < o.targetPrice)
            : (o.buy ? uint192(a_price) < o.targetPrice : uint192(a_price) > o.targetPrice);

        if (isNotHit) return IOstiumTradingCallbacks.CancelReason.NOT_HIT;

        // Check if TP is reached
        if (o.tp != 0 && (o.buy ? priceAfterImpact >= o.tp : priceAfterImpact <= o.tp)) {
            return IOstiumTradingCallbacks.CancelReason.TP_REACHED;
        }

        // Check if SL is reached
        if (o.sl != 0 && (o.buy ? priceAfterImpact <= o.sl : priceAfterImpact >= o.sl)) {
            return IOstiumTradingCallbacks.CancelReason.SL_REACHED;
        }

        // Check exposure limits
        if (!withinExposureLimits(
                o.pairIndex, o.buy, o.collateral, o.leverage, uint192(a_price), pairsStorage, tradingStorage
            )) {
            return IOstiumTradingCallbacks.CancelReason.EXPOSURE_LIMITS;
        }

        // Check price impact
        if ((priceImpactP * o.leverage) / 100 / PRECISION_18 > pairInfos.maxNegativePnlOnOpenP()) {
            return IOstiumTradingCallbacks.CancelReason.PRICE_IMPACT;
        }

        // Check max leverage
        if (!withinMaxLeverage(o.pairIndex, o.leverage, o.isDayTrade, pairsStorage)) {
            return IOstiumTradingCallbacks.CancelReason.MAX_LEVERAGE;
        }

        return IOstiumTradingCallbacks.CancelReason.NONE;
    }

    function getAutomationCloseOrderCancelReason(
        IOstiumTradingStorage.LimitOrder orderType,
        IOstiumTradingStorage.Trade memory t,
        uint256 triggerPrice,
        uint256 usdcSentToTrader,
        bool isDayTradingClosed
    ) external pure returns (IOstiumTradingCallbacks.CancelReason) {
        if (orderType == IOstiumTradingStorage.LimitOrder.CLOSE_DAY_TRADE) {
            return (t.isDayTrade && isDayTradingClosed)
                ? IOstiumTradingCallbacks.CancelReason.NONE
                : IOstiumTradingCallbacks.CancelReason.CLOSE_DAY_TRADE_NOT_ALLOWED;
        } else if (orderType == IOstiumTradingStorage.LimitOrder.LIQ) {
            return usdcSentToTrader == 0
                ? IOstiumTradingCallbacks.CancelReason.NONE
                : IOstiumTradingCallbacks.CancelReason.NOT_HIT;
        } else if (orderType == IOstiumTradingStorage.LimitOrder.TP) {
            return t.tp > 0 && (t.buy ? triggerPrice >= t.tp : triggerPrice <= t.tp)
                ? IOstiumTradingCallbacks.CancelReason.NONE
                : IOstiumTradingCallbacks.CancelReason.NOT_HIT;
        } else if (orderType == IOstiumTradingStorage.LimitOrder.SL) {
            return t.sl > 0 && (t.buy ? triggerPrice <= t.sl : triggerPrice >= t.sl)
                ? IOstiumTradingCallbacks.CancelReason.NONE
                : IOstiumTradingCallbacks.CancelReason.NOT_HIT;
        }
        return IOstiumTradingCallbacks.CancelReason.NOT_HIT;
    }

    function getHandleRemoveCollateralCancelReason(
        IOstiumPriceUpKeep.PriceUpKeepAnswer calldata a,
        IOstiumTradingStorage.Trade memory trade,
        IOstiumPairInfos pairInfos,
        IOstiumPairsStorage pairsStorage,
        uint32 initialLeverage
    ) external returns (IOstiumTradingCallbacks.CancelReason) {
<<<<<<< HEAD
        //@note
        //Intention
        //  1) tradeValue < liqMarginValue -> UNDER_LIQUIDATION
        //  2) leverage > maxLeverage      -> MAX_LEVERAGE
        //  3) profitP == maxPnlP          -> GAIN_LOSS
        //  4) NONE of the above           -> NONE

        TradingCallbacksLib.PriceImpactResult memory result =
            getDynamicTradePriceImpact(a.price, a.ask, a.bid, false, trade, pairInfos, trade.collateral);
=======
        TradingCallbacksLib.PriceImpactResult memory result = getDynamicTradePriceImpact(
            a.price, a.ask, a.bid, false, trade, pairInfos, trade.collateral
        );
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3

        (int256 profitP, int256 maxPnlP) = currentPercentProfit(
            trade.openPrice.toInt256(),
            result.priceAfterImpact.toInt256(),
            trade.buy,
            int32(trade.leverage),
            int32(initialLeverage)
        );

        uint32 maxLeverage = getEffectiveMaxLeverage(trade.pairIndex, trade.isDayTrade, pairsStorage);

        if (maxLeverage == 0) {
            return IOstiumTradingCallbacks.CancelReason.MAX_LEVERAGE;
        }

        (uint256 tradeValue, uint256 liqMarginValue,,) = pairInfos.getTradeValue(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy,
            trade.collateral,
            trade.leverage,
            profitP,
            maxLeverage
        );

        bool isLiquidated = tradeValue < liqMarginValue;
        uint256 usdcSentToTrader = isLiquidated ? 0 : tradeValue;

        //1 {
        if (usdcSentToTrader == 0) {
            return IOstiumTradingCallbacks.CancelReason.UNDER_LIQUIDATION;
        }
        //} 1

<<<<<<< HEAD
        //2 {
        if (trade.leverage > maxLeverage) {
=======
        // Check leverage against appropriate max based on trade type (not market state)
        if (!withinMaxLeverage(trade.pairIndex, trade.leverage, trade.isDayTrade, pairsStorage)) {
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
            return IOstiumTradingCallbacks.CancelReason.MAX_LEVERAGE;
        }
        //} 2

        //3 {
        if (profitP == maxPnlP) {
            return IOstiumTradingCallbacks.CancelReason.GAIN_LOSS;
        }
        //} 3

        return IOstiumTradingCallbacks.CancelReason.NONE;
    }

    function _decayVolumeWithPade(uint256 volume, uint32 decayInterval, uint128 decayRate)
        internal
        pure
        returns (uint256 decayedVolume)
    {
        //@note
        //Intention
        //  V = V0 * e^(-decayRate * time)
        //    ~ V0 * (1 - decayRate * time / 2) / (1 + decayRate * time / 2)
        //
        //  Use Pade Approximation for decay function
        //  -----------------------------
        //  | e^-x ~ (1 - x/2)/(1 + x/2)|
        //  -----------------------------

        if (decayInterval == 0) {
            return volume;
        }

        uint256 decayFactor_half = (uint256(decayRate) * decayInterval) / 2;
        uint256 numerator = PRECISION_18 > decayFactor_half ? PRECISION_18 - decayFactor_half : 0;
        uint256 denominator = PRECISION_18 + decayFactor_half;
        uint256 decayMultiplier = (numerator * PRECISION_18) / denominator;

        return uint128((uint256(volume) * decayMultiplier) / PRECISION_18);
    }

    function _priceImpactFunction(
        uint256 netVolThreshold,
        uint256 priceImpactK,
        uint256 tradeSize,
        uint256 initialVol,
        uint256 midPrice,
        uint256 askPrice,
        uint256 bidPrice
    ) internal pure returns (uint256 priceImpactP) {
<<<<<<< HEAD
        //@note
        //Intention
        //  PriceImpactP = (spreadComponent + dynamicComponent) / tradeSize * 100
        //      1) If isOpen == buy -> nextImbalance += tradeSize
        //         Else             -> nextImbalance -= tradeSize
        //      2) If trade reduce imbalance (|nextImbalance| < |initialImbalance|) -> return 0
        //      3) If |nextImbalance| < netVolThreshold                             -> return 0
        //      4) Calculate linear `spreadComponent`: spreadComponent = (spread * thresholdTradeSize) / SPREAD_DIVISOR
        //          Where:
        //            `thresholdTradeSize`: amount that push the system above `netVolThreshold`
        //            `SPREAD_DIVISOR`: 2^18
        //      5) Calculate quadratic `dynamicComponent`: dynamicComponent = <Excess portion> * <Cost per excess unit>
        //          Where:
        //              <Excess portion> = thresholdTradeSize ^2 / excessOverThreshold
        //              <Cost per excess unit> = priceImpactK * excessOverThreshold ^ 2
        //          Ex:
        //              excessOverThreshold = 1000
        //              thresholdTradeSize = 500       (A push 500 imbalance, protocol already has 500 imbalance)
        //              => <Excess portion> = 500 ^2 / 1000 = 250 (25% = 50% ^ 2)
        //              => <Cost per excess unit> = priceImpactK * 1000 ^ 2
        //          dynamicComponent = 250 * priceImpactK * 1000 ^ 2

        //1 {
        int256 nextImbalance = initialImbalance + (isOpen == buy ? int256(tradeSize) : -int256(tradeSize));
        uint256 absNextImbalance = nextImbalance >= 0 ? uint256(nextImbalance) : uint256(-nextImbalance);
        uint256 absInitialImbalance = initialImbalance >= 0 ? uint256(initialImbalance) : uint256(-initialImbalance);

        //2 {
        if (absNextImbalance < absInitialImbalance && (initialImbalance * nextImbalance >= 0)) {
            return 0;
        }
        //} 2

        //3 {
        if (absNextImbalance <= netVolThreshold) {
            return 0;
        }
        //}

        //4 {
        uint256 spread = ((askPrice - bidPrice) * PRECISION_18) / midPrice;
        uint256 excessOverThreshold = absNextImbalance - netVolThreshold;
        uint256 thresholdTradeSize = tradeSize < excessOverThreshold ? tradeSize : excessOverThreshold;
        uint256 spreadComponent = (spread * thresholdTradeSize) / SPREAD_DIVISOR;
        //} 4

        //5 {
        uint256 dynamicComponent = 0;
        if (excessOverThreshold > 0 && thresholdTradeSize > 0) {
            uint256 thresholdRatio = (thresholdTradeSize * PRECISION_18) / excessOverThreshold;
            uint256 excessSquared = (excessOverThreshold * excessOverThreshold) / PRECISION_18;
            dynamicComponent =
                (((thresholdTradeSize * thresholdRatio) / PRECISION_18)
                        * ((priceImpactK * excessSquared) / PRECISION_27)) / PRECISION_18;
=======
        uint256 spreadComponent = (askPrice - bidPrice) * PRECISION_18 * 100 / (midPrice * 2);
        uint256 dynamicComponent = 0;

        uint256 finalVol = tradeSize + initialVol;
        if (finalVol > netVolThreshold) {
            uint256 excessVol = finalVol - netVolThreshold;
            dynamicComponent = initialVol < netVolThreshold
                ? priceImpactK * excessVol * excessVol * 100 / (2 * tradeSize) / PRECISION_27
                : priceImpactK * (initialVol - netVolThreshold + tradeSize / 2) * 100 / PRECISION_27;
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
        }
        //} 5

<<<<<<< HEAD
        uint256 priceImpactUSD = spreadComponent + dynamicComponent;
        priceImpactP = ((priceImpactUSD * PRECISION_18) / tradeSize) * 100;

=======
        priceImpactP = spreadComponent + dynamicComponent;
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
        return priceImpactP;
    }

    function getDynamicTradePriceImpact(
        int192 price,
        int192 ask,
        int192 bid,
        bool isOpen,
        IOstiumTradingStorage.Trade memory trade,
        IOstiumPairInfos pairInfos,
        uint256 collateralValue
    ) public returns (PriceImpactResult memory) {
        //@note
        //Intention
        //  1) If `priceImpactK == 0` -> Use static price impact
        //  2) Decay buy and sell volumes using Pade approximation over `dt`
        //  3) Calculate dynamic price impact `priceImpactP`
        //  4) If `priceImpactP > 0`:
        //      4.1) If `isOpen == trade.buy` -> Push price up (buyer pay more to enter)
        //      4.2) Else                     -> Push price lower (floored at 0)
        //Audit
        //  4.2) Don't revert but floor at 0.
        //      -> Is it volatile with sandwich attack?

        uint256 priceImpactK = pairInfos.getPairPriceImpactK(trade.pairIndex);

        uint256 priceImpactP;
        uint256 priceAfterImpact;
        //1 {
        if (priceImpactK == 0) {
            (priceImpactP, priceAfterImpact) = _getTradePriceImpact(price, ask, bid, isOpen, trade.buy);
            return PriceImpactResult({priceImpactP: priceImpactP, priceAfterImpact: priceAfterImpact, isDynamic: false});
        }
        //} 1

        //3 {
        (uint256 netVolThreshold, uint128 decayRate,) = pairInfos.pairDynamicSpreadParams(trade.pairIndex);

        (uint256 buyVolume, uint256 sellVolume, uint32 lastUpdateTimestamp) =
            pairInfos.pairDynamicSpreadState(trade.pairIndex);

        uint32 dt = block.timestamp > lastUpdateTimestamp ? uint32(block.timestamp) - lastUpdateTimestamp : 0;
        uint128 effectiveDecayRate = _getEffectiveDecayRate(buyVolume, sellVolume, decayRate, netVolThreshold);

        uint256 initialVolume = (trade.buy == isOpen) ? buyVolume : sellVolume;
        initialVolume = _decayVolumeWithPade(initialVolume, dt, effectiveDecayRate);

        uint256 tradeNotional = collateralValue * trade.leverage * PRECISION_10;

        priceAfterImpact = uint192(price);

        priceImpactP = _priceImpactFunction(
            netVolThreshold, priceImpactK, tradeNotional, initialVolume, uint192(price), uint192(ask), uint192(bid)
        );
        //} 3

        //4 {
        if (priceImpactP > 0) {
            if (isOpen == trade.buy) {
                priceAfterImpact = (priceAfterImpact * (PRECISION_18 + (priceImpactP / 100))) / PRECISION_18;
            } else {
<<<<<<< HEAD
                priceAfterImpact = priceImpactP < 100e18
                    ? (priceAfterImpact * (PRECISION_18 - (priceImpactP / 100))) / PRECISION_18
                    : 0;
=======
                if (priceImpactP < 100e18) {
                    priceAfterImpact = priceAfterImpact * (PRECISION_18 - (priceImpactP / 100)) / PRECISION_18;
                } else {
                    priceAfterImpact = 0;
                    priceImpactP = 100e18;
                }
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
            }
        }
        //} 4

        return PriceImpactResult({priceImpactP: priceImpactP, priceAfterImpact: priceAfterImpact, isDynamic: true});
    }

    function calculateDecayedVolumesWithPostFeeCollateral(
        uint16 pairIndex,
        bool isOpen,
        bool isBuy,
        uint256 postFeeCollateral,
        uint32 leverage,
        IOstiumPairInfos pairInfos
    ) external returns (uint256 decayedBuyVolume, uint256 decayedSellVolume) {
<<<<<<< HEAD
        //@note
        //Intention
        //  1) Calculate decayed buy and sell volumes
        //  2) tradeNotional = postFeeCollateral * leverage
        //      If isOpen == isBuy  -> decayedBuyVolume += tradeNotional
        //      Else                -> decayedSellVolume += tradeNotional
        //Follow-up
        //  2) tradeNotional is scaled PRECISION_10?
        //  2) increase sellVlume instead of decreasing buyVolume if isOpen != isBuy?

        (, uint128 decayRate,) = pairInfos.pairDynamicSpreadParams(pairIndex);
=======
        (uint256 netVolThreshold, uint128 decayRate,) = pairInfos.pairDynamicSpreadParams(pairIndex);
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3

        (uint256 buyVolume, uint256 sellVolume, uint32 lastUpdateTimestamp) =
            pairInfos.pairDynamicSpreadState(pairIndex);

        //1 {
        uint32 dt = block.timestamp > lastUpdateTimestamp ? uint32(block.timestamp) - lastUpdateTimestamp : 0;

<<<<<<< HEAD
        decayedBuyVolume = _decayVolumeWithPade(buyVolume, dt, decayRate);
        decayedSellVolume = _decayVolumeWithPade(sellVolume, dt, decayRate);
        //} 1
=======
        uint128 effectiveDecayRate = _getEffectiveDecayRate(buyVolume, sellVolume, decayRate, netVolThreshold);
        decayedBuyVolume = _decayVolumeWithPade(buyVolume, dt, effectiveDecayRate);
        decayedSellVolume = _decayVolumeWithPade(sellVolume, dt, effectiveDecayRate);
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3

        //2 {
        uint256 tradeNotional = postFeeCollateral * leverage * PRECISION_10;

        if (isOpen == isBuy) {
            decayedBuyVolume += tradeNotional;
        } else {
            decayedSellVolume += tradeNotional;
        }
        //} 2
    }

    function _getEffectiveDecayRate(uint256 buyVolume, uint256 sellVolume, uint128 decayRate, uint256 netVolThreshold)
        internal
        pure
        returns (uint128)
    {
        if (netVolThreshold == 0) {
            return decayRate * PRECISION_18 / MAX_DECAY_FACTOR;
        }
        uint256 absNetVol = buyVolume > sellVolume ? buyVolume - sellVolume : sellVolume - buyVolume;

        uint256 factor = PRECISION_18;
        if (absNetVol > netVolThreshold) {
            uint256 ratio = absNetVol * PRECISION_18 / netVolThreshold;
            factor = ratio > MAX_DECAY_FACTOR ? MAX_DECAY_FACTOR : ratio;
        }

        return uint128(decayRate * PRECISION_18 / factor);
    }

    // @dev uses the same calculations as in TadingLib.getOpenTradeRevert()
    function calculatePostFeeCollateral(
        uint256 collateral,
        uint32 leverage,
        uint16 pairIndex,
        uint32 takerFeeP,
        IOstiumPairsStorage pairsStorage,
        IOstiumTradingStorage.BuilderFee memory bf
    ) public view returns (uint256) {
        uint256 preFeeNotional = collateral * leverage / 100;

        uint256 oracleFee = pairsStorage.pairOracleFee(pairIndex);

        uint256 builderFee = 0;
        if (bf.builder != address(0) && bf.builderFee > 0) {
            builderFee = bf.builderFee * preFeeNotional / PRECISION_6 / 100;
        }
        // We only use takerFeeP no matter maker or taker
        uint256 openingFee = preFeeNotional * takerFeeP / PRECISION_6 / 100;

        uint256 totalFees = openingFee + oracleFee + builderFee;

        // @dev In very unlikely case of totalFees >= collateral this call will revert with underflow
        // the check that ensures this does not happen exists on openTrade() function
        // if one of the fee values change drastically before the upkeep, it may revert for very small values of collateral
        return collateral - totalFees;
    }

    function executeRegisterTrade(
        uint256 tradeId,
        IOstiumTradingStorage.Trade memory trade,
        uint256 latestPrice,
        IOstiumTradingStorage.BuilderFee memory bf,
        uint8 maxSl_P,
        IOstiumTradingStorage storageT,
        IOstiumPairInfos pairInfos,
        IOstiumPairsStorage pairsStorage,
        IOstiumVault vault
    )
        external
        returns (
            IOstiumTradingStorage.Trade memory,
            uint256 reward,
            uint256 vaultReward,
            uint256 oracleFee,
            uint256 builderFee
        )
    {
        uint256 tradeNotional = Math.mulDiv(trade.collateral, trade.leverage, 100, Math.Rounding.Ceil);

        // 2.1 Charge opening fee
        {
            (reward, vaultReward) =
                storageT.handleOpeningFees(trade.pairIndex, latestPrice, tradeNotional, trade.leverage, trade.buy);

            trade.collateral -= reward;

            if (vaultReward > 0) {
                storageT.transferUsdc(address(storageT), address(this), vaultReward);
                vault.distributeReward(vaultReward);
                trade.collateral -= vaultReward;
            }
        }

        oracleFee = pairsStorage.pairOracleFee(trade.pairIndex);
        storageT.handleOracleFee(oracleFee);
        trade.collateral -= oracleFee;

        if (bf.builder != address(0) && bf.builderFee > 0) {
            builderFee = bf.builderFee * tradeNotional / PRECISION_6 / 100;
            storageT.transferUsdc(address(storageT), bf.builder, builderFee);
            trade.collateral -= builderFee;
        }

        // 4. Set trade final details
        trade.index = storageT.firstEmptyTradeIndex(trade.trader, trade.pairIndex);

        trade.tp = correctTp(trade.openPrice, trade.tp, trade.leverage, trade.leverage, trade.buy);
        trade.sl = correctSl(trade.openPrice, trade.sl, trade.leverage, trade.leverage, trade.buy, maxSl_P);

        // 5. Call other contracts
        pairInfos.storeTradeInitialAccFees(tradeId, trade.trader, trade.pairIndex, trade.index, trade.buy);
        pairsStorage.updateGroupCollateral(trade.pairIndex, trade.collateral, trade.buy, true);

        // 6. Store final trade in storage contract
        uint32 currTimestamp = block.timestamp.toUint32();
        storageT.storeTrade(
            trade,
            IOstiumTradingStorage.TradeInfo(
                tradeId,
                trade.collateral * uint256(1e12) * trade.leverage / 100 * PRECISION_18 / trade.openPrice,
                trade.leverage,
                currTimestamp,
                currTimestamp,
                currTimestamp,
                false
            )
        );

        return (trade, reward, vaultReward, oracleFee, builderFee);
    }

    function executeUnregisterTrade(
        IOstiumTradingStorage.Trade memory trade,
        uint256 usdcSentToTrader,
        uint256 liquidationFee,
        uint256 collateralToClose,
        IOstiumTradingStorage storageT,
        IOstiumPairsStorage pairsStorage,
        IOstiumVault vault
    ) external {
        pairsStorage.updateGroupCollateral(trade.pairIndex, collateralToClose, trade.buy, false);

        // 3.1 Unregister trade
        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index, collateralToClose);

        // 3 USDC vault reward
        if (liquidationFee > 0) {
            storageT.transferUsdc(address(storageT), address(this), liquidationFee);
            vault.receiveAssets(liquidationFee, trade.trader);
        }

        // 4 Take USDC from vault if winning trade
        // or send USDC to vault if losing trade
        uint256 usdcLeftInStorage = collateralToClose - liquidationFee;

        if (usdcSentToTrader > usdcLeftInStorage) {
            vault.sendAssets(usdcSentToTrader - usdcLeftInStorage, trade.trader);
            storageT.transferUsdc(address(storageT), trade.trader, usdcLeftInStorage);
        } else {
            uint256 usdcSentToVault = usdcLeftInStorage - usdcSentToTrader;
            storageT.transferUsdc(address(storageT), address(this), usdcSentToVault);
            vault.receiveAssets(usdcSentToVault, trade.trader);
            if (usdcSentToTrader > 0) storageT.transferUsdc(address(storageT), trade.trader, usdcSentToTrader);
        }
    }
}

