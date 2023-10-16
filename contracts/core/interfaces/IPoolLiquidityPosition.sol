// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Side} from "../../types/Side.sol";

/// @title Perpetual Pool Liquidity Position Interface
/// @notice This interface defines the functions for managing liquidity positions in a perpetual pool
interface IPoolLiquidityPosition {
    /// @notice Emitted when the unrealized loss metrics of the global liquidity position are changed
    /// @param lastZeroLossTimeAfter The time when the LP's net position no longer has unrealized losses
    /// or the risk buffer fund has enough balance to cover the unrealized losses of all LPs
    /// @param liquidityAfter The total liquidity of all LPs whose entry time is
    /// after `lastZeroLossTime`
    /// @param liquidityTimesUnrealizedLossAfter The product of liquidity and unrealized loss for
    /// each LP whose entry time is after `lastZeroLossTime`
    event GlobalUnrealizedLossMetricsChanged(
        uint64 lastZeroLossTimeAfter,
        uint128 liquidityAfter,
        uint256 liquidityTimesUnrealizedLossAfter
    );

    /// @notice Emitted when an LP opens a liquidity position
    /// @param account The owner of the position
    /// @param positionID The position ID
    /// @param margin The margin of the position
    /// @param liquidity The liquidity of the position
    /// @param entryUnrealizedLoss The snapshot of the unrealized loss of LP at the time of opening the position
    /// @param realizedProfitGrowthX64 The snapshot of `GlobalLiquidityPosition.realizedProfitGrowthX64`
    /// at the time of opening the position, as a Q192.64
    event LiquidityPositionOpened(
        address indexed account,
        uint96 positionID,
        uint128 margin,
        uint128 liquidity,
        uint256 entryUnrealizedLoss,
        uint256 realizedProfitGrowthX64
    );

    /// @notice Emitted when an LP closes a liquidity position
    /// @param positionID The position ID
    /// @param margin The margin removed from the position after closing
    /// @param unrealizedLoss The unrealized loss incurred by the position at the time of closing,
    /// which will be transferred to `GlobalLiquidityPosition.riskBufferFund`
    /// @param realizedProfit The realized profit of the position at the time of closing
    /// @param receiver The address that receives the margin upon closing
    event LiquidityPositionClosed(
        uint96 indexed positionID,
        uint128 margin,
        uint128 unrealizedLoss,
        uint256 realizedProfit,
        address receiver
    );

    /// @notice Emitted when the margin of an LP's position is adjusted
    /// @param positionID The position ID
    /// @param marginDelta Change in margin, positive for increase and negative for decrease
    /// @param marginAfter Adjusted margin
    /// @param entryRealizedProfitGrowthAfterX64 The snapshot of `GlobalLiquidityPosition.realizedProfitGrowthX64`
    ///  after adjustment, as a Q192.64
    /// @param receiver The address that receives the margin when it is decreased
    event LiquidityPositionMarginAdjusted(
        uint96 indexed positionID,
        int128 marginDelta,
        uint128 marginAfter,
        uint256 entryRealizedProfitGrowthAfterX64,
        address receiver
    );

    /// @notice Emitted when an LP's position is liquidated
    /// @param liquidator The address that executes the liquidation of the position
    /// @param positionID The position ID to be liquidated
    /// @param realizedProfit The realized profit of the position at the time of liquidation
    /// @param riskBufferFundDelta The remaining margin of the position after liquidation,
    /// which will be transferred to `GlobalLiquidityPosition.riskBufferFund`
    /// @param liquidationExecutionFee The liquidation execution fee paid by the position
    /// @param feeReceiver The address that receives the liquidation execution fee
    event LiquidityPositionLiquidated(
        address indexed liquidator,
        uint96 indexed positionID,
        uint256 realizedProfit,
        uint256 riskBufferFundDelta,
        uint64 liquidationExecutionFee,
        address feeReceiver
    );

    /// @notice Emitted when the net position of all LP's is adjusted
    /// @param netSizeAfter The adjusted net position size
    /// @param liquidationBufferNetSizeAfter The adjusted net position size in the liquidation buffer
    /// @param entryPriceAfterX96 The adjusted entry price, as a Q64.96
    /// @param sideAfter The adjusted side of the net position
    event GlobalLiquidityPositionNetPositionAdjusted(
        uint128 netSizeAfter,
        uint128 liquidationBufferNetSizeAfter,
        uint160 entryPriceAfterX96,
        Side sideAfter
    );

