// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./Router.sol";
import "./interfaces/IOrderBook.sol";
import "../libraries/ReentrancyGuard.sol";

contract OrderBook is IOrderBook, Governable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    IERC20 public immutable usd;
    Router public immutable router;

    uint256 public minExecutionFee;
    uint256 public executionGasLimit = 1_000_000 wei;
    mapping(address => bool) public orderExecutors;

    uint256 public increaseOrdersIndexNext;
    uint256 public decreaseOrdersIndexNext;
    mapping(uint256 => IncreaseOrder) public increaseOrders;
    mapping(uint256 => DecreaseOrder) public decreaseOrders;

    modifier onlyOrderExecutor() {
        if (!orderExecutors[msg.sender]) revert Forbidden();
        _;
    }

    constructor(IERC20 _usd, Router _router, uint256 _minExecutionFee) {
        usd = _usd;
        router = _router;
        minExecutionFee = _minExecutionFee;
        emit MinExecutionFeeUpdated(_minExecutionFee);
    }

    /// @inheritdoc IOrderBook
    function updateMinExecutionFee(uint256 _minExecutionFee) external override onlyGov {
        minExecutionFee = _minExecutionFee;
        emit MinExecutionFeeUpdated(_minExecutionFee);
    }

    /// @inheritdoc IOrderBook
    function updateOrderExecutor(address _account, bool _active) external override onlyGov {
        orderExecutors[_account] = _active;
        emit OrderExecutorUpdated(_account, _active);
    }

    /// @inheritdoc IOrderBook
    function updateExecutionGasLimit(uint256 _executionGasLimit) external override onlyGov {
        executionGasLimit = _executionGasLimit;
    }

    /// @inheritdoc IOrderBook
    function createIncreaseOrder(
        IPool _pool,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta,
        uint160 _triggerMarketPriceX96,
        bool _triggerAbove,
        uint160 _acceptableTradePriceX96
    ) external payable override nonReentrant returns (uint256 index) {
        _side.requireValid();
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);
        if (_marginDelta > 0) router.pluginTransfer(usd, msg.sender, address(this), _marginDelta);

        index = increaseOrdersIndexNext++;
        increaseOrders[index] = IncreaseOrder({
            account: msg.sender,
            pool: _pool,
            side: _side,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            triggerMarketPriceX96: _triggerMarketPriceX96,
            triggerAbove: _triggerAbove,
            acceptableTradePriceX96: _acceptableTradePriceX96,
            executionFee: msg.value
        });

        emit IncreaseOrderCreated(
            msg.sender,
            _pool,
            _side,
            _marginDelta,
            _sizeDelta,
            _triggerMarketPriceX96,
            _triggerAbove,
            _acceptableTradePriceX96,
            msg.value,
            index
        );
    }

    /// @inheritdoc IOrderBook
    function updateIncreaseOrder(
        uint256 _orderIndex,
        uint160 _triggerMarketPriceX96,
        uint160 _acceptableTradePriceX96
    ) external override nonReentrant {
        IncreaseOrder storage order = increaseOrders[_orderIndex];
        if (order.account != msg.sender) revert Forbidden();

        order.triggerMarketPriceX96 = _triggerMarketPriceX96;
        order.acceptableTradePriceX96 = _acceptableTradePriceX96;

        emit IncreaseOrderUpdated(_orderIndex, _triggerMarketPriceX96, _acceptableTradePriceX96);
    }

    /// @inheritdoc IOrderBook
    function cancelIncreaseOrder(uint256 _orderIndex, address payable _feeReceiver) external override nonReentrant {
        IncreaseOrder memory order = increaseOrders[_orderIndex];
        if (order.account == address(0)) revert OrderNotExists(_orderIndex);

        if (order.account != msg.sender && !orderExecutors[msg.sender]) revert Forbidden();

        usd.safeTransfer(order.account, order.marginDelta);

        _transferOutETH(order.executionFee, _feeReceiver);

        delete increaseOrders[_orderIndex];

        emit IncreaseOrderCancelled(_orderIndex, _feeReceiver);
    }

    /// @inheritdoc IOrderBook
    function executeIncreaseOrder(
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external override nonReentrant onlyOrderExecutor {
        IncreaseOrder memory order = increaseOrders[_orderIndex];
        if (order.account == address(0)) revert OrderNotExists(_orderIndex);

        uint160 marketPriceX96 = order.pool.marketPriceX96(order.side);
        _validateTriggerMarketPriceX96(order.triggerAbove, marketPriceX96, order.triggerMarketPriceX96);

        usd.safeTransfer(address(order.pool), order.marginDelta);

        // Note that the gas specified here is just an upper limit,
        // when the gas left is lower than this value, code can still be executed
        uint160 tradePriceX96 = router.pluginIncreasePosition{gas: executionGasLimit}(
            order.pool,
            order.account,
            order.side,
            order.marginDelta,
            order.sizeDelta
        );

        _validateTradePriceX96(order.side, tradePriceX96, order.acceptableTradePriceX96);
        _transferOutETH(order.executionFee, _feeReceiver);

        delete increaseOrders[_orderIndex];

        emit IncreaseOrderExecuted(_orderIndex, marketPriceX96, _feeReceiver);
    }

    /// @inheritdoc IOrderBook
    function createDecreaseOrder(
        IPool _pool,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta,
        uint160 _triggerMarketPriceX96,
        bool _triggerAbove,
        uint160 _acceptableTradePriceX96,
        address _receiver
    ) external payable override nonReentrant returns (uint256 index) {
        _side.requireValid();
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);
        index = _createDecreaseOrder(
            msg.sender,
            _pool,
            _side,
            _marginDelta,
            _sizeDelta,
            _triggerMarketPriceX96,
            _triggerAbove,
            _acceptableTradePriceX96,
            _receiver,
            msg.value
        );
    }

    /// @inheritdoc IOrderBook
    function updateDecreaseOrder(
        uint256 _orderIndex,
        uint160 _triggerMarketPriceX96,
        uint160 _acceptableTradePriceX96
    ) external override nonReentrant {
        DecreaseOrder storage order = decreaseOrders[_orderIndex];
        if (msg.sender != order.account) revert Forbidden();

        order.triggerMarketPriceX96 = _triggerMarketPriceX96;
        order.acceptableTradePriceX96 = _acceptableTradePriceX96;

        emit DecreaseOrderUpdated(_orderIndex, _triggerMarketPriceX96, _acceptableTradePriceX96);
    }

    /// @inheritdoc IOrderBook
    function cancelDecreaseOrder(uint256 _orderIndex, address payable _feeReceiver) external override nonReentrant {
        DecreaseOrder memory order = decreaseOrders[_orderIndex];

        if (order.account == address(0)) revert OrderNotExists(_orderIndex);

        if (order.account != msg.sender && !orderExecutors[msg.sender]) revert Forbidden();

        _transferOutETH(order.executionFee, _feeReceiver);

        delete decreaseOrders[_orderIndex];

        emit DecreaseOrderCancelled(_orderIndex, _feeReceiver);
    }

    /// @inheritdoc IOrderBook
    function executeDecreaseOrder(
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external override nonReentrant onlyOrderExecutor {
        DecreaseOrder memory order = decreaseOrders[_orderIndex];
        if (order.account == address(0)) revert OrderNotExists(_orderIndex);

        uint160 marketPriceX96 = order.pool.marketPriceX96(order.side.flip());
        _validateTriggerMarketPriceX96(order.triggerAbove, marketPriceX96, order.triggerMarketPriceX96);

        uint128 sizeDeltaAfter = order.sizeDelta;
        uint128 marginDeltaAfter = order.marginDelta;
        if (order.sizeDelta == 0) {
            // if `sizeDelta` is 0, close the position without checking the trade price
            (, sizeDeltaAfter, , ) = order.pool.positions(order.account, order.side);
            marginDeltaAfter = 0;
        }

        uint160 tradePriceX96 = router.pluginDecreasePosition{gas: executionGasLimit}(
            order.pool,
            order.account,
            order.side,
            marginDeltaAfter,
            sizeDeltaAfter,
            order.receiver
        );

        if (order.sizeDelta != 0)
            _validateTradePriceX96(order.side.flip(), tradePriceX96, order.acceptableTradePriceX96);

        _transferOutETH(order.executionFee, _feeReceiver);

        delete decreaseOrders[_orderIndex];

        emit DecreaseOrderExecuted(_orderIndex, marketPriceX96, _feeReceiver);
    }

    /// @inheritdoc IOrderBook
    function createTakeProfitAndStopLossOrders(
        IPool _pool,
        Side _side,
        uint128[2] calldata _marginDeltas,
        uint128[2] calldata _sizeDeltas,
        uint160[2] calldata _triggerMarketPriceX96s,
        uint160[2] calldata _acceptableTradePriceX96s,
        address _receiver
    ) external payable override nonReentrant {
        _side.requireValid();
        uint256 fee0 = msg.value >> 1;
        if (fee0 < minExecutionFee) revert InsufficientExecutionFee(fee0, minExecutionFee);

        _createDecreaseOrder(
            msg.sender,
            _pool,
            _side,
            _marginDeltas[0],
            _sizeDeltas[0],
            _triggerMarketPriceX96s[0],
            _side.isLong(),
            _acceptableTradePriceX96s[0],
            _receiver,
            fee0
        );
        _createDecreaseOrder(
            msg.sender,
            _pool,
            _side,
            _marginDeltas[1],
            _sizeDeltas[1],
            _triggerMarketPriceX96s[1],
            !_side.isLong(),
            _acceptableTradePriceX96s[1],
            _receiver,
            msg.value - fee0
        );
    }

    function _createDecreaseOrder(
        address _sender,
        IPool _pool,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta,
        uint160 _triggerMarketPriceX96,
        bool _triggerAbove,
        uint160 _acceptableTradePriceX96,
        address _receiver,
        uint256 _executionFee
    ) internal returns (uint256 index) {
        index = decreaseOrdersIndexNext++;
        decreaseOrders[index] = DecreaseOrder({
            account: _sender,
            pool: _pool,
            side: _side,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            triggerMarketPriceX96: _triggerMarketPriceX96,
            triggerAbove: _triggerAbove,
            acceptableTradePriceX96: _acceptableTradePriceX96,
            receiver: _receiver,
            executionFee: _executionFee
        });

        emit DecreaseOrderCreated(
            _sender,
            _pool,
            _side,
            _marginDelta,
            _sizeDelta,
            _triggerMarketPriceX96,
            _triggerAbove,
            _acceptableTradePriceX96,
            _receiver,
            _executionFee,
            index
        );
    }

    function _validateTriggerMarketPriceX96(
        bool _triggerAbove,
        uint160 _marketPriceX96,
        uint160 _triggerMarketPriceX96
    ) private pure {
        if (
            (_triggerAbove && (_marketPriceX96 < _triggerMarketPriceX96)) ||
            (!_triggerAbove && (_marketPriceX96 > _triggerMarketPriceX96))
        ) revert InvalidMarketPriceToTrigger(_marketPriceX96, _triggerMarketPriceX96);
    }

    function _validateTradePriceX96(Side _side, uint160 _tradePriceX96, uint160 _acceptableTradePriceX96) private pure {
        // long makes price up, short makes price down
        if (
            (_side.isLong() && (_tradePriceX96 > _acceptableTradePriceX96)) ||
            (_side.isShort() && (_tradePriceX96 < _acceptableTradePriceX96))
        ) revert InvalidTradePrice(_tradePriceX96, _acceptableTradePriceX96);
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        _receiver.sendValue(_amountOut);
    }
}
