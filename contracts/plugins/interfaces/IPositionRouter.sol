// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../core/interfaces/IPool.sol";

interface IPositionRouter {
    /// @notice Emitted when min execution fee updated
    /// @param minExecutionFee New min execution fee after the update
    event MinExecutionFeeUpdated(uint256 minExecutionFee);

    /// @notice Emitted when position executor updated
    /// @param account Account to update
    /// @param active Whether active after the update
    event PositionExecutorUpdated(address indexed account, bool active);

    /// @notice Emitted when delay parameter updated
    /// @param minBlockDelayExecutor The new min block delay for executor to execute requests
    /// @param minTimeDelayPublic The new min time delay for public to execute requests
    /// @param maxTimeDelay The new max time delay until request expires
    event DelayValuesUpdated(uint32 minBlockDelayExecutor, uint32 minTimeDelayPublic, uint32 maxTimeDelay);

    /// @notice Emitted when open liquidity position request created
    /// @param account Owner of the request
    /// @param pool The address of the pool to open liquidity position
    /// @param margin Margin of the position
    /// @param liquidity Liquidity of the position
    /// @param executionFee Amount of fee for the executor to carry out the request
    /// @param index Index of the request
    event OpenLiquidityPositionCreated(
        address indexed account,
        IPool indexed pool,
        uint128 margin,
        uint256 liquidity,
        uint256 executionFee,
        uint128 indexed index
    );

