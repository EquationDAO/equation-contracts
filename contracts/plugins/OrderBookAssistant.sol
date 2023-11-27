// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./OrderBook.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

/// @notice A helper contract to cancel orders in batch
/// @custom:since v0.0.4
contract OrderBookAssistant is Multicall {
    OrderBook public immutable orderBook;

    constructor(OrderBook _orderBook) {
        orderBook = _orderBook;
    }

    /// @notice Cancel increase orders in batch
    /// @param _orderIndexes The indexes of orders to cancel
    function cancelIncreaseOrderBatch(uint256[] calldata _orderIndexes) external virtual {
        _cancelOrderBatch(_orderIndexes, _accountForIncreaseOrder, _cancelIncreaseOrder);
    }

    /// @notice Cancel decrease orders in batch
    /// @param _orderIndexes The indexes of orders to cancel
    function cancelDecreaseOrderBatch(uint256[] calldata _orderIndexes) external virtual {
        _cancelOrderBatch(_orderIndexes, _accountForDecreaseOrder, _cancelDecreaseOrder);
    }

    function _cancelOrderBatch(
        uint256[] calldata _orderIndexes,
        function(uint256) internal returns (address) _accountForFn,
        function(uint256, address payable) internal _cancelFn
    ) internal virtual {
        address sender = msg.sender;
        uint256 len = _orderIndexes.length;
        uint256 orderIndex;
        for (uint256 i; i < len; ) {
            orderIndex = _orderIndexes[i];
            if (sender != _accountForFn(orderIndex)) revert Governable.Forbidden();

            _cancelFn(orderIndex, payable(sender));

            // prettier-ignore
            unchecked { ++i; }
        }
    }

    function _accountForIncreaseOrder(uint256 _orderIndex) internal virtual returns (address account) {
        (account, , , , , , , , ) = orderBook.increaseOrders(_orderIndex);
    }

    function _cancelIncreaseOrder(uint256 _orderIndex, address payable _feeReceiver) internal virtual {
        orderBook.cancelIncreaseOrder(_orderIndex, _feeReceiver);
    }

    function _accountForDecreaseOrder(uint256 _orderIndex) internal virtual returns (address account) {
        (account, , , , , , , , , ) = orderBook.decreaseOrders(_orderIndex);
    }

    function _cancelDecreaseOrder(uint256 _orderIndex, address payable _feeReceiver) internal virtual {
        orderBook.cancelDecreaseOrder(_orderIndex, _feeReceiver);
    }
}
