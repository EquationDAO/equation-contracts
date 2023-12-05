// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../governance/Governable.sol";
import "../core/PoolIndexer.sol";
import "../types/PackedValue.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../plugins/interfaces/IOrderBook.sol";
import "../plugins/interfaces/ILiquidator.sol";
import "../plugins/interfaces/IPositionRouter.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

/// @notice MixedExecutorV2 is a contract that executes multiple calls in a single transaction
/// @custom:since v0.0.4
contract MixedExecutorV2 is Multicall, Governable {
    /// @notice The address of pool indexer
    PoolIndexer public immutable poolIndexer;
    /// @notice The address of liquidator
    ILiquidator public immutable liquidator;
    /// @notice The address of position router
    IPositionRouter public immutable positionRouter;
    /// @notice The address of price feed
    IPriceFeed public immutable priceFeed;
    /// @notice The address of order book
    IOrderBook public immutable orderBook;

    /// @notice The executors
    mapping(address => bool) public executors;
    /// @notice Default receiving address of fee
    address payable public feeReceiver;
    /// @notice Indicates whether to cancel the order when an execution error occurs
    bool public cancelOrderIfFailedStatus = true;

    /// @notice Emitted when an executor is updated
    /// @param executor The address of executor to update
    /// @param active Updated status
    event ExecutorUpdated(address indexed executor, bool indexed active);

    /// @notice Emitted when the increase order execute failed
    /// @dev The event is only emitted when the execution error is caused
    /// by the `IOrderBook.InvalidMarketPriceToTrigger`
    /// @param orderIndex The index of order to execute
    event IncreaseOrderExecuteFailed(uint256 indexed orderIndex);
    /// @notice Emitted when the increase order cancel succeeded
    /// @dev The event is emitted when the cancel order is successful after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason The shortened reason of the execution error
    event IncreaseOrderCancelSucceeded(uint256 indexed orderIndex, bytes4 shortenedReason);
    /// @notice Emitted when the increase order cancel failed
    /// @dev The event is emitted when the cancel order is failed after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason1 The shortened reason of the execution error
    /// @param shortenedReason2 The shortened reason of the cancel error
    event IncreaseOrderCancelFailed(uint256 indexed orderIndex, bytes4 shortenedReason1, bytes4 shortenedReason2);

    /// @notice Emitted when the decrease order execute failed
    /// @dev The event is only emitted when the execution error is caused
    /// by the `IOrderBook.InvalidMarketPriceToTrigger`
    /// @param orderIndex The index of order to execute
    event DecreaseOrderExecuteFailed(uint256 indexed orderIndex);
    /// @notice Emitted when the decrease order cancel succeeded
    /// @dev The event is emitted when the cancel order is successful after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason The shortened reason of the execution error
    event DecreaseOrderCancelSucceeded(uint256 indexed orderIndex, bytes4 shortenedReason);
    /// @notice Emitted when the decrease order cancel failed
    /// @dev The event is emitted when the cancel order is failed after the execution error
    /// @param orderIndex The index of order to cancel
    /// @param shortenedReason1 The shortened reason of the execution error
    /// @param shortenedReason2 The shortened reason of the cancel error
    event DecreaseOrderCancelFailed(uint256 indexed orderIndex, bytes4 shortenedReason1, bytes4 shortenedReason2);

    /// @notice Emitted when the liquidity position liquidate failed
    /// @dev The event is emitted when the liquidate is failed after the execution error
    /// @param pool The address of pool
    /// @param positionID The id of position to liquidate
    /// @param shortenedReason The shortened reason of the execution error
    event LiquidateLiquidityPositionFailed(IPool indexed pool, uint96 indexed positionID, bytes4 shortenedReason);
    /// @notice Emitted when the position liquidate failed
    /// @dev The event is emitted when the liquidate is failed after the execution error
    /// @param pool The address of pool
    /// @param account The address of account
    /// @param side The side of position to liquidate
    /// @param shortenedReason The shortened reason of the execution error
    event LiquidatePositionFailed(
        IPool indexed pool,
        address indexed account,
        Side indexed side,
        bytes4 shortenedReason
    );

    /// @notice Error thrown when the execution error and `requireSuccess` is set to true
    error ExecutionFailed(bytes reason);

    modifier onlyExecutor() {
        if (!executors[msg.sender]) revert Forbidden();
        _;
    }

    constructor(
        PoolIndexer _poolIndexer,
        ILiquidator _liquidator,
        IPositionRouter _positionRouter,
        IPriceFeed _priceFeed,
        IOrderBook _orderBook
    ) {
        poolIndexer = _poolIndexer;
        liquidator = _liquidator;
        positionRouter = _positionRouter;
        priceFeed = _priceFeed;
        orderBook = _orderBook;
    }

    /// @notice Set executor status active or not
    /// @param _executor Executor address
    /// @param _active Status of executor permission to set
    function setExecutor(address _executor, bool _active) external virtual onlyGov {
        executors[_executor] = _active;
        emit ExecutorUpdated(_executor, _active);
    }

    /// @notice Set fee receiver
    /// @param _receiver The address of new fee receiver
    function setFeeReceiver(address payable _receiver) external virtual onlyGov {
        feeReceiver = _receiver;
    }

    /// @notice Set whether to cancel the order when an execution error occurs
    /// @param _cancelOrderIfFailedStatus If the _cancelOrderIfFailedStatus is set to 1, the order is canceled
    /// when an error occurs
    function setCancelOrderIfFailedStatus(bool _cancelOrderIfFailedStatus) external virtual onlyGov {
        cancelOrderIfFailedStatus = _cancelOrderIfFailedStatus;
    }

    /// @notice Update prices
    /// @param _packedValues The packed values of the token index and priceX96: bit 0-23 represent the token, and
    /// bit 24-183 represent the priceX96
    /// @param _timestamp The timestamp of the price update
    function setPriceX96s(PackedValue[] calldata _packedValues, uint64 _timestamp) external virtual onlyExecutor {
        IPriceFeed.TokenPrice[] memory tokenPrices = new IPriceFeed.TokenPrice[](_packedValues.length);
        for (uint256 i; i < _packedValues.length; ) {
            tokenPrices[i] = IPriceFeed.TokenPrice({
                token: poolIndexer.indexToken(_packedValues[i].unpackUint24(0)),
                priceX96: _packedValues[i].unpackUint160(24)
            });

            // prettier-ignore
            unchecked { ++i; }
        }

        priceFeed.setPriceX96s(tokenPrices, _timestamp);
    }

    /// @notice Execute multiple liquidity position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeOpenLiquidityPositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeOpenLiquidityPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple close liquidity position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeCloseLiquidityPositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeCloseLiquidityPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple adjust liquidity position margin requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeAdjustLiquidityPositionMargins(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeAdjustLiquidityPositionMargins(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple increase risk buffer fund positions
    /// @param _endIndex The maximum request index to execute, excluded
    function executeIncreaseRiskBufferFundPositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeIncreaseRiskBufferFundPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple decrease risk buffer fund positions
    /// @param _endIndex The maximum request index to execute, excluded
    function executeDecreaseRiskBufferFundPositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeDecreaseRiskBufferFundPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple increase position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeIncreasePositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeIncreasePositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple decrease position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeDecreasePositions(uint128 _endIndex) external virtual onlyExecutor {
        positionRouter.executeDecreasePositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Sample and adjust funding rate batch
    /// @param _packedValue The packed values of the pool index and packed pools count. The maximum packed pools
    /// count is 10: bit 0-23 represent the pool index 1, bit 24-47 represent the pool index 2, and so on, and bit
    /// 240-247 represent the packed pools count
    function sampleAndAdjustFundingRateBatch(PackedValue _packedValue) external virtual onlyExecutor {
        uint8 packedPoolsCount = _packedValue.unpackUint8(240);
        require(packedPoolsCount <= 10);
        for (uint8 i; i < packedPoolsCount; ) {
            unchecked {
                poolIndexer.indexPools(_packedValue.unpackUint24(i * 24)).sampleAndAdjustFundingRate();
                ++i;
            }
        }
    }

    /// @notice Collect protocol fee batch
    /// @param _packedValue The packed values of the pool index and packed pools count. The maximum packed pools
    /// count is 10: bit 0-23 represent the pool index 1, bit 24-47 represent the pool index 2, and so on, and bit
    /// 240-247 represent the packed pools count
    function collectProtocolFeeBatch(PackedValue _packedValue) external virtual onlyExecutor {
        uint8 packedPoolsCount = _packedValue.unpackUint8(240);
        require(packedPoolsCount <= 10);
        for (uint8 i; i < packedPoolsCount; ) {
            unchecked {
                poolIndexer.indexPools(_packedValue.unpackUint24(i * 24)).collectProtocolFee();
                ++i;
            }
        }
    }

    /// @notice Execute an existing increase order
    /// @param _packedValue The packed values of the order index and require success flag: bit 0-247 represent
    /// the order index, and bit 248 represent the require success flag
    function executeIncreaseOrder(PackedValue _packedValue) external virtual onlyExecutor {
        address payable receiver = _getFeeReceiver();
        uint248 orderIndex = _packedValue.unpackUint248(0);
        bool requireSuccess = _packedValue.unpackBool(248);

        try orderBook.executeIncreaseOrder(orderIndex, receiver) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);

            // If the order cannot be triggered due to changes in the market price,
            // it is unnecessary to cancel the order
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            if (errorTypeSelector == IOrderBook.InvalidMarketPriceToTrigger.selector) {
                emit IncreaseOrderExecuteFailed(orderIndex);
                return;
            }

            if (cancelOrderIfFailedStatus) {
                try orderBook.cancelIncreaseOrder(orderIndex, receiver) {
                    emit IncreaseOrderCancelSucceeded(orderIndex, errorTypeSelector);
                } catch (bytes memory reason2) {
                    emit IncreaseOrderCancelFailed(orderIndex, errorTypeSelector, _decodeShortenedReason(reason2));
                }
            }
        }
    }

    /// @notice Execute an existing decrease order
    /// @param _packedValue The packed values of the order index and require success flag: bit 0-247 represent
    /// the order index, and bit 248 represent the require success flag
    function executeDecreaseOrder(PackedValue _packedValue) external virtual onlyExecutor {
        address payable receiver = _getFeeReceiver();
        uint248 orderIndex = _packedValue.unpackUint248(0);
        bool requireSuccess = _packedValue.unpackBool(248);

        try orderBook.executeDecreaseOrder(orderIndex, receiver) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);

            // If the order cannot be triggered due to changes in the market price,
            // it is unnecessary to cancel the order
            bytes4 errorTypeSelector = _decodeShortenedReason(reason);
            if (errorTypeSelector == IOrderBook.InvalidMarketPriceToTrigger.selector) {
                emit DecreaseOrderExecuteFailed(orderIndex);
                return;
            }

            if (cancelOrderIfFailedStatus) {
                try orderBook.cancelDecreaseOrder(orderIndex, receiver) {
                    emit DecreaseOrderCancelSucceeded(orderIndex, errorTypeSelector);
                } catch (bytes memory reason2) {
                    emit DecreaseOrderCancelFailed(orderIndex, errorTypeSelector, _decodeShortenedReason(reason2));
                }
            }
        }
    }

    /// @notice Liquidate a liquidity position
    /// @param _packedValue The packed values of the pool index, position id, and require success flag:
    /// bit 0-23 represent the pool index, bit 24-119 represent the position ID, and bit 120 represent the
    /// require success flag
    function liquidateLiquidityPosition(PackedValue _packedValue) external virtual onlyExecutor {
        IPool pool = poolIndexer.indexPools(_packedValue.unpackUint24(0));
        uint96 positionID = _packedValue.unpackUint96(24);
        bool requireSuccess = _packedValue.unpackBool(120);

        try liquidator.liquidateLiquidityPosition(pool, positionID, _getFeeReceiver()) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);

            emit LiquidateLiquidityPositionFailed(pool, positionID, _decodeShortenedReason(reason));
        }
    }

    /// @notice Liquidate a position
    /// @param _packedValue The packed values of the pool index, account, side, and require success flag:
    /// bit 0-23 represent the pool index, bit 24-183 represent the account, bit 184-191 represent the side,
    /// and bit 192 represent the require success flag
    function liquidatePosition(PackedValue _packedValue) external virtual onlyExecutor {
        IPool pool = poolIndexer.indexPools(_packedValue.unpackUint24(0));
        address account = _packedValue.unpackAddress(24);
        Side side = Side.wrap(_packedValue.unpackUint8(184));
        bool requireSuccess = _packedValue.unpackBool(192);

        try liquidator.liquidatePosition(pool, account, side, _getFeeReceiver()) {} catch (bytes memory reason) {
            if (requireSuccess) revert ExecutionFailed(reason);

            emit LiquidatePositionFailed(pool, account, side, _decodeShortenedReason(reason));
        }
    }

    /// @notice Decode the shortened reason of the execution error
    /// @dev The default implementation is to return the first 4 bytes of the reason, which is typically the
    /// selector for the error type
    /// @param _reason The reason of the execution error
    /// @return The shortened reason of the execution error
    function _decodeShortenedReason(bytes memory _reason) internal pure virtual returns (bytes4) {
        return bytes4(_reason);
    }

    function _getFeeReceiver() internal view virtual returns (address payable) {
        return feeReceiver == address(0) ? payable(msg.sender) : feeReceiver;
    }
}