    /// @notice Emitted when the `realizedProfitGrowthX64` of the global liquidity position is changed
    /// @param realizedProfitGrowthAfterX64 The adjusted `realizedProfitGrowthX64`, as a Q192.64
    event GlobalLiquidityPositionRealizedProfitGrowthChanged(uint256 realizedProfitGrowthAfterX64);

    /// @notice Emitted when the risk buffer fund is used by `Gov`
    /// @param receiver The address that receives the risk buffer fund
    /// @param riskBufferFundDelta The amount of risk buffer fund used
    event GlobalRiskBufferFundGovUsed(address indexed receiver, uint128 riskBufferFundDelta);

    /// @notice Emitted when the risk buffer fund is changed
    event GlobalRiskBufferFundChanged(int256 riskBufferFundAfter);

    /// @notice Emitted when the liquidity of the risk buffer fund is increased
    /// @param account The owner of the position
    /// @param liquidityAfter The total liquidity of the position after the increase
    /// @param unlockTimeAfter The unlock time of the position after the increase
    event RiskBufferFundPositionIncreased(address indexed account, uint128 liquidityAfter, uint64 unlockTimeAfter);

    /// @notice Emitted when the liquidity of the risk buffer fund is decreased
    /// @param account The owner of the position
    /// @param liquidityAfter The total liquidity of the position after the decrease
    /// @param receiver The address that receives the liquidity when it is decreased
    event RiskBufferFundPositionDecreased(address indexed account, uint128 liquidityAfter, address receiver);

    struct GlobalLiquidityPosition {
        uint128 netSize;
        uint128 liquidationBufferNetSize;
        uint160 entryPriceX96;
        Side side;
        uint128 liquidity;
        uint256 realizedProfitGrowthX64;
    }

    struct GlobalRiskBufferFund {
        int256 riskBufferFund;
        uint256 liquidity;
    }

    struct GlobalUnrealizedLossMetrics {
        uint64 lastZeroLossTime;
        uint128 liquidity;
        uint256 liquidityTimesUnrealizedLoss;
    }

    struct LiquidityPosition {
        uint128 margin;
        uint128 liquidity;
        uint256 entryUnrealizedLoss;
        uint256 entryRealizedProfitGrowthX64;
        uint64 entryTime;
        address account;
    }

    struct RiskBufferFundPosition {
        uint128 liquidity;
        uint64 unlockTime;
    }

    /// @notice Get the global liquidity position
    /// @return netSize The size of the net position held by all LPs
    /// @return liquidationBufferNetSize The size of the net position held by all LPs in the liquidation buffer
    /// @return entryPriceX96 The entry price of the net position held by all LPs, as a Q64.96
    /// @return side The side of the position (Long or Short)
    /// @return liquidity The total liquidity of all LPs
    /// @return realizedProfitGrowthX64 The accumulated realized profit growth per liquidity unit, as a Q192.64
    function globalLiquidityPosition()
        external
        view
        returns (
            uint128 netSize,
            uint128 liquidationBufferNetSize,
            uint160 entryPriceX96,
            Side side,
            uint128 liquidity,
            uint256 realizedProfitGrowthX64
        );

    /// @notice Get the global unrealized loss metrics
    /// @return lastZeroLossTime The time when the LP's net position no longer has unrealized losses
    /// or the risk buffer fund has enough balance to cover the unrealized losses of all LPs
    /// @return liquidity The total liquidity of all LPs whose entry time is
    /// after `lastZeroLossTime`
    /// @return liquidityTimesUnrealizedLoss The product of liquidity and unrealized loss for
    /// each LP whose entry time is after `lastZeroLossTime`
    function globalUnrealizedLossMetrics()
        external
        view
        returns (uint64 lastZeroLossTime, uint128 liquidity, uint256 liquidityTimesUnrealizedLoss);

