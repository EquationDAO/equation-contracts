// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import "./IChainLinkAggregator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceFeed {
    /// @notice Emitted when token price updated
    /// @param token Token address
    /// @param priceX96 The price passed in by updater, as a Q64.96
    /// @param maxPriceX96 Calculated maximum price, as a Q64.96
    /// @param minPriceX96 Calculated minimum price, as a Q64.96
    event PriceUpdated(IERC20 indexed token, uint160 priceX96, uint160 minPriceX96, uint160 maxPriceX96);

    /// @notice Emitted when maxCumulativeDeltaDiff exceeded
    /// @param token Token address
    /// @param priceX96 The price passed in by updater, as a Q64.96
    /// @param refPriceX96 The price provided by ChainLink, as a Q64.96
    /// @param cumulativeDelta The cumulative value of the price change ratio
    /// @param cumulativeRefDelta The cumulative value of the ChainLink price change ratio
    event MaxCumulativeDeltaDiffExceeded(
        IERC20 token,
        uint160 priceX96,
        uint160 refPriceX96,
        uint64 cumulativeDelta,
        uint64 cumulativeRefDelta
    );

    /// @notice Invalid tokens and prices due to length mismatch.
    /// @param tokensLength The length of tokens
    /// @param priceX96sLength The length of prices
    error InvalidTokenPriceInput(uint256 tokensLength, uint256 priceX96sLength);

    /// @notice Price not be initialized
    error NotInitialized();

    /// @notice Reference price feed not set
    error ReferencePriceFeedNotSet();

    /// @notice Invalid reference price
    /// @param referencePrice Reference price
    error InvalidReferencePrice(int256 referencePrice);

    /// @notice Reference price timeout
    /// @param elapsed The time elapsed since the last price update.
    error ReferencePriceTimeout(uint256 elapsed);

    /// @notice Invalid update timestamp
    /// @param timestamp Update timestamp
    error InvalidUpdateTimestamp(uint64 timestamp);
    /// @notice L2 sequencer is down
    error SequencerDown();
    /// @notice Grace period is not over
    /// @param sequencerUptime sequencer uptime
    error GracePeriodNotOver(uint256 sequencerUptime);

    struct Slot {
        uint32 maxDeviationRatio;
        uint32 cumulativeRoundDuration;
        uint32 refPriceExtraSample;
        uint32 updateTxTimeout;
    }

    struct TokenConfig {
        IChainLinkAggregator refPriceFeed;
        uint32 refHeartbeatDuration;
        uint64 maxCumulativeDeltaDiff;
    }

    struct PriceDataItem {
        uint32 prevRound;
        uint160 prevRefPriceX96;
        uint64 cumulativeRefPriceDelta;
        uint160 prevPriceX96;
        uint64 cumulativePriceDelta;
    }

    struct PricePack {
        uint64 updateTimestamp;
        uint160 maxPriceX96;
        uint160 minPriceX96;
        uint64 updateBlockTimestamp;
    }

    /// @notice The 0th storage slot in the price feed stores many values, which helps reduce gas
    /// costs when interacting with the price feed.
    /// @return maxDeviationRatio Maximum deviation ratio between price and ChainLink price.
    /// @return cumulativeRoundDuration Period for calculating cumulative deviation ratio.
    /// @return refPriceExtraSample The number of additional rounds for ChainLink prices to participate in price
    /// update calculation.
    /// @return updateTxTimeout The timeout for price update transactions.
    function slot()
        external
        view
        returns (
            uint32 maxDeviationRatio,
            uint32 cumulativeRoundDuration,
            uint32 refPriceExtraSample,
            uint32 updateTxTimeout
        );

    /// @notice Get token configuration for updating price
    /// @param token The token address to query the configuration
    /// @return refPriceFeed ChainLink contract address for corresponding token
    /// @return refHeartbeatDuration Expected update interval of chain link price feed
    /// @return maxCumulativeDeltaDiff Maximum cumulative change ratio difference between prices and ChainLink prices
    /// within a period of time.
    function tokenConfigs(
        IERC20 token
    )
        external
        view
        returns (IChainLinkAggregator refPriceFeed, uint32 refHeartbeatDuration, uint64 maxCumulativeDeltaDiff);

    /// @notice Get latest price data for corresponding token.
    /// @param token The token address to query the price data
    /// @return updateTimestamp The timestamp when updater uploads the price
    /// @return maxPriceX96 Calculated maximum price, as a Q64.96
    /// @return minPriceX96 Calculated minimum price, as a Q64.96
    /// @return updateBlockTimestamp The block timestamp when price is committed
    function latestPrices(
        IERC20 token
    )
        external
        view
        returns (uint64 updateTimestamp, uint160 maxPriceX96, uint160 minPriceX96, uint64 updateBlockTimestamp);

    /// @notice Update prices
    /// @dev Updater calls this method to update prices for multiple tokens. The contract calculation requires
    /// higher precision prices, so the passed-in prices need to be adjusted.
    ///
    /// ## Example
    ///
    /// The price of ETH is $2000, and ETH has 18 decimals, so the price of one unit of ETH is $`2000 / (10 ^ 18)`.
    ///
    /// The price of USDC is $1, and USDC has 6 decimals, so the price of one unit of USDC is $`1 / (10 ^ 6)`.
    ///
    /// Then the price of ETH/USDC pair is 2000 / (10 ^ 18) * (10 ^ 6)
    ///
    /// Finally convert the price to Q64.96, ETH/USDC priceX96 = 2000 / (10 ^ 18) * (10 ^ 6) * (2 ^ 96)
    /// @param tokens Array of token addresses to update prices for
    /// @param priceX96s Array of prices to be updated by updater
    /// @param timestamp The timestamp of price update
    function setPriceX96s(IERC20[] calldata tokens, uint160[] calldata priceX96s, uint64 timestamp) external;

    /// @notice calculate min and max price if passed a specific price value
    /// @param tokens Array of token addresses to update prices for
    /// @param priceX96s Array of prices to be updated by updater
    function calculatePriceX96s(
        IERC20[] calldata tokens,
        uint160[] calldata priceX96s
    ) external view returns (uint160[] memory minPriceX96s, uint160[] memory maxPriceX96s);

    /// @notice Get minimum token price
    /// @param token The token address to query the price
    /// @return priceX96 Minimum token price
    function getMinPriceX96(IERC20 token) external view returns (uint160 priceX96);

    /// @notice Get maximum token price
    /// @param token The token address to query the price
    /// @return priceX96 Maximum token price
    function getMaxPriceX96(IERC20 token) external view returns (uint160 priceX96);

    /// @notice Set updater status active or not
    /// @param account Updater address
    /// @param active Status of updater permission to set
    function setUpdater(address account, bool active) external;

    /// @notice Check if is updater
    /// @param account The address to query the status
    /// @return active Status of updater
    function isUpdater(address account) external returns (bool active);

    /// @notice Set ChainLink contract address for corresponding token.
    /// @param token The token address to set
    /// @param priceFeed ChainLink contract address
    function setRefPriceFeeds(IERC20 token, IChainLinkAggregator priceFeed) external;

    /// @notice Set SequencerUptimeFeed contract address.
    /// @param sequencerUptimeFeed SequencerUptimeFeed contract address
    function setSequencerUptimeFeed(IChainLinkAggregator sequencerUptimeFeed) external;

    /// @notice Get SequencerUptimeFeed contract address.
    /// @return sequencerUptimeFeed SequencerUptimeFeed contract address
    function sequencerUptimeFeed() external returns (IChainLinkAggregator sequencerUptimeFeed);

    /// @notice Set the expected update interval for the ChainLink oracle price of the corresponding token.
    /// If ChainLink does not update the price within this period, it is considered that ChainLink has broken down.
    /// @param token The token address to set
    /// @param duration Expected update interval
    function setRefHeartbeatDuration(IERC20 token, uint32 duration) external;

    /// @notice Set maximum deviation ratio between price and ChainLink price.
    /// If exceeded, the updated price will refer to ChainLink price.
    /// @param maxDeviationRatio Maximum deviation ratio
    function setMaxDeviationRatio(uint32 maxDeviationRatio) external;

    /// @notice Set period for calculating cumulative deviation ratio.
    /// @param cumulativeRoundDuration Period in seconds to set.
    function setCumulativeRoundDuration(uint32 cumulativeRoundDuration) external;

    /// @notice Set the maximum acceptable cumulative change ratio difference between prices and ChainLink prices
    /// within a period of time. If exceeded, the updated price will refer to ChainLink price.
    /// @param token The token address to set
    /// @param maxCumulativeDeltaDiff Maximum cumulative change ratio difference
    function setMaxCumulativeDeltaDiffs(IERC20 token, uint64 maxCumulativeDeltaDiff) external;

    /// @notice Set number of additional rounds for ChainLink prices to participate in price update calculation.
    /// @param refPriceExtraSample The number of additional sampling rounds.
    function setRefPriceExtraSample(uint32 refPriceExtraSample) external;

    /// @notice Set the timeout for price update transactions.
    /// @param updateTxTimeout The timeout for price update transactions
    function setUpdateTxTimeout(uint32 updateTxTimeout) external;
}
