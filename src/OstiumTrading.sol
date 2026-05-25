// SPDX-License-Identifier: MIT
import "./abstract/Delegatable.sol";
import "./lib/ChainUtils.sol";
import "./lib/TradingLib.sol";
import "./interfaces/IOstiumTrading.sol";
import "./interfaces/IOstiumRegistry.sol";
import "./interfaces/IOstiumPairInfos.sol";
import "./interfaces/IOstiumTradingCallbacks.sol";
import "./interfaces/IOstiumTradingStorage.sol";
import "./interfaces/IOstiumPriceRouter.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

pragma solidity ^0.8.24;

contract OstiumTrading is IOstiumTrading, Delegatable, Initializable {
    using SafeCast for uint256;
    using Math for uint256;

    // Contracts (constant)
    IOstiumRegistry public registry;

    // Params (constant)
    uint64 constant PRECISION_18 = 1e18;
    uint32 constant PRECISION_6 = 1e6;
    uint16 constant MAX_GAIN_P = 900;
    uint16 constant PERCENT_BASE = 100e2; // 100% in precision 2 and also the MAX_SLIPPAGE_P
    uint32 constant MAX_BUILDER_FEE_PERCENT = 500000; // 0.5% // PRECISION_6

    // Params (adjustable)
    uint256 public maxAllowedCollateral; // PRECISION_6
    uint16 public marketOrdersTimeout; // block (eg. 30)
    uint16 public triggerTimeout; // block (eg. 30)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IOstiumRegistry _registry,
        uint256 _maxAllowedCollateral,
        uint16 _marketOrdersTimeout,
        uint16 _triggerTimeout
    ) external initializer {
        if (address(_registry) == address(0)) {
            revert WrongParams();
        }

        registry = _registry;
        _setTriggerTimeout(_triggerTimeout);
        _setMaxAllowedCollateral(_maxAllowedCollateral);
        _setMarketOrdersTimeout(_marketOrdersTimeout);
    }

    // Modifiers
    modifier onlyGov() {
        isGov();
        _;
    }

    modifier onlyManager() {
        isManager();
        _;
    }

    modifier notDone() {
        isNotDone();
        _;
    }

    modifier onlyTradesUpKeep() {
        _onlyTradesUpKeep();
        _;
    }

    modifier notPaused() {
        isNotPaused();
        _;
    }

    modifier pairIndexListed(uint16 pairIndex) {
        isPairIndexListed(pairIndex);
        _;
    }

    function isPairIndexListed(uint16 pairIndex) private view {
        if (!IOstiumPairsStorage(registry.getContractAddress("pairsStorage")).isPairIndexListed(pairIndex)) {
            revert PairNotListed(pairIndex);
        }
    }

    function isNotPaused() private view {
        if (isPaused) revert IsPaused();
    }

    function isGov() private view {
        if (msg.sender != registry.gov()) {
            revert NotGov(msg.sender);
        }
    }

    function isManager() private view {
        if (msg.sender != registry.manager()) {
            revert NotManager(msg.sender);
        }
    }

    function isNotDone() private view {
        if (isDone) {
            revert IsDone();
        }
    }

    function _onlyTradesUpKeep() private view {
        if (msg.sender != address(registry.getContractAddress(bytes32("tradesUpKeep")))) {
            revert NotTradesUpKeep(msg.sender);
        }
    }

    function setMaxAllowedCollateral(uint256 value) external onlyGov {
        _setMaxAllowedCollateral(value);
    }

    function _setMaxAllowedCollateral(uint256 value) private {
        if (value == 0) {
            revert WrongParams();
        }
        maxAllowedCollateral = value;

        emit MaxAllowedCollateralUpdated(value);
    }

    function setMarketOrdersTimeout(uint256 value) external onlyGov {
        _setMarketOrdersTimeout(value);
    }

    function _setMarketOrdersTimeout(uint256 value) private {
        if (value == 0 || value > type(uint16).max) {
            revert WrongParams();
        }
        marketOrdersTimeout = value.toUint16();

        emit MarketOrdersTimeoutUpdated(marketOrdersTimeout);
    }

    function setTriggerTimeout(uint256 value) external onlyGov {
        _setTriggerTimeout(value);
    }

    function _setTriggerTimeout(uint256 value) private {
        if (value == 0 || value > type(uint16).max) {
            revert WrongParams();
        }
        triggerTimeout = value.toUint16();
        emit TriggerTimeoutUpdated(triggerTimeout);
    }

    function pause() external onlyManager {
        isPaused = !isPaused;

        emit Paused(isPaused);
    }

    function done() external onlyGov {
        isDone = !isDone;

        emit Done(isDone);
    }

    //struct Trade {                           | enum OpenOrderType {
    //    uint256 collateral; // PRECISION_6   |    MARKET, //immediately
    //    uint192 openPrice; // PRECISION_18   |    LIMIT, //pending until better price
    //    uint192 tp; // PRECISION_18          |    STOP //pending until worse price
    //    uint192 sl; // PRECISION_18          | }
    //    address trader;                      |
    //    uint32 leverage; // PRECISION_2      | struct BuilderFee {
    //    uint16 pairIndex;                    |    address builder;
    //    uint8 index;                         |    uint32 builderFee; // PRECISION_6
    //    bool buy;                            | }
    //}
    function openTrade(
        IOstiumTradingStorage.Trade calldata t,
        IOstiumTradingStorage.BuilderFee calldata bf,
        IOstiumTradingStorage.OpenOrderType orderType,
        uint256 slippageP // for market orders only
    ) external notDone notPaused pairIndexListed(t.pairIndex) {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      notPaused
        //      pairIndexListed
        //      0% < slippage < 100%
        //      t.openPrice != 0
        //      bf.builder != address(0) => bf.builderFee <= 0.5%
        //  2) Guard: validate trade parameters
        //  3) Pull USDC collateral from trader to tradingStorage
        //  4)
        //     4.1) If orderType == LIMIT/STOP  -> store open limit order
        //     4.2) Else orderType == MARKET    -> request live price and store pending market order
        //Audit
        //  4.1, 4.2) `t.trader` is overriden by _msgSender()
        //  4.2) `t.index` is ignored
        //Folow-up
        //  t.openPrice is passed by user

        //-1 {
        address sender = _msgSender();
        if (slippageP == 0 || slippageP >= PERCENT_BASE || t.openPrice == 0) {
            revert WrongParams();
        }

        if (bf.builder != address(0) && bf.builderFee > MAX_BUILDER_FEE_PERCENT) {
            revert WrongParams();
        }
        //} 1

        IOstiumPairsStorage pairsStored = IOstiumPairsStorage(registry.getContractAddress("pairsStorage"));
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));
        IOstiumPairInfos pairInfos = IOstiumPairInfos(registry.getContractAddress("pairInfos"));

        //2 {
        (uint32 makerFeeP, uint32 takerFeeP,,,,) = pairInfos.pairOpeningFees(t.pairIndex);
        TradingLib.getOpenTradeRevert(storageT, pairsStored, sender, t, maxAllowedCollateral, takerFeeP, makerFeeP, bf);
        //} 2

        //3
        storageT.transferUsdc(sender, address(storageT), t.collateral);

        //4 {
        //4.1 {
        if (orderType != IOstiumTradingStorage.OpenOrderType.MARKET) {
            uint8 index = storageT.firstEmptyOpenLimitIndex(sender, t.pairIndex);

            uint32 currTimestamp = block.timestamp.toUint32();
            storageT.storeOpenLimitOrder(
                IOstiumTradingStorage.OpenLimitOrder(
                    t.collateral,
                    t.openPrice,
                    t.tp,
                    t.sl,
                    sender,
                    t.leverage,
                    currTimestamp,
                    currTimestamp,
                    t.pairIndex,
                    orderType,
                    index,
                    t.buy
                ),
                bf
            );

            emit OpenLimitPlaced(sender, t.pairIndex, index);
        }
        //} 4.1
        //4.2{
        else {
            uint256 orderId = IOstiumPriceRouter(registry.getContractAddress("priceRouter"))
                .getPrice(t.pairIndex, IOstiumPriceUpKeep.OrderType.MARKET_OPEN, block.timestamp);

            storageT.storePendingMarketOrder(
                IOstiumTradingStorage.PendingMarketOrderV2(
                    0,
                    t.openPrice,
                    slippageP.toUint32(),
                    IOstiumTradingStorage.Trade(t.collateral, 0, t.tp, t.sl, sender, t.leverage, t.pairIndex, 0, t.buy),
                    0
                ),
                orderId,
                true,
                bf
            );

            emit MarketOpenOrderInitiated(orderId, sender, t.pairIndex);
        }
        //} 4.2
        //} 4
    }

    function closeTradeMarket(
        uint16 pairIndex,
        uint8 index,
        uint16 closePercentage,
        uint192 marketPrice,
        uint32 slippageP
    ) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      0% < closePercentage <= 100%
        //          If closePercentage == 0 -> default to 100% (full close)
        //      0% < slippageP < 100%
        //  2) Validate close order via getCloseTradeRevert
        //  3) Request oracle price
        //  4) Pull oracleFee from sender
        //  5) Store pending market close order as MARKET_CLOSE

        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));
        IOstiumPairsStorage pairsStorage = IOstiumPairsStorage(registry.getContractAddress("pairsStorage"));

        //-1 {
        address sender = _msgSender();

        if (closePercentage > PERCENT_BASE) {
            revert WrongParams();
        }

        if (marketPrice == 0 || slippageP == 0 || slippageP > PERCENT_BASE) {
            revert WrongParams();
        }

        if (closePercentage == 0) {
            closePercentage = PERCENT_BASE;
        }
        //} 1

        IOstiumTradingStorage.Trade memory t = storageT.getOpenTrade(sender, pairIndex, index);
        IOstiumTradingStorage.TradeInfo memory i = storageT.getOpenTradeInfo(sender, pairIndex, index);

        //2
        TradingLib.getCloseTradeRevert(storageT, pairsStorage, sender, t, i, triggerTimeout, closePercentage);

        //3
        uint256 orderId = IOstiumPriceRouter(registry.getContractAddress("priceRouter"))
            .getPrice(pairIndex, IOstiumPriceUpKeep.OrderType.MARKET_CLOSE, block.timestamp);

        //4 {
        // Always charge oracle fee for both partial and full closes to prevent griefing
        uint256 oracleFee = pairsStorage.pairOracleFee(pairIndex);
        storageT.transferUsdc(sender, address(storageT), oracleFee);
        storageT.handleOracleFee(oracleFee);
        emit OracleFeeCharged(orderId, sender, pairIndex, oracleFee);
        //} 4

        //5
        storageT.storePendingMarketOrder(
            IOstiumTradingStorage.PendingMarketOrderV2(
                0,
                marketPrice,
                slippageP,
                IOstiumTradingStorage.Trade(0, 0, 0, 0, sender, 0, pairIndex, index, t.buy),
                closePercentage
            ),
            orderId,
            false,
            IOstiumTradingStorage.BuilderFee(address(0), 0)
        );

        emit MarketCloseOrderInitiatedV2(orderId, i.tradeId, sender, pairIndex, closePercentage);
    }

    function updateOpenLimitOrder(uint16 pairIndex, uint8 index, uint192 price, uint192 tp, uint192 sl)
        external
        notDone
    {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      revert if price == 0
        //      revert if no open limit order at (sender, pairIndex, index)
        //  2) Update o.targetPrice, o.tp, o.sl in memory
        //  3) Validate via getUpdateOpenLimitOrderRevert (TP/SL direction valid, no pending OPEN trigger)
        //  4) Persist updated limit order to storage
        if (price == 0) {
            revert WrongParams();
        }

        address sender = _msgSender();
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));

        if (!storageT.hasOpenLimitOrder(sender, pairIndex, index)) {
            revert NoLimitFound(sender, pairIndex, index);
        }

        IOstiumTradingStorage.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        o.targetPrice = price;
        o.tp = tp;
        o.sl = sl;

        TradingLib.getUpdateOpenLimitOrderRevert(storageT, sender, o, pairIndex, index, triggerTimeout);

        storageT.updateOpenLimitOrder(o);

        emit OpenLimitUpdated(sender, pairIndex, index, price, tp, sl);
    }

    function cancelOpenLimitOrder(uint16 pairIndex, uint8 index) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      (via getCancelOpenLimitOrderRevert) order exists, no pending OPEN trigger
        //  2) Unregister open limit order
        //  3) If o.collateral > oracleFee -> refund (collateral - oracleFee) to sender
        //     Else                         -> cap oracleFee to o.collateral (no refund)
        //  4) Process oracle fee
        address sender = _msgSender();
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));

        TradingLib.getCancelOpenLimitOrderRevert(storageT, sender, pairIndex, index, triggerTimeout);

        IOstiumTradingStorage.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        storageT.unregisterOpenLimitOrder(sender, pairIndex, index);

        uint256 oracleFee = IOstiumPairsStorage(registry.getContractAddress("pairsStorage")).pairOracleFee(pairIndex);
        if (o.collateral > oracleFee) {
            storageT.transferUsdc(address(storageT), sender, o.collateral - oracleFee);
        } else {
            oracleFee = o.collateral;
        }
        storageT.handleOracleFee(oracleFee);

        emit OracleFeeChargedLimitCancelled(sender, pairIndex, oracleFee);
        emit OpenLimitCanceled(sender, pairIndex, index);
    }

    function updateTp(uint16 pairIndex, uint8 index, uint192 newTp) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      noPendingTrigger for TP within triggerTimeout
        //  2) Existing trade (leverage != 0)
        //  3) Ensure don't exceed tp max (900%)
        //  4) updateTp
        //Follow-up
        //  3) maxTpDist < t.openPrice ? t.openPrice - maxTpDist : 0? When 0?

        address sender = _msgSender();
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));

        //-1 {
        if (!TradingLib.checkNoPendingTrigger(
                storageT, sender, pairIndex, index, IOstiumTradingStorage.LimitOrder.TP, triggerTimeout
            )) {
            revert TriggerPending(sender, pairIndex, index);
        }
        //} 1

        IOstiumTradingStorage.Trade memory t = storageT.getOpenTrade(sender, pairIndex, index);

        //2 {
        if (t.leverage == 0) {
            revert NoTradeFound(sender, pairIndex, index);
        }
        //} 2

        (,, uint32 initialLeverage,,,,) = storageT.openTradesInfo(sender, pairIndex, index);

        //3 {
        uint256 maxTpDist = (t.openPrice * MAX_GAIN_P) / (initialLeverage > t.leverage ? initialLeverage : t.leverage);

        if (
            newTp != 0
                && (t.buy
                        ? newTp > t.openPrice + maxTpDist
                        : newTp < (maxTpDist < t.openPrice ? t.openPrice - maxTpDist : 0))
        ) revert WrongTP();
        //} 3

        //4
        storageT.updateTp(sender, pairIndex, index, newTp);

        emit TpUpdated(storageT.getOpenTradeInfo(sender, pairIndex, index).tradeId, sender, pairIndex, index, newTp);
    }

    function updateSl(uint16 pairIndex, uint8 index, uint192 newSl) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      noPendingTrigger for SL within triggerTimeout
        //  2) Existing trade (leverage != 0)
        //  3) Ensure new SL is within max SL distance
        //  4) Persist new SL

        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));

        address sender = _msgSender();

        //-1 {
        if (!TradingLib.checkNoPendingTrigger(
                storageT, sender, pairIndex, index, IOstiumTradingStorage.LimitOrder.SL, triggerTimeout
            )) {
            revert TriggerPending(sender, pairIndex, index);
        }
        //} 1

        IOstiumTradingStorage.Trade memory t = storageT.getOpenTrade(sender, pairIndex, index);

        //2 {
        if (t.leverage == 0) {
            revert NoTradeFound(sender, pairIndex, index);
        }
        //} 2

        //3 {
        uint8 maxSL_P = IOstiumTradingCallbacks(registry.getContractAddress("callbacks")).maxSl_P();
        uint256 maxSlDist = (t.openPrice * maxSL_P) / t.leverage;

        if (newSl != 0 && (t.buy ? newSl < t.openPrice - maxSlDist : newSl > t.openPrice + maxSlDist)) {
            revert WrongSL();
        }
        //} 3

        //4
        storageT.updateSl(sender, pairIndex, index, newSl);

        emit SlUpdated(storageT.getOpenTradeInfo(sender, pairIndex, index).tradeId, sender, pairIndex, index, newSl);
    }

    function topUpCollateral(uint16 pairIndex, uint8 index, uint256 topUpAmount) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      onlyExistingTrade (leverage != 0)
        //      topUpAmount > 0
        //      noPendingTrigger for TP, SL, LIQ, CLOSE_DAY_TRADE, REMOVE_COLLATERAL  within triggerTimeout
        //  2) Compute newLeverage from (collateral + topUpAmount)
        //  3) validate top up
        //      don't exceed max allowed collateral
        //      newCollateral < maxAllowedCollateral
        //      pairMinLeverage <= newLeverage < t.leverage
        //  4) Update states
        //Follow-up
        //  2) tradeSize is rounded up?

        address sender = _msgSender();
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));
        IOstiumPairsStorage pairsStorage = IOstiumPairsStorage(registry.getContractAddress("pairsStorage"));

        IOstiumTradingStorage.Trade memory t = storageT.getOpenTrade(sender, pairIndex, index);

        //-1 {
        if (t.leverage == 0) {
            revert NoTradeFound(sender, pairIndex, index);
        }
        if (topUpAmount == 0) {
            revert WrongParams();
        }
        if (!TradingLib.checkNoPendingTriggers(storageT, t.trader, t.pairIndex, t.index, triggerTimeout)) {
            revert TriggerPending(t.trader, t.pairIndex, t.index);
        }
        //} 1

        //2 {
        uint256 tradeSize = t.collateral.mulDiv(t.leverage, 100, Math.Rounding.Ceil);
        uint256 newCollateral = t.collateral + topUpAmount;
        uint32 newLeverage = ((tradeSize * PRECISION_6) / newCollateral / 1e4).toUint32();

        if ((tradeSize * PRECISION_6) % (newCollateral * 1e4) != 0) {
            newLeverage += 1;
            newCollateral = (tradeSize * 1e2) / newLeverage;

            if (newCollateral > t.collateral) {
                topUpAmount = newCollateral - t.collateral;
            } else {
                revert WrongParams();
            }
        }
        //} 2

        //3 {
        if (pairsStorage.groupCollateral(pairIndex, t.buy) + topUpAmount > pairsStorage.groupMaxCollateral(pairIndex)) {
            revert ExposureLimits();
        }

        if (newCollateral > maxAllowedCollateral) {
            revert AboveMaxAllowedCollateral();
        }

        if (newLeverage >= t.leverage || newLeverage < pairsStorage.pairMinLeverage(t.pairIndex)) {
            revert WrongLeverage(newLeverage);
        }
        //} 3

        //4 {
        t.leverage = newLeverage;
        t.collateral = newCollateral;

        storageT.transferUsdc(sender, address(storageT), topUpAmount);

        storageT.updateTrade(t);
        pairsStorage.updateGroupCollateral(t.pairIndex, topUpAmount, t.buy, true);
        //} 4

        emit TopUpCollateralExecuted(
            storageT.getOpenTradeInfo(sender, pairIndex, index).tradeId, sender, pairIndex, topUpAmount, t.leverage
        );
    }

    function removeCollateral(uint16 pairIndex, uint8 index, uint256 removeAmount) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      onlyExistingTrade (leverage != 0)
        //      0 < removeAmount <= current collateral
        //       noPendingTrigger for TP, SL, LIQ, CLOSE_DAY_TRADE, REMOVE_COLLATERAL  within triggerTimeout
        //  2) Calculate new leverage, collateral
        //  4) t.leverage < newLeverage <= pairMaxLeverage
        //  5) Request price from router
        //  6) Store pending remove collateral order and trigger
        //  7) Pull and handle oracle fee in USDC

        //1 {
        address sender = _msgSender();
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));
        IOstiumPairsStorage pairsStorage = IOstiumPairsStorage(registry.getContractAddress("pairsStorage"));

        IOstiumTradingStorage.Trade memory t = storageT.getOpenTrade(sender, pairIndex, index);

        if (t.leverage == 0) {
            revert NoTradeFound(sender, pairIndex, index);
        }
        if (removeAmount == 0 || removeAmount >= t.collateral) {
            revert WrongParams();
        }
        if (!TradingLib.checkNoPendingTriggers(storageT, t.trader, t.pairIndex, t.index, triggerTimeout)) {
            revert TriggerPending(t.trader, t.pairIndex, t.index);
        }
        //} 1

        //2 {
        uint256 tradeSize = t.collateral.mulDiv(t.leverage, 100, Math.Rounding.Ceil);
        uint256 newCollateral = t.collateral - removeAmount;
        uint32 newLeverage = ((tradeSize * PRECISION_6) / newCollateral / 1e4).toUint32();

        if ((tradeSize * PRECISION_6) % (newCollateral * 1e4) != 0) {
            newCollateral = (tradeSize * 1e2) / newLeverage;

            if (newCollateral < t.collateral) {
                removeAmount = t.collateral - newCollateral;
            } else {
                revert WrongParams();
            }
        }
        //} 2

        //3 {
        if (newLeverage <= t.leverage || newLeverage > pairsStorage.pairMaxLeverage(t.pairIndex)) {
            revert WrongLeverage(newLeverage);
        }
        //} 3

        //4 {
        uint256 orderId = IOstiumPriceRouter(registry.getContractAddress("priceRouter"))
            .getPrice(pairIndex, IOstiumPriceUpKeep.OrderType.REMOVE_COLLATERAL, block.timestamp);
        //} 4

        //5 {
        storageT.storePendingRemoveCollateral(
            IOstiumTradingStorage.PendingRemoveCollateral(removeAmount, sender, pairIndex, index), orderId
        );

        storageT.setTrigger(t.trader, pairIndex, index, IOstiumTradingStorage.LimitOrder.REMOVE_COLLATERAL);
        //} 5

        //6 {
        uint256 oracleFee = pairsStorage.pairOracleFee(pairIndex);
        storageT.transferUsdc(sender, address(storageT), oracleFee);
        storageT.handleOracleFee(oracleFee);
        //} 6

        emit RemoveCollateralInitiated(
            storageT.getOpenTradeInfo(sender, pairIndex, index).tradeId, orderId, sender, pairIndex, removeAmount
        );
    }

    function executeAutomationOrder(
        IOstiumTradingStorage.LimitOrder orderType,
        address trader,
        uint16 pairIndex,
        uint8 index,
        uint256 priceTimestamp
    ) external onlyTradesUpKeep notDone pairIndexListed(pairIndex) returns (IOstiumTrading.AutomationOrderStatus) {
        //@note
        //Intention
        //  1) Guard:
        //      onlyTradesUpKeep
        //      notDone
        //      pairIndexListed
        //  2)
        //     2.1) If orderType == OPEN:
        //              hasOpenLimitOrder()
        //              isNotPaused()
        //              valid timestamp: priceTimestamp >= order.createdAt
        //     2.2) Else (close types: TP/SL/LIQ/...):
        //              hasOpenLimitOrder(): leverage == 0
        //              valid timestamp: priceTimestamp >= tradeInfo.createdAt
        //              if SL type but sl == 0 || sl updated after priceTimestamp -> early stop
        //              if TP type but tp == 0 or tp updated after priceTimestamp -> early stop
        //  3) If have same orderType pending trigger -> early stop
        //  4) Request oracle price (LIMIT_OPEN or LIMIT_CLOSE)
        //  5) Store pending automation order; set trigger block
        //Assumption
        //  5) automation order can be expired (priceTimestamp + triggerTimeout)

        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));

        IOstiumTradingStorage.Trade memory t;

        //2 {
        //2.1 {
        if (orderType == IOstiumTradingStorage.LimitOrder.OPEN) {
            if (!storageT.hasOpenLimitOrder(trader, pairIndex, index)) {
                return IOstiumTrading.AutomationOrderStatus.NO_LIMIT;
            }
            isNotPaused();

            IOstiumTradingStorage.OpenLimitOrder memory openOrder = storageT.getOpenLimitOrder(trader, pairIndex, index);
            if (priceTimestamp < openOrder.createdAt) {
                return IOstiumTrading.AutomationOrderStatus.BACKDATED_EXECUTION;
            }
        }
        //} 2.1
        //2.2 {
        else {
            t = storageT.getOpenTrade(trader, pairIndex, index);
            IOstiumTradingStorage.TradeInfo memory tInfo = storageT.getOpenTradeInfo(trader, pairIndex, index);

            if (t.leverage == 0) {
                return IOstiumTrading.AutomationOrderStatus.NO_TRADE;
            }

            if (priceTimestamp < tInfo.createdAt) {
                return IOstiumTrading.AutomationOrderStatus.BACKDATED_EXECUTION;
            }

            if (
                orderType == IOstiumTradingStorage.LimitOrder.SL
                    && (t.sl == 0 || (t.sl != 0 && tInfo.slLastUpdated > priceTimestamp))
            ) {
                return IOstiumTrading.AutomationOrderStatus.NO_SL;
            }
            if (
                orderType == IOstiumTradingStorage.LimitOrder.TP
                    && (t.tp == 0 || (t.tp != 0 && tInfo.tpLastUpdated > priceTimestamp))
            ) {
                return IOstiumTrading.AutomationOrderStatus.NO_TP;
            }
        }
        //} 2.2
        //} 2

        //3 {
        if (!TradingLib.checkNoPendingTrigger(storageT, trader, pairIndex, index, orderType, triggerTimeout)) {
            return IOstiumTrading.AutomationOrderStatus.PENDING_TRIGGER;
        }
        //} 3

        //4 {
        uint256 orderId = IOstiumPriceRouter(registry.getContractAddress("priceRouter"))
            .getPrice(
                pairIndex,
                orderType == IOstiumTradingStorage.LimitOrder.OPEN
                    ? IOstiumPriceUpKeep.OrderType.LIMIT_OPEN
                    : IOstiumPriceUpKeep.OrderType.LIMIT_CLOSE,
                priceTimestamp
            );
        storageT.storePendingAutomationOrder(
            IOstiumTradingStorage.PendingAutomationOrder(trader, pairIndex, index, orderType), orderId
        );
        storageT.setTrigger(trader, pairIndex, index, orderType);
        //} 4

        if (orderType == IOstiumTradingStorage.LimitOrder.OPEN) {
            emit AutomationOpenOrderInitiated(orderId, trader, pairIndex, index);
        } else {
            emit AutomationCloseOrderInitiated(
                orderId, storageT.getOpenTradeInfo(trader, pairIndex, index).tradeId, trader, pairIndex, orderType
            );
        }

        return IOstiumTrading.AutomationOrderStatus.SUCCESS;
    }

    function openTradeMarketTimeout(uint256 _order) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      revert if no pending order (trader == address(0))
        //      revert if caller != order.trader
        //      revert if leverage != 0 (identifies this as a close order, not open)
        //      revert if block + marketOrdersTimeout not yet elapsed
        //  2) Unregister pending market open order
        //  3) Refund full collateral to sender

        address sender = _msgSender();
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));

        (uint256 _block, uint192 wantedPrice, uint32 slippageP, IOstiumTradingStorage.Trade memory trade,) =
            storageT.reqID_pendingMarketOrder(_order);

        if (trade.trader == address(0)) {
            revert NoTradeToTimeoutFound(_order);
        }

        if (trade.trader != sender) {
            revert NotYourOrder(_order, trade.trader);
        }

        if (trade.leverage == 0) {
            revert NotOpenMarketTimeoutOrder(_order);
        }

        if (_block != 0 && ChainUtils.getBlockNumber() < _block + marketOrdersTimeout) {
            revert WaitTimeout(_order);
        }

        storageT.unregisterPendingMarketOrder(_order, true);
        storageT.transferUsdc(address(storageT), sender, trade.collateral);

        emit MarketOpenTimeoutExecutedV2(
            _order,
            IOstiumTradingStorage.PendingMarketOrderV2({
                block: _block, wantedPrice: wantedPrice, slippageP: slippageP, trade: trade, percentage: 0
            })
        );
    }

    function closeTradeMarketTimeout(uint256 _order, bool retry) external notDone {
        //@note
        //Intention
        //  1) Guard:
        //      notDone
        //      revert if no pending order (trader == address(0))
        //      revert if caller != order.trader
        //      revert if leverage > 0 (identifies this as an open order, not close)
        //      revert if block == 0 or block + marketOrdersTimeout not yet elapsed
        //  2) Unregister pending market close order
        //  3) If retry -> delegatecall closeTradeMarket with same params; emit MarketCloseFailed on failure
        //  4) Refund oracle fee to sender regardless of retry outcome

        address sender = _msgSender();
        IOstiumTradingStorage storageT = IOstiumTradingStorage(registry.getContractAddress("tradingStorage"));

        (
            uint256 _block,
            uint192 wantedPrice,
            uint32 slippageP,
            IOstiumTradingStorage.Trade memory trade,
            uint16 percentage
        ) = storageT.reqID_pendingMarketOrder(_order);

        if (trade.trader == address(0)) {
            revert NoTradeToTimeoutFound(_order);
        }

        if (trade.trader != sender) {
            revert NotYourOrder(_order, trade.trader);
        }

        if (trade.leverage > 0) {
            revert NotCloseMarketTimeoutOrder(_order);
        }

        if (_block == 0 || ChainUtils.getBlockNumber() < _block + marketOrdersTimeout) {
            revert WaitTimeout(_order);
        }

        storageT.unregisterPendingMarketOrder(_order, false);

        uint256 tradeId = storageT.getOpenTradeInfo(sender, trade.pairIndex, trade.index).tradeId;

        if (retry) {
            (bool success,) = address(this)
                .delegatecall(
                    abi.encodeWithSignature(
                        "closeTradeMarket(uint16,uint8,uint16,uint192,uint32)",
                        trade.pairIndex,
                        trade.index,
                        percentage,
                        wantedPrice,
                        slippageP
                    )
                );
            if (!success) {
                emit MarketCloseFailed(tradeId, sender, trade.pairIndex);
            }
        }
        // Always refund oracle fee regardless of partial or full close
        uint256 oracleFee =
            IOstiumPairsStorage(registry.getContractAddress("pairsStorage")).pairOracleFee(trade.pairIndex);
        storageT.refundOracleFee(oracleFee);
        storageT.transferUsdc(address(storageT), sender, oracleFee);
        emit OracleFeeRefunded(_order, sender, trade.pairIndex, oracleFee);

        emit MarketCloseTimeoutExecutedV2(
            _order,
            tradeId,
            IOstiumTradingStorage.PendingMarketOrderV2({
                trade: trade, block: _block, wantedPrice: wantedPrice, slippageP: slippageP, percentage: percentage
            })
        );
    }
}
