// SPDX-License-Identifier: MIT
<<<<<<< HEAD
import "./interfaces/IOwnable.sol";
import "./interfaces/IOstiumVault.sol";
import "./interfaces/IOstiumOpenPnl.sol";
import "./interfaces/IOstiumRegistry.sol";
=======
import './interfaces/IOwnable.sol';
import './interfaces/IOstiumVault.sol';
import './interfaces/IOstiumOpenPnl.sol';
import './interfaces/IOstiumRegistry.sol';
import './interfaces/IOstiumTradingStorage.sol';
import './interfaces/IOstiumPairInfos.sol';
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

pragma solidity ^0.8.24;

contract OstiumOpenPnl is IOstiumOpenPnl, Initializable {
    using SafeCast for uint256;

    uint64 constant PRECISION_18 = 1e18; // 18 decimals
    uint32 constant PRECISION_6 = 1e6; // 6 decimals
    uint8 constant PRECISION_2 = 1e2; // 2 decimals

    IOstiumRegistry public registry;

    int256 private accTotalPnl;
    int256 private accClosedPnl;

    int256[] public __DEPRECATED_nextEpochValues;
    uint256 public __DEPRECATED_lastRequestId;
    uint32 public __DEPRECATED_requestsStart;
    uint32 public __DEPRECATED_requestsEvery;
    uint32 public __DEPRECATED_nextEpochValuesLastRequestTs;
    uint8 public __DEPRECATED_nextEpochValuesRequestCount;
    uint8 public __DEPRECATED_requestsCount;

    mapping(uint16 pairIndex => int256) public lastTradePrice;
    mapping(uint16 pairIndex => int256) public accNetOiUnits;

    int256 private accTotalRollover; // 18 decimals
    int256 private accClosedRollover; // 18 decimals

    mapping(uint16 pairIndex => mapping(bool long => uint256)) public currentNotional; // notional -> 6 decimals

    constructor() {
        _disableInitializers();
    }

    function initialize(IOstiumRegistry _registry) external initializer {
        if (address(_registry) == address(0)) {
            revert WrongParams();
        }
        registry = _registry;
        //_updateRequestsStart(2 days);
        //_updateRequestsEvery(3 hours);
        //_updateRequestsCount(8);
    }

    function initializeV2(
        int256 openRolloverFee,
        uint16[] calldata pairIds,
        uint256[] calldata currentLongNotional,
        uint256[] calldata currentShortNotional
    ) external reinitializer(2) {
        if (pairIds.length != currentLongNotional.length || pairIds.length != currentShortNotional.length) {
            revert WrongParams();
        }

        accTotalRollover = openRolloverFee;

        for (uint256 i; i < pairIds.length; i++) {
            uint16 pairId = pairIds[i];
            currentNotional[pairId][true] = currentLongNotional[i];
            currentNotional[pairId][false] = currentShortNotional[i];
        }
    }

    modifier onlyCallbacks() {
        _onlyCallbacks();
        _;
    }

    function _onlyCallbacks() internal view {
        if (msg.sender != registry.getContractAddress('callbacks')) revert NotCallbacks(msg.sender);
    }

    modifier onlyPairInfos() {
        _onlyPairInfos();
        _;
    }

<<<<<<< HEAD
    function _updateRequestsStart(uint256 newValue) private {
        if (newValue < MIN_REQUESTS || newValue > MAX_REQUESTS_START) {
            revert WrongParams();
        }
        requestsStart = uint32(newValue);
        emit RequestsStartUpdated(newValue);
    }

    function updateRequestsEvery(uint256 newValue) public onlyRegistryOwner {
        _updateRequestsEvery(newValue);
    }

    function _updateRequestsEvery(uint256 newValue) private {
        if (newValue < MIN_REQUESTS || newValue > MAX_REQUESTS_EVERY) {
            revert WrongParams();
        }
        requestsEvery = uint32(newValue);
        emit RequestsEveryUpdated(newValue);
    }

    function updateRequestsCount(uint256 newValue) public onlyRegistryOwner {
        _updateRequestsCount(newValue);
    }

    function _updateRequestsCount(uint256 newValue) private {
        if (newValue < MIN_REQUESTS_COUNT || newValue > MAX_REQUESTS_COUNT) {
            revert WrongParams();
        }
        requestsCount = uint8(newValue);
        emit RequestsCountUpdated(newValue);
    }

    function updateRequestsInfoBatch(uint256 newRequestsStart, uint256 newRequestsEvery, uint256 newRequestsCount)
        external
        onlyRegistryOwner
    {
        updateRequestsStart(newRequestsStart);
        updateRequestsEvery(newRequestsEvery);
        updateRequestsCount(newRequestsCount);
    }

    function forceNewEpoch() external {
        if (
            block.timestamp - IOstiumVault(registry.getContractAddress("vault")).currentEpochStart()
                < requestsStart + requestsEvery * requestsCount
        ) revert TooEarly();

        uint256 newEpoch = startNewEpoch();
        emit NewEpochForced(newEpoch);
    }

    function newOpenPnlRequestOrEpoch() external {
        bool firstRequest = nextEpochValuesLastRequestTs == 0;

        if (
            firstRequest
                && block.timestamp - IOstiumVault(registry.getContractAddress("vault")).currentEpochStart()
                    >= requestsStart
        ) {
            makeOpenPnlRequest();
        } else if (!firstRequest && block.timestamp - nextEpochValuesLastRequestTs >= requestsEvery) {
            if (nextEpochValuesRequestCount < requestsCount) {
                makeOpenPnlRequest();
            } else if (nextEpochValues.length >= requestsCount) {
                startNewEpoch();
            }
        }
=======
    function _onlyPairInfos() internal view {
        if (msg.sender != registry.getContractAddress('pairInfos')) revert NotPairInfos(msg.sender);
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
    }

    function getOpenPnl() public view returns (int256) {
        return (accTotalPnl - accClosedPnl);
    }

<<<<<<< HEAD
    function makeOpenPnlRequest() private {
        ++lastRequestId;
        nextEpochValuesRequestCount++;
        nextEpochValuesLastRequestTs = uint32(block.timestamp);

        int256 openPnlValue = getOpenPnl();
        nextEpochValues.push(openPnlValue);

        emit NextEpochValueRequested(
            IOstiumVault(registry.getContractAddress("vault")).currentEpoch(), lastRequestId, openPnlValue
        );
    }

    function startNewEpoch() private returns (uint256 newEpoch) {
        IOstiumVault vault = IOstiumVault(registry.getContractAddress("vault"));
        nextEpochValuesRequestCount = 0;
        nextEpochValuesLastRequestTs = 0;

        uint256 currentEpochPositiveOpenPnl = vault.currentEpochPositiveOpenPnl();

        // If all responses arrived, use mean, otherwise it means we forced a new epoch,
        // so as a safety we use the last epoch value
        int256 newEpochOpenPnl =
            nextEpochValues.length >= requestsCount ? average(nextEpochValues) : currentEpochPositiveOpenPnl.toInt256();

        uint256 finalNewEpochPositiveOpenPnl = vault.updateAccPnlPerTokenUsed(
            currentEpochPositiveOpenPnl, newEpochOpenPnl > 0 ? uint256(newEpochOpenPnl) : 0
        );

        newEpoch = vault.currentEpoch();

        emit NewEpoch(newEpoch, lastRequestId, nextEpochValues, newEpochOpenPnl, finalNewEpochPositiveOpenPnl);

        delete nextEpochValues;
=======
    function getOpenRolloverFee() public view returns (int256) {
        return (accTotalRollover - accClosedRollover);
    }

    function getOpenPnlWithRollover() public view returns (int256) {
        return (getOpenPnl() - getOpenRolloverFee());
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
    }

    function updateAccTotalPnl(
        int256 oraclePrice,
        uint256 openPrice,
        uint256 closePrice,
        uint256 oiNotional,
        uint16 pairIndex,
        bool buy,
        bool open
<<<<<<< HEAD
    ) external {
        if (msg.sender != registry.getContractAddress("callbacks")) {
            revert NotCallbacks(msg.sender);
        }
=======
    ) external onlyCallbacks {
>>>>>>> 8390ce497f68fb128900840e0ec30683afa945d3
        int256 oiNotionalSigned = buy ? oiNotional.toInt256() : -oiNotional.toInt256();

        if (open) {
            accTotalPnl -= oiNotionalSigned * (openPrice.toInt256() - oraclePrice) / int64(PRECISION_18);
        } else {
            accTotalPnl -= oiNotionalSigned * (oraclePrice - closePrice.toInt256()) / int64(PRECISION_18);
            accClosedPnl -= oiNotionalSigned * (openPrice.toInt256() - closePrice.toInt256()) / int64(PRECISION_18);
        }

        accTotalPnl += (oraclePrice - lastTradePrice[pairIndex]) * accNetOiUnits[pairIndex] / int64(PRECISION_18);

        lastTradePrice[pairIndex] = oraclePrice;
        emit LastTradePriceUpdated(pairIndex, oraclePrice);

        accNetOiUnits[pairIndex] =
            open ? accNetOiUnits[pairIndex] + oiNotionalSigned : accNetOiUnits[pairIndex] - oiNotionalSigned;

        emit AccTotalPnlUpdated(pairIndex, accTotalPnl, accClosedPnl, accNetOiUnits[pairIndex]);
    }

    function updateAccTotalRollover(uint16 pairIndex, bool long, int256 prevAccRollover, int256 newAccRollover)
        external
        onlyPairInfos
    {
        accTotalRollover += getRolloverFee(newAccRollover - prevAccRollover, currentNotional[pairIndex][long]);
        emit OpenRolloverUpdated(pairIndex, long, accTotalRollover, accClosedRollover, currentNotional[pairIndex][long]);
    }

    function updateAccClosedRollover(IOstiumTradingStorage.Trade memory t, uint16 closePercentage)
        external
        onlyCallbacks
    {
        bool long = t.buy;
        uint16 pairIndex = t.pairIndex;

        if (closePercentage == 0) {
            uint256 notional = t.collateral * t.leverage / PRECISION_2;
            currentNotional[pairIndex][long] += notional;
        } else {
            uint256 collateralToClose = t.collateral * closePercentage / 100e2;
            uint256 notional = collateralToClose * t.leverage / PRECISION_2; // mirrors unregisterTrade to avoid currentNotional drift
            if (notional > currentNotional[pairIndex][long]) {
                emit CurrentNotionalUnderflow(pairIndex, long, currentNotional[pairIndex][long], notional);
                notional = currentNotional[pairIndex][long];
            }
            currentNotional[pairIndex][long] -= notional;

            int256 initAccRollover = IOstiumPairInfos(registry.getContractAddress('pairInfos'))
                .getTradeInitialAccRolloverFeesPerCollateral(t.trader, t.pairIndex, t.index);
            int256 currentAccRollover =
                IOstiumPairInfos(registry.getContractAddress('pairInfos')).getAccRollover(t.pairIndex, t.buy);
            accClosedRollover += getRolloverFee(currentAccRollover - initAccRollover, notional);
        }
        emit OpenRolloverUpdated(pairIndex, long, accTotalRollover, accClosedRollover, currentNotional[pairIndex][long]);
    }

    function getRolloverFee(int256 deltaAccRollover, uint256 notional) private pure returns (int256) {
        return deltaAccRollover * notional.toInt256() / int32(PRECISION_6);
    }
}