    /// @notice Emitted when open liquidity position request cancelled
    /// @param index Index of the cancelled request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event OpenLiquidityPositionCancelled(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when open liquidity position request executed
    /// @param index Index of the order to execute
    /// @param executionFeeReceiver Receiver of the order execution fee
    event OpenLiquidityPositionExecuted(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when close liquidity position request created
    /// @param account Owner of the request
    /// @param pool The address of the pool to close liquidity position
    /// @param positionID ID of the position
    /// @param receiver Address of the margin receiver
    /// @param executionFee  Amount of fee for the executor to carry out the request
    /// @param index Index of the request
    event CloseLiquidityPositionCreated(
        address indexed account,
        IPool indexed pool,
        uint96 positionID,
        address receiver,
        uint256 executionFee,
        uint128 indexed index
    );

    /// @notice Emitted when close liquidity position request cancelled
    /// @param index Index of cancelled request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event CloseLiquidityPositionCancelled(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when close liquidity position request executed
    /// @param index Index of the executed request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event CloseLiquidityPositionExecuted(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when adjust liquidity position margin request created
    /// @param account Owner of the request
    /// @param pool The address of the pool to adjust liquidity position margin
    /// @param positionID ID of the position
    /// @param marginDelta Delta of margin of the adjustment
    /// @param receiver Address of the margin receiver
    /// @param executionFee Amount of fee for the executor to carry out the request
    /// @param index Index of the request
    event AdjustLiquidityPositionMarginCreated(
        address indexed account,
        IPool indexed pool,
        uint96 positionID,
        int128 marginDelta,
        address receiver,
        uint256 executionFee,
        uint128 indexed index
    );

    /// @notice Emitted when adjust liquidity position margin request cancelled
    /// @param index Index of cancelled request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event AdjustLiquidityPositionMarginCancelled(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when adjust liquidity position margin request executed
    /// @param index Index of executed request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event AdjustLiquidityPositionMarginExecuted(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when increase risk buffer fund position request created
    /// @param account Owner of the request
    /// @param pool The address of the pool to increase risk buffer fund position
    /// @param liquidityDelta The increase in liquidity
    /// @param executionFee Amount of fee for the executor to carry out the request
    /// @param index Index of the request
    event IncreaseRiskBufferFundPositionCreated(
        address indexed account,
        IPool indexed pool,
        uint128 liquidityDelta,
        uint256 executionFee,
        uint128 indexed index
    );

    /// @notice Emitted when increase risk buffer fund position request cancelled
    /// @param index Index of the cancelled request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event IncreaseRiskBufferFundPositionCancelled(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when increase risk buffer fund position request executed
    /// @param index Index of the executed request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event IncreaseRiskBufferFundPositionExecuted(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when decrease risk buffer fund position request created
    /// @param account Owner of the request
    /// @param pool The address of the pool to decrease risk buffer fund position
    /// @param liquidityDelta The decrease in liquidity
    /// @param receiver Address of the margin receiver
    /// @param executionFee Amount of fee for the executor to carry out the request
    /// @param index Index of the request
    event DecreaseRiskBufferFundPositionCreated(
        address indexed account,
        IPool indexed pool,
        uint128 liquidityDelta,
        address receiver,
        uint256 executionFee,
        uint128 indexed index
    );

    /// @notice Emitted when decrease risk buffer fund position request cancelled
    /// @param index Index of the cancelled request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event DecreaseRiskBufferFundPositionCancelled(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when decrease risk buffer fund position request executed
    /// @param index Index of the executed request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event DecreaseRiskBufferFundPositionExecuted(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when open or increase an existing position size request created
    /// @param account Owner of the request
    /// @param pool The address of the pool to increase position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The increase in position margin
    /// @param sizeDelta The increase in position size
    /// @param acceptableTradePriceX96 The worst trade price of the request
    /// @param executionFee Amount of fee for the executor to carry out the request
    /// @param index Index of the request
    event IncreasePositionCreated(
        address indexed account,
        IPool indexed pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 acceptableTradePriceX96,
        uint256 executionFee,
        uint128 indexed index
    );

    /// @notice Emitted when increase position request cancelled
    /// @param index Index of the cancelled request
    /// @param executionFeeReceiver Receiver of the cancelled request execution fee
    event IncreasePositionCancelled(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when increase position request executed
    /// @param index Index of the executed request
    /// @param executionFeeReceiver Receiver of the executed request execution fee
    event IncreasePositionExecuted(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when close or decrease existing position size request created
    /// @param account Owner of the request
    /// @param pool The address of the pool to decrease position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The decrease in position margin
    /// @param sizeDelta The decrease in position size
    /// @param acceptableTradePriceX96 The worst trade price of the request
    /// @param receiver Address of the margin receiver
    /// @param executionFee Amount of fee for the executor to carry out the order
    /// @param index Index of the request
    event DecreasePositionCreated(
        address indexed account,
        IPool indexed pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 acceptableTradePriceX96,
        address receiver,
        uint256 executionFee,
        uint128 indexed index
    );

    /// @notice Emitted when decrease position request cancelled
    /// @param index Index of the cancelled decrease position request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event DecreasePositionCancelled(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Emitted when decrease position request executed
    /// @param index Index of the executed decrease position request
    /// @param executionFeeReceiver Receiver of the request execution fee
    event DecreasePositionExecuted(uint128 indexed index, address payable executionFeeReceiver);

    /// @notice Execution fee is insufficient
    /// @param available The available execution fee amount
    /// @param required The required minimum execution fee amount
    error InsufficientExecutionFee(uint256 available, uint256 required);

    /// @notice Request expired
    /// @param expiredAt When the request is expired
    error Expired(uint256 expiredAt);

    /// @notice Too early to execute request
    /// @param earliest The earliest time to execute the request
    error TooEarly(uint256 earliest);

    /// @notice Trade price exceeds limit
    error InvalidTradePrice(uint160 tradePriceX96, uint160 acceptableTradePriceX96);

    struct OpenLiquidityPositionRequest {
        address account;
        uint96 blockNumber;
        IPool pool;
        uint64 blockTime;
        uint128 margin;
        uint128 liquidity;
        uint256 executionFee;
    }

    struct CloseLiquidityPositionRequest {
        address account;
        uint96 positionID;
        IPool pool;
        uint96 blockNumber;
        uint256 executionFee;
        address receiver;
        uint64 blockTime;
    }

    struct AdjustLiquidityPositionMarginRequest {
        address account;
        uint96 positionID;
        IPool pool;
        uint96 blockNumber;
        int128 marginDelta;
        uint64 blockTime;
        address receiver;
        uint256 executionFee;
    }

    struct IncreaseRiskBufferFundPositionRequest {
        address account;
        uint96 blockNumber;
        IPool pool;
        uint64 blockTime;
        uint128 liquidityDelta;
        uint256 executionFee;
    }

    struct DecreaseRiskBufferFundPositionRequest {
        address account;
        uint96 blockNumber;
        IPool pool;
        uint64 blockTime;
        uint128 liquidityDelta;
        address receiver;
        uint256 executionFee;
    }

    struct IncreasePositionRequest {
        address account;
        uint96 blockNumber;
        IPool pool;
        uint128 marginDelta;
        uint128 sizeDelta;
        uint160 acceptableTradePriceX96;
        uint64 blockTime;
        Side side;
        uint256 executionFee;
    }

    struct DecreasePositionRequest {
        address account;
        uint96 blockNumber;
        IPool pool;
        uint128 marginDelta;
        uint128 sizeDelta;
        uint160 acceptableTradePriceX96;
        uint64 blockTime;
        Side side;
        address receiver;
        uint256 executionFee;
    }

    /// @notice Update position executor
    /// @param account Account to update
    /// @param active Updated status
    function updatePositionExecutor(address account, bool active) external;

    /// @notice Update delay parameters
    /// @param minBlockDelayExecutor New min block delay for executor to execute requests
    /// @param minTimeDelayPublic New min time delay for public to execute requests
    /// @param maxTimeDelay New max time delay until request expires
    function updateDelayValues(uint32 minBlockDelayExecutor, uint32 minTimeDelayPublic, uint32 maxTimeDelay) external;

    /// @notice Update minimum execution fee
    /// @param minExecutionFee New min execution fee
    function updateMinExecutionFee(uint256 minExecutionFee) external;

    /// @notice Update the gas limit for executing requests
    /// @param executionGasLimit New execution gas limit
    function updateExecutionGasLimit(uint160 executionGasLimit) external;

    /// @notice Create open liquidity position request
    /// @param pool The address of the pool to open liquidity position
    /// @param margin Margin of the position
    /// @param liquidity Liquidity of the position
    /// @return index Index of the request
    function createOpenLiquidityPosition(
        IPool pool,
        uint128 margin,
        uint128 liquidity
    ) external payable returns (uint128 index);

    /// @notice Cancel open liquidity position request
    /// @param index Index of the request to cancel
    /// @param executionFeeReceiver Receiver of request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelOpenLiquidityPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute open liquidity position request
    /// @param index Index of request to execute
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeOpenLiquidityPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Execute multiple liquidity position requests
    /// @param endIndex The maximum request index to execute, excluded
    /// @param executionFeeReceiver Receiver of the request execution fees
    function executeOpenLiquidityPositions(uint128 endIndex, address payable executionFeeReceiver) external;

    /// @notice Create close liquidity position request
    /// @param pool The address of the pool to close liquidity position
    /// @param positionID ID of the position
    /// @param receiver Address of the margin receiver
    /// @return index The request index
    function createCloseLiquidityPosition(
        IPool pool,
        uint96 positionID,
        address receiver
    ) external payable returns (uint128 index);

    /// @notice Cancel close liquidity position request
    /// @param index Index of the request to cancel
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelCloseLiquidityPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute close liquidity position request
    /// @param index Index of the request to execute
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeCloseLiquidityPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Execute multiple close liquidity position requests
    /// @param endIndex The maximum request index to execute, excluded
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeCloseLiquidityPositions(uint128 endIndex, address payable executionFeeReceiver) external;

    /// @notice Create adjust liquidity position margin request
    /// @param pool The address of the pool to adjust liquidity position margin
    /// @param positionID ID of the position
    /// @param marginDelta Delta of margin of the adjustment
    /// @param receiver Address of the margin receiver
    /// @return index Index of the request
    function createAdjustLiquidityPositionMargin(
        IPool pool,
        uint96 positionID,
        int128 marginDelta,
        address receiver
    ) external payable returns (uint128 index);

    /// @notice Cancel adjust liquidity position margin request
    /// @param index Index of the request to cancel
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelAdjustLiquidityPositionMargin(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute adjust liquidity position margin request
    /// @param index Index of the request to execute
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeAdjustLiquidityPositionMargin(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Execute multiple adjust liquidity position margin requests
    /// @param endIndex The maximum request index to execute, excluded
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeAdjustLiquidityPositionMargins(uint128 endIndex, address payable executionFeeReceiver) external;

    /// @notice Create increase risk buffer fund position request
    /// @param pool The address of the pool to increase risk buffer fund position
    /// @param liquidityDelta The increase in liquidity
    /// @return index Index of the request
    function createIncreaseRiskBufferFundPosition(
        IPool pool,
        uint128 liquidityDelta
    ) external payable returns (uint128 index);

    /// @notice Cancel increase risk buffer fund position request
    /// @param index Index of the request to cancel
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelIncreaseRiskBufferFundPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute increase risk buffer fund position request
    /// @param index Index of the request to execute
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeIncreaseRiskBufferFundPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Execute multiple increase risk buffer fund position requests
    /// @param endIndex The maximum request index to execute, excluded
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeIncreaseRiskBufferFundPositions(uint128 endIndex, address payable executionFeeReceiver) external;

    /// @notice Create decrease risk buffer fund position request
    /// @param pool The address of the pool to decrease risk buffer fund position
    /// @param liquidityDelta The decrease in liquidity
    /// @param receiver Address of the margin receiver
    /// @return index Index of the request
    function createDecreaseRiskBufferFundPosition(
        IPool pool,
        uint128 liquidityDelta,
        address receiver
    ) external payable returns (uint128 index);

    /// @notice Cancel decrease risk buffer fund position request
    /// @param index Index of the request to cancel
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelDecreaseRiskBufferFundPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute decrease risk buffer fund position request
    /// @param index Index of the request to execute
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeDecreaseRiskBufferFundPosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Execute multiple decrease risk buffer fund position requests
    /// @param endIndex The maximum request index to execute, excluded
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeDecreaseRiskBufferFundPositions(uint128 endIndex, address payable executionFeeReceiver) external;

    /// @notice Create open or increase the size of existing position request
    /// @param pool The address of the pool to increase position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The increase in position margin
    /// @param sizeDelta The increase in position size
    /// @param acceptableTradePriceX96 The worst trade price of the request, as a Q64.96
    /// @return index Index of the request
    function createIncreasePosition(
        IPool pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 acceptableTradePriceX96
    ) external payable returns (uint128 index);

    /// @notice Cancel increase position request
    /// @param index Index of the request to cancel
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelIncreasePosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute increase position request
    /// @param index Index of the request to execute
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeIncreasePosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Execute multiple increase position requests
    /// @param endIndex The maximum request index to execute, excluded
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeIncreasePositions(uint128 endIndex, address payable executionFeeReceiver) external;

    /// @notice Create decrease position request
    /// @param pool The address of the pool to decrease position
    /// @param side The side of the position (Long or Short)
    /// @param marginDelta The decrease in position margin
    /// @param sizeDelta The decrease in position size
    /// @param acceptableTradePriceX96 The worst trade price of the request, as a Q64.96
    /// @param receiver Margin recipient address
    /// @return index The request index
    function createDecreasePosition(
        IPool pool,
        Side side,
        uint128 marginDelta,
        uint128 sizeDelta,
        uint160 acceptableTradePriceX96,
        address receiver
    ) external payable returns (uint128 index);

    /// @notice Cancel decrease position request
    /// @param index Index of the request to cancel
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return cancelled True if the cancellation succeeds or request not exists
    function cancelDecreasePosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool cancelled);

    /// @notice Execute decrease position request
    /// @param index Index of the request to execute
    /// @param executionFeeReceiver Receiver of the request execution fee
    /// @return executed True if the execution succeeds or request not exists
    function executeDecreasePosition(
        uint128 index,
        address payable executionFeeReceiver
    ) external returns (bool executed);

    /// @notice Execute multiple decrease position requests
    /// @param endIndex The maximum request index to execute, excluded
    /// @param executionFeeReceiver Receiver of the request execution fee
    function executeDecreasePositions(uint128 endIndex, address payable executionFeeReceiver) external;
}
