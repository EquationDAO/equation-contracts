// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Side} from "../../types/Side.sol";

/// @title Perpetual Pool Position Interface
/// @notice This interface defines the functions for managing positions in a perpetual pool
interface IPoolPosition {
    /// @notice Emitted when the funding rate growth is adjusted
    /// @param fundingRateDeltaX96 The change in funding rate, a positive value means longs pay shorts,
    /// when a negative value means shorts pay longs, as a Q160.96
    /// @param longFundingRateGrowthAfterX96 The adjusted `GlobalPosition.longFundingRateGrowthX96`, as a Q96.96
    /// @param shortFundingRateGrowthAfterX96 The adjusted `GlobalPosition.shortFundingRateGrowthX96`, as a Q96.96
    /// @param lastAdjustFundingRateTime The adjusted `GlobalFundingRateSample.lastAdjustFundingRateTime`
    event FundingRateGrowthAdjusted(
        int256 fundingRateDeltaX96,
        int192 longFundingRateGrowthAfterX96,
        int192 shortFundingRateGrowthAfterX96,
        uint64 lastAdjustFundingRateTime
    );

    /// @notice Emitted when the position margin/liquidity (value) is increased
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The increased margin
    /// @param marginAfter The adjusted margin
    /// @param sizeAfter The adjusted position size
    /// @param tradePriceX96 The trade price at which the position is adjusted.
    /// If only adding margin, it returns 0, as a Q64.96
    /// @param entryPriceAfterX96 The adjusted entry price of the position, as a Q64.96
    /// @param fundingFee The funding fee, a positive value means the position receives funding fee,
    /// while a negative value means the position positive pays funding fee
    /// @param tradingFee The trading fee paid by the position
    event PositionIncreased(
        address indexed account,
        Side side,
        uint128 marginDelta,
        uint128 marginAfter,
        uint128 sizeAfter,
        uint160 tradePriceX96,
        uint160 entryPriceAfterX96,
        int256 fundingFee,
        uint128 tradingFee
    );

    /// @notice Emitted when the position margin/liquidity (value) is decreased
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The decreased margin
    /// @param marginAfter The adjusted margin
    /// @param sizeAfter The adjusted position size
    /// @param tradePriceX96 The trade price at which the position is adjusted.
    /// If only reducing margin, it returns 0, as a Q64.96
    /// @param realizedPnLDelta The realized PnL
    /// @param fundingFee The funding fee, a positive value means the position receives a funding fee,
    /// while a negative value means the position pays funding fee
    /// @param tradingFee The trading fee paid by the position
    /// @param receiver The address that receives the margin
    event PositionDecreased(
        address indexed account,
        Side side,
        uint128 marginDelta,
        uint128 marginAfter,
        uint128 sizeAfter,
        uint160 tradePriceX96,
        int256 realizedPnLDelta,
        int256 fundingFee,
        uint128 tradingFee,
        address receiver
    );

    /// @notice Emitted when a position is liquidated
    /// @param liquidator The address that executes the liquidation of the position
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param indexPriceX96 The index price when liquidating the position, as a Q64.96
    /// @param liquidationPriceX96 The liquidation price of the position, as a Q64.96
    /// @param fundingFee The funding fee, a positive value means the position receives a funding fee,
    /// while a negative value means the position pays funding fee. If it's negative,
    /// it represents the actual funding fee paid during liquidation
    /// @param tradingFee The trading fee paid by the position
    /// @param liquidationFee The liquidation fee paid by the position
    /// @param liquidationExecutionFee The liquidation execution fee paid by the position
    /// @param feeReceiver The address that receives the liquidation execution fee
    event PositionLiquidated(
        address indexed liquidator,
        address indexed account,
        Side side,
        uint160 indexPriceX96,
        uint160 liquidationPriceX96,
        int256 fundingFee,
        uint128 tradingFee,
        uint128 liquidationFee,
        uint64 liquidationExecutionFee,
        address feeReceiver
    );

