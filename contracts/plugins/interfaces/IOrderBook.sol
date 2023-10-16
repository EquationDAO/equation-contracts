// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../core/interfaces/IPool.sol";

interface IOrderBook {
    /// @notice Emitted when min execution fee updated
    /// @param minExecutionFee The new min execution fee after the update
    event MinExecutionFeeUpdated(uint256 minExecutionFee);

    /// @notice Emitted when order executor updated
    /// @param account The account to update
    /// @param active Updated status
    event OrderExecutorUpdated(address indexed account, bool active);

    /// @notice Emitted when increase order created
    /// @param account Owner of the increase order
    /// @param pool The address of the pool to increase position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The increase in margin
    /// @param sizeDelta The increase in size
    /// @param triggerMarketPriceX96 Market price to trigger the order, as a Q64.96
    /// @param triggerAbove Execute the order when current price is greater than or
    /// equal to trigger price if `true` and vice versa
    /// @param acceptableTradePriceX96 Acceptable worst trade price of the order, as a Q64.96
    /// @param executionFee Amount of fee for the executor to carry out the order
    /// @param orderIndex Index of the order
    event IncreaseOrderCreated(
        address indexed account,
        IPool indexed pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 triggerMarketPriceX96,
        bool triggerAbove,
        uint160 acceptableTradePriceX96,
        uint256 executionFee,
        uint256 indexed orderIndex
    );

    /// @notice Emitted when increase order updated
    /// @param orderIndex Index of the updated order
    /// @param triggerMarketPriceX96 The new market price to trigger the order, as a Q64.96
    /// @param acceptableTradePriceX96 The new acceptable worst trade price of the order, as a Q64.96
    event IncreaseOrderUpdated(
        uint256 indexed orderIndex,
        uint160 triggerMarketPriceX96,
        uint160 acceptableTradePriceX96
    );

    /// @notice Emitted when increase order cancelled
    /// @param orderIndex Index of the cancelled order
    /// @param feeReceiver Receiver of the order execution fee
    event IncreaseOrderCancelled(uint256 indexed orderIndex, address payable feeReceiver);

    /// @notice Emitted when order executed
    /// @param orderIndex Index of the executed order
    /// @param marketPriceX96 Actual execution price, as a Q64.96
    /// @param feeReceiver Receiver of the order execution fee
    event IncreaseOrderExecuted(uint256 indexed orderIndex, uint160 marketPriceX96, address payable feeReceiver);

    /// @notice Emitted when decrease order created
    /// @param account Owner of the decrease order
    /// @param pool The address of the pool to decrease position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The decrease in margin
    /// @param sizeDelta The decrease in size
    /// Note if zero, we treat it as a close position request, which will close the position,
    /// ignoring the `marginDelta` and `acceptableTradePriceX96`
    /// @param triggerMarketPriceX96 Market price to trigger the order, as a Q64.96
    /// @param triggerAbove Execute the order when current price is greater than or
    /// equal to trigger price if `true` and vice versa
    /// @param acceptableTradePriceX96 Acceptable worst trade price of the order, as a Q64.96
    /// @param receiver Margin recipient address
    /// @param executionFee Amount of fee for the executor to carry out the order
    /// @param orderIndex Index of the order
    event DecreaseOrderCreated(
        address indexed account,
        IPool indexed pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 triggerMarketPriceX96,
        bool triggerAbove,
        uint160 acceptableTradePriceX96,
        address receiver,
        uint256 executionFee,
        uint256 indexed orderIndex
    );

    /// @notice Emitted when decrease order updated
    /// @param orderIndex Index of the decrease order
    /// @param triggerMarketPriceX96 The new market price to trigger the order, as a Q64.96
    /// @param acceptableTradePriceX96 The new acceptable worst trade price of the order, as a Q64.96
    event DecreaseOrderUpdated(
        uint256 indexed orderIndex,
        uint160 triggerMarketPriceX96,
        uint160 acceptableTradePriceX96
    );

    /// @notice Emitted when decrease order cancelled
    /// @param orderIndex Index of the cancelled order
    /// @param feeReceiver Receiver of the order execution fee
    event DecreaseOrderCancelled(uint256 indexed orderIndex, address feeReceiver);

    /// @notice Emitted when decrease order executed
    /// @param orderIndex Index of the executed order
    /// @param marketPriceX96 The market price when execution, as a Q64.96
    /// @param feeReceiver Receiver of the order execution fee
    event DecreaseOrderExecuted(uint256 indexed orderIndex, uint160 marketPriceX96, address payable feeReceiver);

    /// @notice Execution fee is insufficient
    /// @param available The available execution fee amount
    /// @param required The required minimum execution fee amount
    error InsufficientExecutionFee(uint256 available, uint256 required);

    /// @notice Order not exists
    /// @param orderIndex The order index
    error OrderNotExists(uint256 orderIndex);

    /// @notice Current market price is invalid to trigger the order
    /// @param marketPriceX96 The current market price, as a Q64.96
    /// @param triggerMarketPriceX96 The trigger market price, as a Q64.96
    error InvalidMarketPriceToTrigger(uint160 marketPriceX96, uint160 triggerMarketPriceX96);

    /// @notice Trade price exceeds limit
    /// @param tradePriceX96 The trade price, as a Q64.96
    /// @param acceptableTradePriceX96 The acceptable trade price, as a Q64.96
    error InvalidTradePrice(uint160 tradePriceX96, uint160 acceptableTradePriceX96);

