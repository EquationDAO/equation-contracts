// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../libraries/SafeCast.sol";
import "../libraries/Constants.sol";
import {M as Math} from "../libraries/Math.sol";
import "./interfaces/IPriceFeed.sol";
import "../governance/Governable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PriceFeed is IPriceFeed, Governable {
    using SafeCast for *;
    using SafeMath for *;

    /// @dev value difference precision
    uint256 public constant DELTA_PRECISION = 1000 * 1000;
    /// @dev seconds after l2 sequencer comes back online that we start accepting price feed data.
    uint256 public constant GRACE_PERIOD_TIME = 30 minutes;
    uint8 public constant USD_DECIMALS = 6;
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @inheritdoc IPriceFeed
    IChainLinkAggregator public override stableTokenPriceFeed;
    /// @inheritdoc IPriceFeed
    uint32 public override stableTokenPriceFeedHeartBeatDuration;

    /// @inheritdoc IPriceFeed
    Slot public override slot;
    mapping(address => bool) private updaters;
    /// @inheritdoc IPriceFeed
    IChainLinkAggregator public override sequencerUptimeFeed;
    /// @inheritdoc IPriceFeed
    mapping(IERC20 => TokenConfig) public override tokenConfigs;

    /// @dev latest price
    mapping(IERC20 => PricePack) public override latestPrices;
    mapping(IERC20 => PriceDataItem) private priceDataItems;

    modifier onlyUpdater() {
        if (!updaters[msg.sender]) revert Forbidden();
        _;
    }

    constructor(IChainLinkAggregator _stableTokenPriceFeed, uint32 _stableTokenPriceFeedHeartBeatDuration) {
        (slot.maxDeviationRatio, slot.cumulativeRoundDuration, slot.updateTxTimeout) = (100e3, 1 minutes, 1 minutes);
        stableTokenPriceFeed = _stableTokenPriceFeed;
        stableTokenPriceFeedHeartBeatDuration = _stableTokenPriceFeedHeartBeatDuration;
    }

    /// @inheritdoc IPriceFeed
    function calculatePriceX96s(
        TokenPrice[] calldata _tokenPrices
    ) external view returns (uint160[] memory minPriceX96s, uint160[] memory maxPriceX96s) {
        uint256 priceX96sLength = _tokenPrices.length;

        minPriceX96s = new uint160[](priceX96sLength);
        maxPriceX96s = new uint160[](priceX96sLength);
        (uint256 stableTokenPrice, uint8 stableTokenDecimals) = _getStableTokenPrice();
        for (uint256 i; i < priceX96sLength; ) {
            uint160 priceX96 = _tokenPrices[i].priceX96;
            IERC20 token = _tokenPrices[i].token;
            TokenConfig memory tokenConfig = tokenConfigs[token];
            if (address(tokenConfig.refPriceFeed) == address(0)) revert ReferencePriceFeedNotSet();

            (uint160 latestRefPriceX96, uint160 minRefPriceX96, uint160 maxRefPriceX96) = _getReferencePriceX96(
                tokenConfig.refPriceFeed,
                tokenConfig.refHeartbeatDuration,
                stableTokenPrice,
                stableTokenDecimals
            );

            (, bool reachMaxDeltaDiff) = _calculateNewPriceDataItem(
                token,
                priceX96,
                latestRefPriceX96,
                tokenConfig.maxCumulativeDeltaDiff
            );

            (minPriceX96s[i], maxPriceX96s[i]) = _reviseMinAndMaxPriceX96(
                priceX96,
                minRefPriceX96,
                maxRefPriceX96,
                reachMaxDeltaDiff
            );

            // prettier-ignore
            unchecked { ++i; }
        }
        return (minPriceX96s, maxPriceX96s);
    }

    /// @inheritdoc IPriceFeed
    function setPriceX96s(TokenPrice[] calldata _tokenPrices, uint64 _timestamp) external override onlyUpdater {
        uint256 tokenPricesLength = _tokenPrices.length;
        _checkSequencerUp();
        (uint256 stableTokenPrice, uint8 stableTokenDecimals) = _getStableTokenPrice();
        for (uint256 i; i < tokenPricesLength; ++i) {
            uint160 priceX96 = _tokenPrices[i].priceX96;
            IERC20 token = _tokenPrices[i].token;
            PricePack storage pack = latestPrices[token];
            if (!_setTokenLastUpdated(pack, _timestamp)) continue;
            TokenConfig memory tokenConfig = tokenConfigs[token];
            if (address(tokenConfig.refPriceFeed) == address(0)) revert ReferencePriceFeedNotSet();
            (uint160 latestRefPriceX96, uint160 minRefPriceX96, uint160 maxRefPriceX96) = _getReferencePriceX96(
                tokenConfig.refPriceFeed,
                tokenConfig.refHeartbeatDuration,
                stableTokenPrice,
                stableTokenDecimals
            );

            (PriceDataItem memory newItem, bool reachMaxDeltaDiff) = _calculateNewPriceDataItem(
                token,
                priceX96,
                latestRefPriceX96,
                tokenConfig.maxCumulativeDeltaDiff
            );
            priceDataItems[token] = newItem;

            if (reachMaxDeltaDiff)
                emit MaxCumulativeDeltaDiffExceeded(
                    token,
                    priceX96,
                    latestRefPriceX96,
                    newItem.cumulativePriceDelta,
                    newItem.cumulativeRefPriceDelta
                );
            (uint160 minPriceX96, uint160 maxPriceX96) = _reviseMinAndMaxPriceX96(
                priceX96,
                minRefPriceX96,
                maxRefPriceX96,
                reachMaxDeltaDiff
            );
            pack.minPriceX96 = minPriceX96;
            pack.maxPriceX96 = maxPriceX96;
            emit PriceUpdated(token, priceX96, minPriceX96, maxPriceX96);
        }
    }

    /// @inheritdoc IPriceFeed
    function getMinPriceX96(IERC20 _token) external view override returns (uint160 priceX96) {
        _checkSequencerUp();
        priceX96 = latestPrices[_token].minPriceX96;
        if (priceX96 == 0) revert NotInitialized();
    }

    /// @inheritdoc IPriceFeed
    function getMaxPriceX96(IERC20 _token) external view override returns (uint160 priceX96) {
        _checkSequencerUp();
        priceX96 = latestPrices[_token].maxPriceX96;
        if (priceX96 == 0) revert NotInitialized();
    }

    /// @inheritdoc IPriceFeed
    function setUpdater(address _account, bool _active) external override onlyGov {
        updaters[_account] = _active;
    }

    /// @inheritdoc IPriceFeed
    function isUpdater(address _account) external view override returns (bool active) {
        return updaters[_account];
    }

    /// @inheritdoc IPriceFeed
    function setRefPriceFeed(IERC20 _token, IChainLinkAggregator _priceFeed) external override onlyGov {
        tokenConfigs[_token].refPriceFeed = _priceFeed;
    }

    /// @inheritdoc IPriceFeed
    function setSequencerUptimeFeed(IChainLinkAggregator _sequencerUptimeFeed) external override onlyGov {
        sequencerUptimeFeed = _sequencerUptimeFeed;
    }

    /// @inheritdoc IPriceFeed
    function setRefHeartbeatDuration(IERC20 _token, uint32 _duration) external override onlyGov {
        tokenConfigs[_token].refHeartbeatDuration = _duration;
    }

    /// @inheritdoc IPriceFeed
    function setMaxDeviationRatio(uint32 _maxDeviationRatio) external override onlyGov {
        slot.maxDeviationRatio = _maxDeviationRatio;
    }

    /// @inheritdoc IPriceFeed
    function setCumulativeRoundDuration(uint32 _cumulativeRoundDuration) external override onlyGov {
        slot.cumulativeRoundDuration = _cumulativeRoundDuration;
    }

    /// @inheritdoc IPriceFeed
    function setMaxCumulativeDeltaDiffs(IERC20 _token, uint64 _maxCumulativeDeltaDiff) external override onlyGov {
        tokenConfigs[_token].maxCumulativeDeltaDiff = _maxCumulativeDeltaDiff;
    }

    /// @inheritdoc IPriceFeed
    function setRefPriceExtraSample(uint32 _refPriceExtraSample) external override onlyGov {
        slot.refPriceExtraSample = _refPriceExtraSample;
    }

    /// @inheritdoc IPriceFeed
    function setUpdateTxTimeout(uint32 _updateTxTimeout) external override onlyGov {
        slot.updateTxTimeout = _updateTxTimeout;
    }

    /// @inheritdoc IPriceFeed
    function setStableTokenPriceFeed(
        IChainLinkAggregator _stableTokenPriceFeed,
        uint32 _stableTokenPriceFeedHeartBeatDuration
    ) external override onlyGov {
        (stableTokenPriceFeed, stableTokenPriceFeedHeartBeatDuration) = (
            _stableTokenPriceFeed,
            _stableTokenPriceFeedHeartBeatDuration
        );
    }

    function _calculateNewPriceDataItem(
        IERC20 _token,
        uint160 _priceX96,
        uint160 _refPriceX96,
        uint64 _maxCumulativeDeltaDiffs
    ) private view returns (PriceDataItem memory item, bool reachMaxDeltaDiff) {
        item = priceDataItems[_token];
        uint32 currentRound = uint32(block.timestamp / slot.cumulativeRoundDuration);
        if (currentRound != item.prevRound || item.prevRefPriceX96 == 0 || item.prevPriceX96 == 0) {
            item.cumulativePriceDelta = 0;
            item.cumulativeRefPriceDelta = 0;
            item.prevRefPriceX96 = _refPriceX96;
            item.prevPriceX96 = _priceX96;
            item.prevRound = currentRound;
            return (item, false);
        }

        unchecked {
            uint256 cumulativeRefPriceDelta = _calculateDiffBasisPoints(_refPriceX96, item.prevRefPriceX96);
            uint256 cumulativePriceDelta = _calculateDiffBasisPoints(_priceX96, item.prevPriceX96);

            item.cumulativeRefPriceDelta = item.cumulativeRefPriceDelta.add(cumulativeRefPriceDelta).toUint64();
            item.cumulativePriceDelta = item.cumulativePriceDelta.add(cumulativePriceDelta).toUint64();
            if (
                item.cumulativePriceDelta > item.cumulativeRefPriceDelta &&
                item.cumulativePriceDelta - item.cumulativeRefPriceDelta > _maxCumulativeDeltaDiffs
            ) reachMaxDeltaDiff = true;

            item.prevRefPriceX96 = _refPriceX96;
            item.prevPriceX96 = _priceX96;
            item.prevRound = currentRound;
            return (item, reachMaxDeltaDiff);
        }
    }

    function _getReferencePriceX96(
        IChainLinkAggregator _aggregator,
        uint32 _refHeartbeatDuration,
        uint256 _stableTokenPrice,
        uint8 _stableTokenPriceDecimals
    ) private view returns (uint160 _latestRefPriceX96, uint160 _minRefPriceX96, uint160 _maxRefPriceX96) {
        (uint80 roundID, int256 refUSDPrice, , uint256 timestamp, ) = _aggregator.latestRoundData();
        if (refUSDPrice <= 0) revert InvalidReferencePrice(refUSDPrice);
        if (_refHeartbeatDuration != 0 && block.timestamp - timestamp > _refHeartbeatDuration)
            revert ReferencePriceTimeout(block.timestamp - timestamp);
        uint256 priceDecimalsMagnification = 10 ** uint256(_stableTokenPriceDecimals);
        uint256 refPrice = Math.mulDiv(uint256(refUSDPrice), priceDecimalsMagnification, _stableTokenPrice);
        uint256 magnification = 10 ** uint256(_aggregator.decimals());
        _latestRefPriceX96 = _toPriceX96(refPrice, magnification);
        if (slot.refPriceExtraSample == 0) return (_latestRefPriceX96, _latestRefPriceX96, _latestRefPriceX96);

        (int256 minRefUSDPrice, int256 maxRefUSDPrice) = (refUSDPrice, refUSDPrice);
        for (uint256 i = 1; i <= slot.refPriceExtraSample; ) {
            (, int256 price, , , ) = _aggregator.getRoundData(uint80(roundID - i));
            if (price > maxRefUSDPrice) maxRefUSDPrice = price;

            if (price < minRefUSDPrice) minRefUSDPrice = price;

            // prettier-ignore
            unchecked { ++i; }
        }
        if (minRefUSDPrice <= 0) revert InvalidReferencePrice(minRefUSDPrice);

        uint256 minRefPrice = Math.mulDiv(uint256(minRefUSDPrice), priceDecimalsMagnification, _stableTokenPrice);
        uint256 maxRefPrice = Math.mulDiv(uint256(maxRefUSDPrice), priceDecimalsMagnification, _stableTokenPrice);
        _minRefPriceX96 = _toPriceX96(minRefPrice, magnification);
        _maxRefPriceX96 = _toPriceX96(maxRefPrice, magnification);
    }

    function _toPriceX96(uint256 _price, uint256 _magnification) private pure returns (uint160) {
        // prettier-ignore
        unchecked { _price = Math.mulDiv(_price, Constants.Q96, uint256(10) ** TOKEN_DECIMALS); }
        _price = uint256(10) ** USD_DECIMALS >= _magnification
            ? _price * (uint256(10) ** USD_DECIMALS / _magnification)
            : _price / (_magnification / uint256(10) ** USD_DECIMALS);
        return _price.toUint160();
    }

    function _setTokenLastUpdated(PricePack storage _latestPrice, uint64 _timestamp) private returns (bool) {
        // Execution delay may cause the update time to be out of order.
        if (block.timestamp == _latestPrice.updateBlockTimestamp || _timestamp <= _latestPrice.updateTimestamp)
            return false;

        uint32 _updateTxTimeout = slot.updateTxTimeout;
        // timeout and revert
        if (_timestamp <= block.timestamp - _updateTxTimeout || _timestamp >= block.timestamp + _updateTxTimeout)
            revert InvalidUpdateTimestamp(_timestamp);

        _latestPrice.updateTimestamp = _timestamp;
        _latestPrice.updateBlockTimestamp = block.timestamp.toUint64();
        return true;
    }

    function _reviseMinAndMaxPriceX96(
        uint160 _priceX96,
        uint160 _minRefPriceX96,
        uint160 _maxRefPriceX96,
        bool _reachMaxDeltaDiff
    ) private view returns (uint160 minPriceX96, uint160 maxPriceX96) {
        uint256 diffBasisPointsMin = _calculateDiffBasisPoints(_priceX96, _minRefPriceX96);
        if ((diffBasisPointsMin > slot.maxDeviationRatio || _reachMaxDeltaDiff) && _minRefPriceX96 < _priceX96)
            minPriceX96 = _minRefPriceX96;
        else minPriceX96 = _priceX96;

        uint256 diffBasisPointsMax = _calculateDiffBasisPoints(_priceX96, _maxRefPriceX96);
        if ((diffBasisPointsMax > slot.maxDeviationRatio || _reachMaxDeltaDiff) && _maxRefPriceX96 > _priceX96)
            maxPriceX96 = _maxRefPriceX96;
        else maxPriceX96 = _priceX96;
    }

    function _calculateDiffBasisPoints(uint160 _priceX96, uint160 _basisPriceX96) private pure returns (uint256) {
        unchecked {
            uint160 deltaX96 = _priceX96 > _basisPriceX96 ? _priceX96 - _basisPriceX96 : _basisPriceX96 - _priceX96;
            return (uint256(deltaX96) * DELTA_PRECISION) / _basisPriceX96;
        }
    }

    function _checkSequencerUp() private view {
        if (address(sequencerUptimeFeed) == address(0)) return;
        (, int256 answer, uint256 startedAt, , ) = sequencerUptimeFeed.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        if (answer != 0) revert SequencerDown();

        // Make sure the grace period has passed after the sequencer is back up.
        if (block.timestamp - startedAt <= GRACE_PERIOD_TIME) revert GracePeriodNotOver(startedAt);
    }

    function _getStableTokenPrice() private view returns (uint256, uint8) {
        IChainLinkAggregator priceFeed = stableTokenPriceFeed;
        uint32 heartbeatDuration = stableTokenPriceFeedHeartBeatDuration;

        (, int256 stableTokenPrice, , uint256 timestamp, ) = priceFeed.latestRoundData();
        if (heartbeatDuration != 0 && block.timestamp - timestamp > heartbeatDuration)
            revert StableTokenPriceTimeout(block.timestamp - timestamp);

        if (stableTokenPrice <= 0) revert InvalidStableTokenPrice(stableTokenPrice);
        return (uint256(stableTokenPrice), priceFeed.decimals());
    }
}
