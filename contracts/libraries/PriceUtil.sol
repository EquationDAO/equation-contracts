// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./LiquidityPositionUtil.sol";

library PriceUtil {
    using SafeCast for *;

    struct MoveStep {
        Side side;
        uint128 sizeLeft;
        uint160 indexPriceX96;
        bool improveBalance;
        IPool.PriceVertex from;
        IPool.PriceVertex current;
        IPool.PriceVertex to;
    }

    struct PriceStateCache {
        uint128 premiumRateX96;
        uint8 pendingVertexIndex;
        uint8 liquidationVertexIndex;
        uint8 currentVertexIndex;
    }

    /// @notice Emitted when the premium rate is changed
    event PremiumRateChanged(uint128 premiumRateAfterX96);

    /// @notice Emitted when liquidation buffer net size is changed
    event LiquidationBufferNetSizeChanged(uint8 index, uint128 netSizeAfter);

    /// @notice Emitted when premium rate overflows, should stop calculation
    error MaxPremiumRateExceeded();

    /// @notice Emitted when sizeDelta is zero
    error ZeroSizeDelta();

    /// @notice Calculate trade price and update the price state when traders adjust positions.
    /// For liquidations, call this function to update the price state but the trade price returned is invalid
    /// @param _globalPosition Global position of the lp, will be updated
    /// @param _priceState States of the price, will be updated
    /// @param _side Side of the operation
    /// @param _sizeDelta The adjustment of size
    /// @param _indexPriceX96 The index price, as a Q64.96
    /// @param _liquidation Whether the operation is liquidation
    /// @return tradePriceX96 The average price of the adjustment if liquidation is false, invalid otherwise
    function updatePriceState(
        IPool.GlobalLiquidityPosition storage _globalPosition,
        IPool.PriceState storage _priceState,
        Side _side,
        uint128 _sizeDelta,
        uint160 _indexPriceX96,
        bool _liquidation
    ) public returns (uint160 tradePriceX96) {
        if (_sizeDelta == 0) revert ZeroSizeDelta();
        IPool.GlobalLiquidityPosition memory globalPositionCache = _globalPosition;
        PriceStateCache memory priceStateCache = PriceStateCache({
            premiumRateX96: _priceState.premiumRateX96,
            pendingVertexIndex: _priceState.pendingVertexIndex,
            liquidationVertexIndex: _priceState.liquidationVertexIndex,
            currentVertexIndex: _priceState.currentVertexIndex
        });

        bool improveBalance = _side == globalPositionCache.side &&
            (globalPositionCache.netSize | globalPositionCache.liquidationBufferNetSize) > 0;

        (uint256 tradePriceX96TimesSizeTotal, uint128 sizeLeft, uint128 totalBufferUsed) = _updatePriceState(
            globalPositionCache,
            _priceState,
            priceStateCache,
            _side,
            improveBalance,
            _sizeDelta,
            _indexPriceX96,
            _liquidation
        );

        if (!improveBalance) {
            globalPositionCache.side = _side.flip();
            globalPositionCache.netSize += _sizeDelta - totalBufferUsed;
            globalPositionCache.liquidationBufferNetSize += totalBufferUsed;
        } else {
            // When the net position of LP decreases and reaches or crosses the vertex,
            // at least the vertex represented by (current, pending] needs to be updated
            if (priceStateCache.pendingVertexIndex > priceStateCache.currentVertexIndex) {
                IPool(address(this)).changePriceVertex(
                    priceStateCache.currentVertexIndex,
                    priceStateCache.pendingVertexIndex
                );
                _priceState.pendingVertexIndex = priceStateCache.currentVertexIndex;
            }

            globalPositionCache.netSize -= _sizeDelta - sizeLeft - totalBufferUsed;
            globalPositionCache.liquidationBufferNetSize -= totalBufferUsed;
        }

        if (sizeLeft > 0) {
            assert((globalPositionCache.netSize | globalPositionCache.liquidationBufferNetSize) == 0);

            // Note that if and only if crossed the (0, 0), update the global position side
            globalPositionCache.side = globalPositionCache.side.flip();

            (uint256 tradePriceX96TimesSizeTotal2, , uint128 totalBufferUsed2) = _updatePriceState(
                globalPositionCache,
                _priceState,
                priceStateCache,
                _side,
                false,
                sizeLeft,
                _indexPriceX96,
                _liquidation
            );

            tradePriceX96TimesSizeTotal += tradePriceX96TimesSizeTotal2;

            globalPositionCache.netSize = sizeLeft - totalBufferUsed2;
            globalPositionCache.liquidationBufferNetSize = totalBufferUsed2;
        }

        tradePriceX96 = _side.isLong()
            ? Math.ceilDiv(tradePriceX96TimesSizeTotal, _sizeDelta).toUint160()
            : (tradePriceX96TimesSizeTotal / _sizeDelta).toUint160();

        // Write the changes back to storage
        _globalPosition.side = globalPositionCache.side;
        _globalPosition.netSize = globalPositionCache.netSize;
        _globalPosition.liquidationBufferNetSize = globalPositionCache.liquidationBufferNetSize;
        _priceState.premiumRateX96 = priceStateCache.premiumRateX96;
        _priceState.currentVertexIndex = priceStateCache.currentVertexIndex;

        emit PremiumRateChanged(priceStateCache.premiumRateX96);
    }

    function _updatePriceState(
        IPool.GlobalLiquidityPosition memory _globalPositionCache,
        IPool.PriceState storage _priceState,
        PriceStateCache memory _priceStateCache,
        Side _side,
        bool _improveBalance,
        uint128 _sizeDelta,
        uint160 _indexPriceX96,
        bool _liquidation
    ) internal returns (uint256 tradePriceX96TimesSizeTotal, uint128 sizeLeft, uint128 totalBufferUsed) {
        MoveStep memory step = MoveStep({
            side: _side,
            sizeLeft: _sizeDelta,
            indexPriceX96: _indexPriceX96,
            improveBalance: _improveBalance,
            from: IPool.PriceVertex(0, 0),
            current: IPool.PriceVertex(_globalPositionCache.netSize, _priceStateCache.premiumRateX96),
            to: IPool.PriceVertex(0, 0)
        });
        if (!step.improveBalance) {
            // Balance rate got worse
            if (_priceStateCache.currentVertexIndex == 0) _priceStateCache.currentVertexIndex = 1;
            uint8 end = _liquidation ? _priceStateCache.liquidationVertexIndex + 1 : Constants.VERTEX_NUM;
            for (uint8 i = _priceStateCache.currentVertexIndex; i < end && step.sizeLeft > 0; ++i) {
                (step.from, step.to) = (_priceState.priceVertices[i - 1], _priceState.priceVertices[i]);
                (uint160 tradePriceX96, uint128 sizeUsed, , int256 premiumRateAfterX96) = simulateMove(step);

                if (sizeUsed < step.sizeLeft && !(_liquidation && i == _priceStateCache.liquidationVertexIndex)) {
                    // Crossed
                    // prettier-ignore
                    unchecked { _priceStateCache.currentVertexIndex = i + 1; }
                    step.current = step.to;
                }

                // prettier-ignore
                unchecked { step.sizeLeft -= sizeUsed; }
                tradePriceX96TimesSizeTotal += uint256(tradePriceX96) * sizeUsed;
                _priceStateCache.premiumRateX96 = uint256(premiumRateAfterX96).toUint128();
            }

            if (step.sizeLeft > 0) {
                if (!_liquidation) revert MaxPremiumRateExceeded();

                // prettier-ignore
                unchecked { totalBufferUsed += step.sizeLeft; }

                uint8 liquidationVertexIndex = _priceStateCache.liquidationVertexIndex;
                uint128 liquidationBufferNetSizeAfter = _priceState.liquidationBufferNetSizes[liquidationVertexIndex] +
                    step.sizeLeft;
                _priceState.liquidationBufferNetSizes[liquidationVertexIndex] = liquidationBufferNetSizeAfter;
                emit LiquidationBufferNetSizeChanged(liquidationVertexIndex, liquidationBufferNetSizeAfter);
            }
        } else {
            // Balance rate got better, note that when `i` == 0, loop continues to use liquidation buffer in (0, 0)
            for (uint8 i = _priceStateCache.currentVertexIndex; i >= 0 && step.sizeLeft > 0; --i) {
                // Use liquidation buffer in `from`
                uint128 bufferSizeAfter = _priceState.liquidationBufferNetSizes[i];
                if (bufferSizeAfter > 0) {
                    uint128 sizeUsed = uint128(Math.min(bufferSizeAfter, step.sizeLeft));
                    uint160 tradePriceX96 = calculateMarketPriceX96(
                        _globalPositionCache.side,
                        _side,
                        _indexPriceX96,
                        step.current.premiumRateX96
                    );
                    // prettier-ignore
                    unchecked { bufferSizeAfter -= sizeUsed; }
                    _priceState.liquidationBufferNetSizes[i] = bufferSizeAfter;
                    // prettier-ignore
                    unchecked { totalBufferUsed += sizeUsed; }

                    // prettier-ignore
                    unchecked { step.sizeLeft -= sizeUsed; }
                    tradePriceX96TimesSizeTotal += uint256(tradePriceX96) * sizeUsed;
                    emit LiquidationBufferNetSizeChanged(i, bufferSizeAfter);
                }
                if (i == 0) break;
                if (step.sizeLeft > 0) {
                    step.from = _priceState.priceVertices[uint8(i)];
                    step.to = _priceState.priceVertices[uint8(i - 1)];
                    (uint160 tradePriceX96, uint128 sizeUsed, bool reached, int256 premiumRateAfterX96) = simulateMove(
                        step
                    );
                    if (reached) {
                        // Reached or crossed
                        _priceStateCache.currentVertexIndex = uint8(i - 1);
                        step.current = step.to;
                    }
                    // prettier-ignore
                    unchecked { step.sizeLeft -= sizeUsed; }
                    tradePriceX96TimesSizeTotal += uint256(tradePriceX96) * sizeUsed;
                    _priceStateCache.premiumRateX96 = uint256(premiumRateAfterX96).toUint128();
                }
            }
            sizeLeft = step.sizeLeft;
        }
    }

    function calculateAX96AndBX96(
        Side _globalSide,
        IPool.PriceVertex memory _from,
        IPool.PriceVertex memory _to
    ) internal pure returns (uint256 aX96, int256 bX96) {
        if (_from.size > _to.size) (_from, _to) = (_to, _from);
        assert(_to.premiumRateX96 >= _from.premiumRateX96);

        unchecked {
            uint128 sizeDelta = _to.size - _from.size;
            aX96 = Math.ceilDiv(_to.premiumRateX96 - _from.premiumRateX96, sizeDelta);

            uint256 numeratorPart1X96 = uint256(_from.premiumRateX96) * _to.size;
            uint256 numeratorPart2X96 = uint256(_to.premiumRateX96) * _from.size;
            if (_globalSide.isShort()) {
                if (numeratorPart1X96 >= numeratorPart2X96)
                    bX96 = ((numeratorPart1X96 - numeratorPart2X96) / sizeDelta).toInt256();
                else bX96 = -((numeratorPart2X96 - numeratorPart1X96) / sizeDelta).toInt256();
            } else {
                if (numeratorPart2X96 >= numeratorPart1X96)
                    bX96 = ((numeratorPart2X96 - numeratorPart1X96) / sizeDelta).toInt256();
                else bX96 = -((numeratorPart1X96 - numeratorPart2X96) / sizeDelta).toInt256();
            }
        }
    }

    function simulateMove(
        MoveStep memory _step
    ) internal pure returns (uint160 tradePriceX96, uint128 sizeUsed, bool reached, int256 premiumRateAfterX96) {
        (reached, sizeUsed) = calculateReachedAndSizeUsed(_step);
        premiumRateAfterX96 = calculatePremiumRateAfterX96(_step, reached, sizeUsed);
        int256 premiumRateBeforeX96 = _step.current.premiumRateX96.toInt256();
        (uint256 tradePriceX96Down, uint256 tradePriceX96Up) = Math.mulDiv2(
            _step.indexPriceX96,
            (_step.improveBalance && _step.side.isLong()) || (!_step.improveBalance && _step.side.isShort())
                ? ((int256(Constants.Q96) << 1) - premiumRateBeforeX96 - premiumRateAfterX96).toUint256()
                : ((int256(Constants.Q96) << 1) + premiumRateBeforeX96 + premiumRateAfterX96).toUint256(),
            Constants.Q96 << 1
        );
        tradePriceX96 = (_step.side.isLong() ? tradePriceX96Up : tradePriceX96Down).toUint160();
    }

    function calculateReachedAndSizeUsed(MoveStep memory _step) internal pure returns (bool reached, uint128 sizeUsed) {
        uint128 sizeCost = _step.improveBalance
            ? _step.current.size - _step.to.size
            : _step.to.size - _step.current.size;
        reached = _step.sizeLeft >= sizeCost;
        sizeUsed = reached ? sizeCost : _step.sizeLeft;
    }

    function calculatePremiumRateAfterX96(
        MoveStep memory _step,
        bool _reached,
        uint128 _sizeUsed
    ) internal pure returns (int256 premiumRateAfterX96) {
        if (_reached) {
            premiumRateAfterX96 = _step.to.premiumRateX96.toInt256();
        } else {
            Side globalSide = _step.improveBalance ? _step.side : _step.side.flip();
            (uint256 aX96, int256 bX96) = calculateAX96AndBX96(globalSide, _step.from, _step.to);
            uint256 sizeAfter = _step.improveBalance ? _step.current.size - _sizeUsed : _step.current.size + _sizeUsed;
            if (globalSide.isLong()) bX96 = -bX96;
            premiumRateAfterX96 = (aX96 * sizeAfter).toInt256() + bX96;
        }
    }

    function calculateMarketPriceX96(
        Side _globalSide,
        Side _side,
        uint160 _indexPriceX96,
        uint128 _premiumRateX96
    ) public pure returns (uint160 marketPriceX96) {
        uint256 premiumRateAfterX96 = _globalSide.isLong()
            ? Constants.Q96 - _premiumRateX96
            : Constants.Q96 + _premiumRateX96;
        marketPriceX96 = _side.isLong()
            ? Math.mulDivUp(_indexPriceX96, premiumRateAfterX96, Constants.Q96).toUint160()
            : Math.mulDiv(_indexPriceX96, premiumRateAfterX96, Constants.Q96).toUint160();
    }
}