    struct GlobalPosition {
        uint128 longSize;
        uint128 shortSize;
        int192 longFundingRateGrowthX96;
        int192 shortFundingRateGrowthX96;
    }

    struct PreviousGlobalFundingRate {
        int192 longFundingRateGrowthX96;
        int192 shortFundingRateGrowthX96;
    }

    struct GlobalFundingRateSample {
        uint64 lastAdjustFundingRateTime;
        uint16 sampleCount;
        int176 cumulativePremiumRateX96;
    }

    struct Position {
        uint128 margin;
        uint128 size;
        uint160 entryPriceX96;
        int192 entryFundingRateGrowthX96;
    }

    /// @notice Get the global position
    /// @return longSize The sum of long position sizes
    /// @return shortSize The sum of short position sizes
    /// @return longFundingRateGrowthX96 The funding rate growth per unit of long position sizes, as a Q96.96
    /// @return shortFundingRateGrowthX96 The funding rate growth per unit of short position sizes, as a Q96.96
    function globalPosition()
        external
        view
        returns (
            uint128 longSize,
            uint128 shortSize,
            int192 longFundingRateGrowthX96,
            int192 shortFundingRateGrowthX96
        );

    /// @notice Get the previous global funding rate growth
    /// @return longFundingRateGrowthX96 The funding rate growth per unit of long position sizes, as a Q96.96
    /// @return shortFundingRateGrowthX96 The funding rate growth per unit of short position sizes, as a Q96.96
    function previousGlobalFundingRate()
        external
        view
        returns (int192 longFundingRateGrowthX96, int192 shortFundingRateGrowthX96);

    /// @notice Get the global funding rate sample
    /// @return lastAdjustFundingRateTime The timestamp of the last funding rate adjustment
    /// @return sampleCount The number of samples taken since the last funding rate adjustment
    /// @return cumulativePremiumRateX96 The cumulative premium rate of the samples taken
    /// since the last funding rate adjustment, as a Q80.96
    function globalFundingRateSample()
        external
        view
        returns (uint64 lastAdjustFundingRateTime, uint16 sampleCount, int176 cumulativePremiumRateX96);

    /// @notice Get the information of a position
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @return margin The margin of the position
    /// @return size The size of the position
    /// @return entryPriceX96 The entry price of the position, as a Q64.96
    /// @return entryFundingRateGrowthX96 The snapshot of the funding rate growth at the time the position was opened.
    /// For long positions it is `GlobalPosition.longFundingRateGrowthX96`,
    /// and for short positions it is `GlobalPosition.shortFundingRateGrowthX96`
    function positions(
        address account,
        Side side
    ) external view returns (uint128 margin, uint128 size, uint160 entryPriceX96, int192 entryFundingRateGrowthX96);

    /// @notice Increase the margin/liquidity (value) of a position
    /// @dev The call will fail if the caller is not the `IRouter`
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The increase in margin, which can be 0
    /// @param sizeDelta The increase in size, which can be 0
    /// @return tradePriceX96 The trade price at which the position is adjusted.
    /// If only adding margin, it returns 0, as a Q64.96
    function increasePosition(
        address account,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta
    ) external returns (uint160 tradePriceX96);

    /// @notice Decrease the margin/liquidity (value) of a position
    /// @dev The call will fail if the caller is not the `IRouter` or the position does not exist
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The decrease in margin, which can be 0
    /// @param sizeDelta The decrease in size, which can be 0
    /// @param receiver The address to receive the margin
    /// @return tradePriceX96 The trade price at which the position is adjusted.
    /// If only reducing margin, it returns 0, as a Q64.96
    function decreasePosition(
        address account,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        address receiver
    ) external returns (uint160 tradePriceX96);

    /// @notice Liquidate a position
    /// @dev The call will fail if the caller is not the liquidator or the position does not exist
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param feeReceiver The address that receives the liquidation execution fee
    function liquidatePosition(address account, Side side, address feeReceiver) external;
}
