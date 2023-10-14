// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../core/interfaces/IPool.sol";
import "../../oracle/interfaces/IPriceFeed.sol";

interface ILiquidator {
    /// @notice Emitted when executor updated
    /// @param account The account to update
    /// @param active Updated status
    event ExecutorUpdated(address account, bool active);

    /// @notice Emitted when a position is closed by the liquidator
    /// @param pool The pool in which the position is closed
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param liquidationExecutionFee The liquidation execution fee paid to the liquidator
    event PositionClosedByLiquidator(
        IPool indexed pool,
        address indexed account,
        Side side,
        uint64 liquidationExecutionFee
    );

    /// @notice Update price feed contract through `IPoolFactory`
    function updatePriceFeed() external;

    /// @notice Update executor
    /// @param account Account to update
    /// @param active Updated status
    function updateExecutor(address account, bool active) external;

    /// @notice Liquidate a liquidity position
    /// @dev See `IPoolLiquidityPosition#liquidateLiquidityPosition` for more information
    /// @param pool The pool in which to liquidate the position
    /// @param positionID The position ID to liquidate
    /// @param feeReceiver The address to receive the liquidation execution fee
    function liquidateLiquidityPosition(IPool pool, uint96 positionID, address feeReceiver) external;

    /// @notice Liquidate a position
    /// @dev See `IPool#liquidatePosition` for more information
    /// @param pool The pool in which to liquidate the position
    /// @param account The owner of the position
    /// @param side The side of the position (Long or Short)
    /// @param feeReceiver The address to receive the liquidation execution fee
    function liquidatePosition(IPool pool, address account, Side side, address feeReceiver) external;
}
