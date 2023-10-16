// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../governance/Governable.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../plugins/interfaces/IOrderBook.sol";
import "../plugins/interfaces/ILiquidator.sol";
import "../plugins/interfaces/IPositionRouter.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

/// @notice MixedExecutor is a contract that executes multiple calls in a single transaction
contract MixedExecutor is Multicall, Governable {
    /// @notice Execution error
    error ExecutionError();

    struct Slot {
        /// @notice Fee receiver
        address payable feeReceiver;
        /// @notice Indicates whether to cancel the order when an execution error occurs
        bool cancelOrderIfFailedStatus;
    }

    struct SetPricesParams {
        uint160[] priceX96s;
        uint64 timestamp;
    }

    mapping(address => bool) public executors;
    ILiquidator public immutable liquidator;
    /// @notice The address of position router
    IPositionRouter public immutable positionRouter;
    /// @notice The address of price feed
    IPriceFeed public immutable priceFeed;
    /// @notice The address of order book
    IOrderBook public immutable orderBook;
    Slot public slot;
    /// @notice Cache of token addresses used on updating the price
    IERC20[] public tokens;

    modifier onlyExecutor() {
        if (!executors[msg.sender]) revert Forbidden();
        _;
    }

    constructor(ILiquidator _liquidator, IPositionRouter _router, IPriceFeed _priceFeed, IOrderBook _orderBook) {
        (liquidator, positionRouter, priceFeed, orderBook) = (_liquidator, _router, _priceFeed, _orderBook);
        slot.cancelOrderIfFailedStatus = true;
    }

    /// @notice Set executor status active or not
    /// @param _executor Executor address
    /// @param _active Status of executor permission to set
    function setExecutor(address _executor, bool _active) external onlyGov {
        executors[_executor] = _active;
    }

    /// @notice Set the cache of token addresses used on updating the price
    /// @param _tokens The token address list
    function setTokens(IERC20[] memory _tokens) external onlyGov {
        tokens = _tokens;
    }

    /// @notice Set fee receiver
    /// @param _receiver The address of new fee receiver
    function setFeeReceiver(address payable _receiver) external onlyGov {
        slot.feeReceiver = _receiver;
    }

    /// @notice Set whether to cancel the order when an execution error occurs
    /// @param _cancelOrderIfFailedStatus If the _cancelOrderIfFailedStatus is set to 1, the order is canceled
    /// when an error occurs
    function setCancelOrderIfFailedStatus(bool _cancelOrderIfFailedStatus) external onlyGov {
        slot.cancelOrderIfFailedStatus = _cancelOrderIfFailedStatus;
    }

    /// @notice Update prices
    /// @param _params The price message to update
    function setPriceX96s(SetPricesParams calldata _params) external onlyExecutor {
        uint256 priceX96sLen = _params.priceX96s.length;
        uint256 tokensLen = tokens.length;

        IPriceFeed.TokenPrice[] memory tokenPrices = new IPriceFeed.TokenPrice[](priceX96sLen);
        for (uint256 i; i < priceX96sLen; ) {
            if (i >= tokensLen) break;

            tokenPrices[i] = IPriceFeed.TokenPrice({token: tokens[i], priceX96: _params.priceX96s[i]});

            // prettier-ignore
            unchecked { ++i; }
        }
        priceFeed.setPriceX96s(tokenPrices, _params.timestamp);
    }

    /// @notice Update prices
    /// @dev This function is used to update the price of only a subset of tokens
    /// @param _tokenPrices Array of token addresses and prices to update for
    /// @param _timestamp The timestamp of price update
    function fastSetPriceX96s(IPriceFeed.TokenPrice[] calldata _tokenPrices, uint64 _timestamp) external onlyExecutor {
        priceFeed.setPriceX96s(_tokenPrices, _timestamp);
    }

    /// @notice Execute multiple liquidity position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeOpenLiquidityPositions(uint128 _endIndex) external onlyExecutor {
        positionRouter.executeOpenLiquidityPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple close liquidity position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeCloseLiquidityPositions(uint128 _endIndex) external onlyExecutor {
        positionRouter.executeCloseLiquidityPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple adjust liquidity position margin requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeAdjustLiquidityPositionMargins(uint128 _endIndex) external onlyExecutor {
        positionRouter.executeAdjustLiquidityPositionMargins(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple increase risk buffer fund positions
    /// @param _endIndex The maximum request index to execute, excluded
    function executeIncreaseRiskBufferFundPositions(uint128 _endIndex) external onlyExecutor {
        positionRouter.executeIncreaseRiskBufferFundPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple decrease risk buffer fund positions
    /// @param _endIndex The maximum request index to execute, excluded
    function executeDecreaseRiskBufferFundPositions(uint128 _endIndex) external onlyExecutor {
        positionRouter.executeDecreaseRiskBufferFundPositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple increase position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeIncreasePositions(uint128 _endIndex) external onlyExecutor {
        positionRouter.executeIncreasePositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Execute multiple decrease position requests
    /// @param _endIndex The maximum request index to execute, excluded
    function executeDecreasePositions(uint128 _endIndex) external onlyExecutor {
        positionRouter.executeDecreasePositions(_endIndex, _getFeeReceiver());
    }

    /// @notice Sample and adjust funding rate
    /// @param _pool The pool address
    function sampleAndAdjustFundingRate(IPool _pool) external {
        _pool.sampleAndAdjustFundingRate();
    }

    /// @notice Collect protocol fee
    /// @param _pool The pool address
    function collectProtocolFee(IPool _pool) external {
        _pool.collectProtocolFee();
    }

    /// @notice Execute an existing increase order
    /// @param _orderIndex The index of order to execute
    /// @param _requireSuccess True if the execution error is ignored, false otherwise.
    function executeIncreaseOrder(uint256 _orderIndex, bool _requireSuccess) external onlyExecutor {
        try orderBook.executeIncreaseOrder(_orderIndex, _getFeeReceiver()) {} catch {
            if (_requireSuccess) revert ExecutionError();

            if (slot.cancelOrderIfFailedStatus)
                try orderBook.cancelIncreaseOrder(_orderIndex, _getFeeReceiver()) {} catch {}
        }
    }

    /// @notice Execute an existing decrease order
    /// @param _orderIndex The index of order to execute
    /// @param _requireSuccess True if the execution error is ignored, false otherwise.
    function executeDecreaseOrder(uint256 _orderIndex, bool _requireSuccess) external onlyExecutor {
        address payable feeReceiver = slot.feeReceiver == address(0) ? payable(msg.sender) : slot.feeReceiver;
        try orderBook.executeDecreaseOrder(_orderIndex, feeReceiver) {} catch {
            if (_requireSuccess) revert ExecutionError();

            if (slot.cancelOrderIfFailedStatus)
                try orderBook.cancelDecreaseOrder(_orderIndex, _getFeeReceiver()) {} catch {}
        }
    }

    /// @notice Liquidate a liquidity position
    /// @param _pool The pool address
    /// @param _positionID The position ID
    /// @param _requireSuccess True if the execution error is ignored, false otherwise.
    function liquidateLiquidityPosition(IPool _pool, uint96 _positionID, bool _requireSuccess) external onlyExecutor {
        try liquidator.liquidateLiquidityPosition(_pool, _positionID, _getFeeReceiver()) {} catch {
            if (_requireSuccess) revert ExecutionError();
        }
    }

    /// @notice Liquidate a position
    /// @param _pool The pool address
    /// @param _account The owner of the position
    /// @param _side The side of the position (Long or Short)
    /// @param _requireSuccess True if the execution error is ignored, false otherwise.
    function liquidatePosition(IPool _pool, address _account, Side _side, bool _requireSuccess) external onlyExecutor {
        try liquidator.liquidatePosition(_pool, _account, _side, _getFeeReceiver()) {} catch {
            if (_requireSuccess) revert ExecutionError();
        }
    }

    function _getFeeReceiver() private view returns (address payable) {
        return slot.feeReceiver == address(0) ? payable(msg.sender) : slot.feeReceiver;
    }
}
