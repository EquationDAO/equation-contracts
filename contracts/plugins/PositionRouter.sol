// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./Router.sol";
import "../libraries/SafeCast.sol";
import "../libraries/ReentrancyGuard.sol";
import {M as Math} from "../libraries/Math.sol";
import "./interfaces/IPositionRouter.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract PositionRouter is IPositionRouter, Governable, ReentrancyGuard {
    using SafeCast for uint256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    IERC20 public immutable usd;
    Router public immutable router;

    uint256 public minExecutionFee;

    // pack into a single slot to save gas
    uint32 public minBlockDelayExecutor;
    uint32 public minTimeDelayPublic = 3 minutes;
    uint32 public maxTimeDelay = 30 minutes;
    uint160 public executionGasLimit = 1_000_000 wei;

    mapping(address => bool) public positionExecutors;

    // LP stats
    mapping(uint128 => OpenLiquidityPositionRequest) public openLiquidityPositionRequests;
    uint128 public openLiquidityPositionIndex;
    uint128 public openLiquidityPositionIndexNext;

    mapping(uint128 => CloseLiquidityPositionRequest) public closeLiquidityPositionRequests;
    uint128 public closeLiquidityPositionIndex;
    uint128 public closeLiquidityPositionIndexNext;

    mapping(uint128 => AdjustLiquidityPositionMarginRequest) public adjustLiquidityPositionMarginRequests;
    uint128 public adjustLiquidityPositionMarginIndex;
    uint128 public adjustLiquidityPositionMarginIndexNext;

    mapping(uint128 => IncreaseRiskBufferFundPositionRequest) public increaseRiskBufferFundPositionRequests;
    uint128 public increaseRiskBufferFundPositionIndex;
    uint128 public increaseRiskBufferFundPositionIndexNext;

    mapping(uint128 => DecreaseRiskBufferFundPositionRequest) public decreaseRiskBufferFundPositionRequests;
    uint128 public decreaseRiskBufferFundPositionIndex;
    uint128 public decreaseRiskBufferFundPositionIndexNext;

    // Trader stats
    mapping(uint128 => IncreasePositionRequest) public increasePositionRequests;
    uint128 public increasePositionIndex;
    uint128 public increasePositionIndexNext;

    mapping(uint128 => DecreasePositionRequest) public decreasePositionRequests;
    uint128 public decreasePositionIndex;
    uint128 public decreasePositionIndexNext;

    modifier onlyPositionExecutor() {
        if (!positionExecutors[msg.sender]) revert Forbidden();
        _;
    }

    constructor(IERC20 _usd, Router _router, uint256 _minExecutionFee) {
        usd = _usd;
        router = _router;
        minExecutionFee = _minExecutionFee;
        emit MinExecutionFeeUpdated(_minExecutionFee);
    }

    /// @inheritdoc IPositionRouter
    function updatePositionExecutor(address _account, bool _active) external override onlyGov {
        positionExecutors[_account] = _active;
        emit PositionExecutorUpdated(_account, _active);
    }

    /// @inheritdoc IPositionRouter
    function updateDelayValues(
        uint32 _minBlockDelayExecutor,
        uint32 _minTimeDelayPublic,
        uint32 _maxTimeDelay
    ) external override onlyGov {
        minBlockDelayExecutor = _minBlockDelayExecutor;
        minTimeDelayPublic = _minTimeDelayPublic;
        maxTimeDelay = _maxTimeDelay;
        emit DelayValuesUpdated(_minBlockDelayExecutor, _minTimeDelayPublic, _maxTimeDelay);
    }

    /// @inheritdoc IPositionRouter
    function updateMinExecutionFee(uint256 _minExecutionFee) external override onlyGov {
        minExecutionFee = _minExecutionFee;
        emit MinExecutionFeeUpdated(_minExecutionFee);
    }

    /// @inheritdoc IPositionRouter
    function updateExecutionGasLimit(uint160 _executionGasLimit) external override onlyGov {
        executionGasLimit = _executionGasLimit;
    }

    /// @inheritdoc IPositionRouter
    function createOpenLiquidityPosition(
        IPool _pool,
        uint128 _margin,
        uint128 _liquidity
    ) external payable override nonReentrant returns (uint128 index) {
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        router.pluginTransfer(usd, msg.sender, address(this), _margin);

        index = openLiquidityPositionIndexNext++;
        openLiquidityPositionRequests[index] = OpenLiquidityPositionRequest({
            account: msg.sender,
            pool: _pool,
            margin: _margin,
            liquidity: _liquidity,
            executionFee: msg.value,
            blockNumber: block.number.toUint96(),
            blockTime: block.timestamp.toUint64()
        });

        emit OpenLiquidityPositionCreated(msg.sender, _pool, _margin, _liquidity, msg.value, index);
    }

    /// @inheritdoc IPositionRouter
    function cancelOpenLiquidityPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        OpenLiquidityPositionRequest memory request = openLiquidityPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldCancel = _shouldCancel(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) return false;

        usd.safeTransfer(request.account, request.margin);

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete openLiquidityPositionRequests[_index];

        emit OpenLiquidityPositionCancelled(_index, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeOpenLiquidityPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        OpenLiquidityPositionRequest memory request = openLiquidityPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldExecute = _shouldExecute(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) return false;

        usd.safeTransfer(address(request.pool), request.margin);

        // Note that the gas specified here is just an upper limit,
        // when the gas left is lower than this value, code can still be executed
        router.pluginOpenLiquidityPosition{gas: executionGasLimit}(
            request.pool,
            request.account,
            request.margin,
            request.liquidity
        );

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete openLiquidityPositionRequests[_index];

        emit OpenLiquidityPositionExecuted(_index, _executionFeeReceiver);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeOpenLiquidityPositions(
        uint128 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        uint128 index = openLiquidityPositionIndex;
        _endIndex = uint128(Math.min(_endIndex, openLiquidityPositionIndexNext));

        while (index < _endIndex) {
            try this.executeOpenLiquidityPosition(index, _executionFeeReceiver) returns (bool _executed) {
                if (!_executed) break;
            } catch {
                try this.cancelOpenLiquidityPosition(index, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) break;
                } catch {}
            }
            // prettier-ignore
            unchecked { ++index; }
        }

        openLiquidityPositionIndex = index;
    }

    /// @inheritdoc IPositionRouter
    function createCloseLiquidityPosition(
        IPool _pool,
        uint96 _positionID,
        address _receiver
    ) external payable override nonReentrant returns (uint128 index) {
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        address owner = _pool.liquidityPositionAccount(_positionID);
        if (owner != msg.sender) revert Forbidden();

        index = closeLiquidityPositionIndexNext++;
        closeLiquidityPositionRequests[index] = CloseLiquidityPositionRequest({
            account: msg.sender,
            pool: _pool,
            positionID: _positionID,
            receiver: _receiver,
            executionFee: msg.value,
            blockNumber: block.number.toUint96(),
            blockTime: block.timestamp.toUint64()
        });

        emit CloseLiquidityPositionCreated(msg.sender, _pool, _positionID, _receiver, msg.value, index);
    }

    /// @inheritdoc IPositionRouter
    function cancelCloseLiquidityPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        CloseLiquidityPositionRequest memory request = closeLiquidityPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldCancel = _shouldCancel(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) return false;

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete closeLiquidityPositionRequests[_index];

        emit CloseLiquidityPositionCancelled(_index, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeCloseLiquidityPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        CloseLiquidityPositionRequest memory request = closeLiquidityPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldExecute = _shouldExecute(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) return false;

        router.pluginCloseLiquidityPosition{gas: executionGasLimit}(request.pool, request.positionID, request.receiver);

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete closeLiquidityPositionRequests[_index];

        emit CloseLiquidityPositionExecuted(_index, _executionFeeReceiver);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeCloseLiquidityPositions(
        uint128 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        uint128 index = closeLiquidityPositionIndex;
        _endIndex = uint128(Math.min(_endIndex, closeLiquidityPositionIndexNext));

        while (index < _endIndex) {
            try this.executeCloseLiquidityPosition(index, _executionFeeReceiver) returns (bool _executed) {
                if (!_executed) break;
            } catch {
                try this.cancelCloseLiquidityPosition(index, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) break;
                } catch {}
            }
            // prettier-ignore
            unchecked { ++index; }
        }

        closeLiquidityPositionIndex = index;
    }

    /// @inheritdoc IPositionRouter
    function createAdjustLiquidityPositionMargin(
        IPool _pool,
        uint96 _positionID,
        int128 _marginDelta,
        address _receiver
    ) external payable override nonReentrant returns (uint128 index) {
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        address owner = _pool.liquidityPositionAccount(_positionID);
        if (owner != msg.sender) revert Forbidden();

        if (_marginDelta > 0) router.pluginTransfer(usd, msg.sender, address(this), uint128(_marginDelta));

        index = adjustLiquidityPositionMarginIndexNext++;
        adjustLiquidityPositionMarginRequests[index] = AdjustLiquidityPositionMarginRequest({
            account: msg.sender,
            pool: _pool,
            positionID: _positionID,
            marginDelta: _marginDelta,
            receiver: _receiver,
            executionFee: msg.value,
            blockNumber: block.number.toUint96(),
            blockTime: block.timestamp.toUint64()
        });

        emit AdjustLiquidityPositionMarginCreated(
            msg.sender,
            _pool,
            _positionID,
            _marginDelta,
            _receiver,
            msg.value,
            index
        );
    }

    /// @inheritdoc IPositionRouter
    function cancelAdjustLiquidityPositionMargin(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        AdjustLiquidityPositionMarginRequest memory request = adjustLiquidityPositionMarginRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldCancel = _shouldCancel(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) return false;

        if (request.marginDelta > 0) usd.safeTransfer(request.account, uint128(request.marginDelta));

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete adjustLiquidityPositionMarginRequests[_index];

        emit AdjustLiquidityPositionMarginCancelled(_index, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeAdjustLiquidityPositionMargin(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        AdjustLiquidityPositionMarginRequest memory request = adjustLiquidityPositionMarginRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldExecute = _shouldExecute(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) return false;

        if (request.marginDelta > 0) usd.safeTransfer(address(request.pool), uint128(request.marginDelta));

        router.pluginAdjustLiquidityPositionMargin{gas: executionGasLimit}(
            request.pool,
            request.positionID,
            request.marginDelta,
            request.receiver
        );

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete adjustLiquidityPositionMarginRequests[_index];

        emit AdjustLiquidityPositionMarginExecuted(_index, _executionFeeReceiver);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeAdjustLiquidityPositionMargins(
        uint128 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        uint128 index = adjustLiquidityPositionMarginIndex;
        _endIndex = uint128(Math.min(_endIndex, adjustLiquidityPositionMarginIndexNext));

        while (index < _endIndex) {
            try this.executeAdjustLiquidityPositionMargin(index, _executionFeeReceiver) returns (bool _executed) {
                if (!_executed) break;
            } catch {
                try this.cancelAdjustLiquidityPositionMargin(index, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) break;
                } catch {}
            }
            // prettier-ignore
            unchecked { ++index; }
        }

        adjustLiquidityPositionMarginIndex = index;
    }

    /// @inheritdoc IPositionRouter
    function createIncreaseRiskBufferFundPosition(
        IPool _pool,
        uint128 _liquidityDelta
    ) external payable override nonReentrant returns (uint128 index) {
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        router.pluginTransfer(usd, msg.sender, address(this), _liquidityDelta);

        index = increaseRiskBufferFundPositionIndexNext++;
        increaseRiskBufferFundPositionRequests[index] = IncreaseRiskBufferFundPositionRequest({
            account: msg.sender,
            pool: _pool,
            liquidityDelta: _liquidityDelta,
            executionFee: msg.value,
            blockNumber: block.number.toUint96(),
            blockTime: block.timestamp.toUint64()
        });

        emit IncreaseRiskBufferFundPositionCreated(msg.sender, _pool, _liquidityDelta, msg.value, index);
    }

    /// @inheritdoc IPositionRouter
    function cancelIncreaseRiskBufferFundPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        IncreaseRiskBufferFundPositionRequest memory request = increaseRiskBufferFundPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldCancel = _shouldCancel(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) return false;

        usd.safeTransfer(request.account, request.liquidityDelta);

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete increaseRiskBufferFundPositionRequests[_index];

        emit IncreaseRiskBufferFundPositionCancelled(_index, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeIncreaseRiskBufferFundPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        IncreaseRiskBufferFundPositionRequest memory request = increaseRiskBufferFundPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldExecute = _shouldExecute(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) return false;

        usd.safeTransfer(address(request.pool), request.liquidityDelta);

        router.pluginIncreaseRiskBufferFundPosition{gas: executionGasLimit}(
            request.pool,
            request.account,
            request.liquidityDelta
        );

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete increaseRiskBufferFundPositionRequests[_index];

        emit IncreaseRiskBufferFundPositionExecuted(_index, _executionFeeReceiver);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeIncreaseRiskBufferFundPositions(
        uint128 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        uint128 index = increaseRiskBufferFundPositionIndex;
        _endIndex = uint128(Math.min(_endIndex, increaseRiskBufferFundPositionIndexNext));

        while (index < _endIndex) {
            try this.executeIncreaseRiskBufferFundPosition(index, _executionFeeReceiver) returns (bool _executed) {
                if (!_executed) break;
            } catch {
                try this.cancelIncreaseRiskBufferFundPosition(index, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) break;
                } catch {}
            }
            // prettier-ignore
            unchecked { ++index; }
        }

        increaseRiskBufferFundPositionIndex = index;
    }

    /// @inheritdoc IPositionRouter
    function createDecreaseRiskBufferFundPosition(
        IPool _pool,
        uint128 _liquidityDelta,
        address _receiver
    ) external payable override nonReentrant returns (uint128 index) {
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        index = decreaseRiskBufferFundPositionIndexNext++;
        decreaseRiskBufferFundPositionRequests[index] = DecreaseRiskBufferFundPositionRequest({
            account: msg.sender,
            pool: _pool,
            liquidityDelta: _liquidityDelta,
            receiver: _receiver,
            executionFee: msg.value,
            blockNumber: block.number.toUint96(),
            blockTime: block.timestamp.toUint64()
        });

        emit DecreaseRiskBufferFundPositionCreated(msg.sender, _pool, _liquidityDelta, _receiver, msg.value, index);
    }

    /// @inheritdoc IPositionRouter
    function cancelDecreaseRiskBufferFundPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        DecreaseRiskBufferFundPositionRequest memory request = decreaseRiskBufferFundPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldCancel = _shouldCancel(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) return false;

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete decreaseRiskBufferFundPositionRequests[_index];

        emit DecreaseRiskBufferFundPositionCancelled(_index, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeDecreaseRiskBufferFundPosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        DecreaseRiskBufferFundPositionRequest memory request = decreaseRiskBufferFundPositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldExecute = _shouldExecute(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) return false;

        router.pluginDecreaseRiskBufferFundPosition{gas: executionGasLimit}(
            request.pool,
            request.account,
            request.liquidityDelta,
            request.receiver
        );

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete decreaseRiskBufferFundPositionRequests[_index];

        emit DecreaseRiskBufferFundPositionExecuted(_index, _executionFeeReceiver);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeDecreaseRiskBufferFundPositions(
        uint128 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        uint128 index = decreaseRiskBufferFundPositionIndex;
        _endIndex = uint128(Math.min(_endIndex, decreaseRiskBufferFundPositionIndexNext));

        while (index < _endIndex) {
            try this.executeDecreaseRiskBufferFundPosition(index, _executionFeeReceiver) returns (bool _executed) {
                if (!_executed) break;
            } catch {
                try this.cancelDecreaseRiskBufferFundPosition(index, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) break;
                } catch {}
            }
            // prettier-ignore
            unchecked { ++index; }
        }

        decreaseRiskBufferFundPositionIndex = index;
    }

    /// @inheritdoc IPositionRouter
    function createIncreasePosition(
        IPool _pool,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta,
        uint160 _acceptableTradePriceX96
    ) external payable override nonReentrant returns (uint128 index) {
        _side.requireValid();
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        if (_marginDelta > 0) router.pluginTransfer(usd, msg.sender, address(this), _marginDelta);

        index = increasePositionIndexNext++;
        increasePositionRequests[index] = IncreasePositionRequest({
            account: msg.sender,
            pool: _pool,
            side: _side,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            acceptableTradePriceX96: _acceptableTradePriceX96,
            executionFee: msg.value,
            blockNumber: block.number.toUint96(),
            blockTime: block.timestamp.toUint64()
        });

        emit IncreasePositionCreated(
            msg.sender,
            _pool,
            _side,
            _marginDelta,
            _sizeDelta,
            _acceptableTradePriceX96,
            msg.value,
            index
        );
    }

    /// @inheritdoc IPositionRouter
    function cancelIncreasePosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldCancel = _shouldCancel(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) return false;

        if (request.marginDelta > 0) usd.safeTransfer(request.account, request.marginDelta);

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete increasePositionRequests[_index];

        emit IncreasePositionCancelled(_index, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeIncreasePosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        IncreasePositionRequest memory request = increasePositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldExecute = _shouldExecute(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) return false;

        if (request.marginDelta > 0) usd.safeTransfer(address(request.pool), request.marginDelta);

        uint160 tradePriceX96 = router.pluginIncreasePosition{gas: executionGasLimit}(
            request.pool,
            request.account,
            request.side,
            request.marginDelta,
            request.sizeDelta
        );

        if (request.acceptableTradePriceX96 != 0)
            _validateTradePriceX96(request.side, tradePriceX96, request.acceptableTradePriceX96);

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete increasePositionRequests[_index];

        emit IncreasePositionExecuted(_index, _executionFeeReceiver);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeIncreasePositions(
        uint128 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        uint128 index = increasePositionIndex;
        _endIndex = uint128(Math.min(_endIndex, increasePositionIndexNext));

        while (index < _endIndex) {
            try this.executeIncreasePosition(index, _executionFeeReceiver) returns (bool _executed) {
                if (!_executed) break;
            } catch {
                try this.cancelIncreasePosition(index, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) break;
                } catch {}
            }
            // prettier-ignore
            unchecked { ++index; }
        }

        increasePositionIndex = index;
    }

    /// @inheritdoc IPositionRouter
    function createDecreasePosition(
        IPool _pool,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta,
        uint160 _acceptableTradePriceX96,
        address _receiver
    ) external payable override nonReentrant returns (uint128 index) {
        _side.requireValid();
        if (msg.value < minExecutionFee) revert InsufficientExecutionFee(msg.value, minExecutionFee);

        index = decreasePositionIndexNext++;
        decreasePositionRequests[index] = DecreasePositionRequest({
            account: msg.sender,
            pool: _pool,
            side: _side,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            acceptableTradePriceX96: _acceptableTradePriceX96,
            receiver: _receiver,
            executionFee: msg.value,
            blockNumber: block.number.toUint96(),
            blockTime: block.timestamp.toUint64()
        });

        emit DecreasePositionCreated(
            msg.sender,
            _pool,
            _side,
            _marginDelta,
            _sizeDelta,
            _acceptableTradePriceX96,
            _receiver,
            msg.value,
            index
        );
    }

    /// @inheritdoc IPositionRouter
    function cancelDecreasePosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldCancel = _shouldCancel(request.blockNumber, request.blockTime, request.account);
        if (!shouldCancel) return false;

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete decreasePositionRequests[_index];

        emit DecreasePositionCancelled(_index, _executionFeeReceiver);

        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeDecreasePosition(
        uint128 _index,
        address payable _executionFeeReceiver
    ) external override nonReentrant returns (bool) {
        DecreasePositionRequest memory request = decreasePositionRequests[_index];
        if (request.account == address(0)) return true;

        bool shouldExecute = _shouldExecute(request.blockNumber, request.blockTime, request.account);
        if (!shouldExecute) return false;

        uint160 tradePriceX96 = router.pluginDecreasePosition{gas: executionGasLimit}(
            request.pool,
            request.account,
            request.side,
            request.marginDelta,
            request.sizeDelta,
            request.receiver
        );

        if (request.acceptableTradePriceX96 != 0)
            _validateTradePriceX96(request.side.flip(), tradePriceX96, request.acceptableTradePriceX96);

        _transferOutETH(request.executionFee, _executionFeeReceiver);

        delete decreasePositionRequests[_index];

        emit DecreasePositionExecuted(_index, _executionFeeReceiver);
        return true;
    }

    /// @inheritdoc IPositionRouter
    function executeDecreasePositions(
        uint128 _endIndex,
        address payable _executionFeeReceiver
    ) external override onlyPositionExecutor {
        uint128 index = decreasePositionIndex;
        _endIndex = uint128(Math.min(_endIndex, decreasePositionIndexNext));

        while (index < _endIndex) {
            try this.executeDecreasePosition(index, _executionFeeReceiver) returns (bool _executed) {
                if (!_executed) break;
            } catch {
                try this.cancelDecreasePosition(index, _executionFeeReceiver) returns (bool _cancelled) {
                    if (!_cancelled) break;
                } catch {}
            }
            // prettier-ignore
            unchecked { ++index; }
        }

        decreasePositionIndex = index;
    }

    // validation
    function _shouldCancel(
        uint256 _positionBlockNumber,
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        return _shouldExecuteOrCancel(_positionBlockNumber, _positionBlockTime, _account);
    }

    function _shouldExecute(
        uint256 _positionBlockNumber,
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        if (_positionBlockTime.add(maxTimeDelay) <= block.timestamp)
            revert Expired(_positionBlockTime.add(maxTimeDelay));

        return _shouldExecuteOrCancel(_positionBlockNumber, _positionBlockTime, _account);
    }

    function _shouldExecuteOrCancel(
        uint256 _positionBlockNumber,
        uint256 _positionBlockTime,
        address _account
    ) internal view returns (bool) {
        bool isExecutorCall = msg.sender == address(this) || positionExecutors[msg.sender];

        if (isExecutorCall) return _positionBlockNumber.add(minBlockDelayExecutor) <= block.number;

        if (msg.sender != _account) revert Forbidden();

        if (_positionBlockTime.add(minTimeDelayPublic) > block.timestamp)
            revert TooEarly(_positionBlockTime.add(minTimeDelayPublic));

        return true;
    }

    function _validateTradePriceX96(
        Side _side,
        uint160 _tradePriceX96,
        uint160 _acceptableTradePriceX96
    ) internal pure {
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