    struct IncreaseOrder {
        address account;
        IPool pool;
        Side side;
        uint128 marginDelta;
        uint128 sizeDelta;
        uint160 triggerMarketPriceX96;
        bool triggerAbove;
        uint160 acceptableTradePriceX96;
        uint256 executionFee;
    }

    struct DecreaseOrder {
        address account;
        IPool pool;
        Side side;
        uint128 marginDelta;
        uint128 sizeDelta;
        uint160 triggerMarketPriceX96;
        bool triggerAbove;
        uint160 acceptableTradePriceX96;
        address receiver;
        uint256 executionFee;
    }

    /// @notice Update minimum execution fee
    /// @param minExecutionFee New min execution fee
    function updateMinExecutionFee(uint256 minExecutionFee) external;

    /// @notice Update order executor
    /// @param account Account to update
    /// @param active Updated status
    function updateOrderExecutor(address account, bool active) external;

    /// @notice Update the gas limit for executing requests
    /// @param executionGasLimit New execution gas limit
    function updateExecutionGasLimit(uint256 executionGasLimit) external;

    /// @notice Create an order to open or increase the size of an existing position
    /// @param pool The pool address of position to create increase order
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The increase in margin
    /// @param sizeDelta The increase in size
    /// @param triggerMarketPriceX96 Market price to trigger the order, as a Q64.96
    /// @param triggerAbove Execute the order when current price is greater than or
    /// equal to trigger price if `true` and vice versa
    /// @param acceptableTradePriceX96 Acceptable worst trade price of the order, as a Q64.96
    /// @return orderIndex Index of the order
    function createIncreaseOrder(
        IPool pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 triggerMarketPriceX96,
        bool triggerAbove,
        uint160 acceptableTradePriceX96
    ) external payable returns (uint256 orderIndex);

    /// @notice Update an existing increase order
    /// @param orderIndex The index of order to update
    /// @param triggerMarketPriceX96 The new market price to trigger the order, as a Q64.96
    /// @param acceptableTradePriceX96 The new acceptable worst trade price of the order, as a Q64.96
    function updateIncreaseOrder(
        uint256 orderIndex,
        uint160 triggerMarketPriceX96,
        uint160 acceptableTradePriceX96
    ) external;

    /// @notice Cancel an existing increase order
    /// @param orderIndex The index of order to cancel
    /// @param feeReceiver Receiver of the order execution fee
    function cancelIncreaseOrder(uint256 orderIndex, address payable feeReceiver) external;

    /// @notice Execute an existing increase order
    /// @param orderIndex The index of order to execute
    /// @param feeReceiver Receiver of the order execution fee
    function executeIncreaseOrder(uint256 orderIndex, address payable feeReceiver) external;

    /// @notice Create an order to close or decrease the size of an existing position
    /// @param pool The address of the pool to create decrease order
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The decrease in margin
    /// @param sizeDelta The decrease in size
    /// Note if zero, we treat it as a close position request, which will close the position,
    /// ignoring the `marginDelta` and `acceptableTradePriceX96`
    /// @param triggerMarketPriceX96 Market price to trigger the order, as a Q64.96
    /// @param triggerAbove Execute the order when current price is greater than or
    /// equal to trigger price if `true` and vice versa
    /// @param acceptableTradePriceX96 Acceptable worst trade price of the order, as a Q64.96
    /// @param receiver Margin recipient address
    /// @return orderIndex Index of the order
    function createDecreaseOrder(
        IPool pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 triggerMarketPriceX96,
        bool triggerAbove,
        uint160 acceptableTradePriceX96,
        address receiver
    ) external payable returns (uint256 orderIndex);

    /// @notice Update an existing decrease order
    /// @param orderIndex The index of order to update
    /// @param triggerMarketPriceX96 The new market price to trigger the order, as a Q64.96
    /// @param acceptableTradePriceX96 The new acceptable worst trade price of the order, as a Q64.96
    function updateDecreaseOrder(
        uint256 orderIndex,
        uint160 triggerMarketPriceX96,
        uint160 acceptableTradePriceX96
    ) external;

    /// @notice Cancel an existing decrease order
    /// @param orderIndex The index of order to cancel
    /// @param feeReceiver Receiver of the order execution fee
    function cancelDecreaseOrder(uint256 orderIndex, address payable feeReceiver) external;

    /// @notice Execute an existing decrease order
    /// @param orderIndex The index of order to execute
    /// @param feeReceiver Receiver of the order execution fee
    function executeDecreaseOrder(uint256 orderIndex, address payable feeReceiver) external;

    /// @notice Create take-profit and stop-loss orders in a single call
    /// @param pool The pool address of position to create orders
    /// @param side The side of the position (Long or Short)
    /// @param marginDeltas The decreases in margin
    /// @param sizeDeltas The decreases in size
    /// @param triggerMarketPriceX96s Market prices to trigger the order, as Q64.96s
    /// @param acceptableTradePriceX96s Acceptable worst trade prices of the orders, as Q64.96s
    /// @param receiver Margin recipient address
    function createTakeProfitAndStopLossOrders(
        IPool pool,
        Side side,
        uint128[2] calldata marginDeltas,
        uint128[2] calldata sizeDeltas,
        uint160[2] calldata triggerMarketPriceX96s,
        uint160[2] calldata acceptableTradePriceX96s,
        address receiver
    ) external payable;
}