    /// @notice Get the information of a liquidity position
    /// @param positionID The position ID
    /// @return margin The margin of the position
    /// @return liquidity The liquidity (value) of the position
    /// @return entryUnrealizedLoss The snapshot of unrealized loss of LP at the time of opening the position
    /// @return entryRealizedProfitGrowthX64 The snapshot of `GlobalLiquidityPosition.realizedProfitGrowthX64`
    /// at the time of opening the position, as a Q192.64
    /// @return entryTime The time when the position is opened
    /// @return account The owner of the position
    function liquidityPositions(
        uint96 positionID
    )
        external
        view
        returns (
            uint128 margin,
            uint128 liquidity,
            uint256 entryUnrealizedLoss,
            uint256 entryRealizedProfitGrowthX64,
            uint64 entryTime,
            address account
        );

    /// @notice Get the owner of a specific liquidity position
    /// @param positionID The position ID
    /// @return account The owner of the position, `address(0)` returned if the position does not exist
    function liquidityPositionAccount(uint96 positionID) external view returns (address account);

    /// @notice Open a new liquidity position
    /// @dev The call will fail if the caller is not the `IRouter`
    /// @param account The owner of the position
    /// @param margin The margin of the position
    /// @param liquidity The liquidity (value) of the position
    /// @return positionID The position ID
    function openLiquidityPosition(
        address account,
        uint128 margin,
        uint128 liquidity
    ) external returns (uint96 positionID);

    /// @notice Close a liquidity position
    /// @dev The call will fail if the caller is not the `IRouter` or the position does not exist
    /// @param positionID The position ID
    /// @param receiver The address to receive the margin at the time of closing
    function closeLiquidityPosition(uint96 positionID, address receiver) external;

    /// @notice Adjust the margin of a liquidity position
    /// @dev The call will fail if the caller is not the `IRouter` or the position does not exist
    /// @param positionID The position ID
    /// @param marginDelta The change in margin, positive for increasing margin and negative for decreasing margin
    /// @param receiver The address to receive the margin when the margin is decreased
    function adjustLiquidityPositionMargin(uint96 positionID, int128 marginDelta, address receiver) external;

    /// @notice Liquidate a liquidity position
    /// @dev The call will fail if the caller is not the liquidator or the position does not exist
    /// @param positionID The position ID
    /// @param feeReceiver The address to receive the liquidation execution fee
    function liquidateLiquidityPosition(uint96 positionID, address feeReceiver) external;

    /// @notice `Gov` uses the risk buffer fund
    /// @dev The call will fail if the caller is not the `Gov` or
    /// the adjusted remaining risk buffer fund cannot cover the unrealized loss
    /// @param receiver The address to receive the risk buffer fund
    /// @param riskBufferFundDelta The used risk buffer fund
    function govUseRiskBufferFund(address receiver, uint128 riskBufferFundDelta) external;

    /// @notice Get the global risk buffer fund
    /// @return riskBufferFund The risk buffer fund, which accumulated by unrealized losses and price impact fees
    /// paid by LPs when positions are closed or liquidated. It also accumulates the remaining margin of LPs
    /// after liquidation. Additionally, the net profit or loss from closing LP's net position is also accumulated
    /// in the risk buffer fund
    /// @return liquidity The total liquidity of the risk buffer fund
    function globalRiskBufferFund() external view returns (int256 riskBufferFund, uint256 liquidity);

    /// @notice Get the liquidity of the risk buffer fund
    /// @param account The owner of the position
    /// @return liquidity The liquidity of the risk buffer fund
    /// @return unlockTime The time when the liquidity can be withdrawn
    function riskBufferFundPositions(address account) external view returns (uint128 liquidity, uint64 unlockTime);

    /// @notice Increase the liquidity of a risk buffer fund position
    /// @dev The call will fail if the caller is not the `IRouter`
    /// @param account The owner of the position
    /// @param liquidityDelta The increase in liquidity
    function increaseRiskBufferFundPosition(address account, uint128 liquidityDelta) external;

    /// @notice Decrease the liquidity of a risk buffer fund position
    /// @dev The call will fail if the caller is not the `IRouter`
    /// @param account The owner of the position
    /// @param liquidityDelta The decrease in liquidity
    /// @param receiver The address to receive the liquidity when it is decreased
    function decreaseRiskBufferFundPosition(address account, uint128 liquidityDelta, address receiver) external;
}
