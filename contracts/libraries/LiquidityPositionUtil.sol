// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./PositionUtil.sol";

/// @notice Utility library for liquidity positions
library LiquidityPositionUtil {
    using SafeCast for *;

    /// @notice Insufficient risk buffer fund
    error InsufficientRiskBufferFund(int256 unrealizedLoss, uint128 requiredRiskBufferFund);
    /// @notice The position has not reached the unlock time
    error UnlockTimeNotReached(uint64 requiredUnlockTime);
    /// @notice Insufficient liquidity
    error InsufficientLiquidity(uint256 liquidity, uint256 requiredLiquidity);
    /// @notice The risk buffer fund is experiencing losses
    error RiskBufferFundLoss();

    /// @notice Calculate the unrealized loss of the net position held by all LPs
    /// @param _side The side of the position (Long or Short)
    /// @param _netSize The size of the net position held by all LPs
    /// @param _entryPriceX96 The entry price of the net position held by all LPs, as a Q64.96
    /// @param _indexPriceX96 The index price, as a Q64.96
    /// @param _riskBufferFund The risk buffer fund
    /// @return unrealizedLoss The unrealized loss of the net position held by all LPs
    function calculateUnrealizedLoss(
        Side _side,
        uint128 _netSize,
        uint160 _entryPriceX96,
        uint160 _indexPriceX96,
        int256 _riskBufferFund
    ) internal pure returns (uint256 unrealizedLoss) {
        int256 unrealizedPnL = PositionUtil.calculateUnrealizedPnL(_side, _netSize, _entryPriceX96, _indexPriceX96);
        unrealizedPnL += _riskBufferFund;
        // Even if `unrealizedPnL` is `type(int256).min`, the unsafe type conversion
        // will still produce the correct result
        // prettier-ignore
        unchecked { return unrealizedPnL >= 0 ? 0 : uint256(-unrealizedPnL); }
    }

    /// @notice Update the global unrealized loss metrics
    /// @param _metrics The current metrics
    /// @param _currentUnrealizedLoss The current unrealized loss of the net position held by all LPs,
    /// see `calculateUnrealizedLoss`
    /// @param _currentTimestamp The current timestamp
    /// @param _liquidityDelta The change in liquidity, positive for increase, negative for decrease
    /// @param _liquidityDeltaEntryTime The entry time of the liquidity delta
    /// @param _liquidityDeltaEntryUnrealizedLoss The snapshot of unrealized loss
    /// at the entry time of the liquidity delta
    function updateUnrealizedLossMetrics(
        IPoolLiquidityPosition.GlobalUnrealizedLossMetrics storage _metrics,
        uint256 _currentUnrealizedLoss,
        uint64 _currentTimestamp,
        int256 _liquidityDelta,
        uint64 _liquidityDeltaEntryTime,
        uint256 _liquidityDeltaEntryUnrealizedLoss
    ) internal {
        if (_currentUnrealizedLoss == 0) {
            _metrics.lastZeroLossTime = _currentTimestamp;
            _metrics.liquidity = 0;
            _metrics.liquidityTimesUnrealizedLoss = 0;
        } else if (_liquidityDeltaEntryTime > _metrics.lastZeroLossTime && _liquidityDelta != 0) {
            if (_liquidityDelta > 0) {
                // The liquidityDelta is at most type(uint128).max, so liquidityDelta will not overflow here
                _metrics.liquidity += uint128(uint256(_liquidityDelta));
                _metrics.liquidityTimesUnrealizedLoss += _liquidityDeltaEntryUnrealizedLoss * uint256(_liquidityDelta);
            } else {
                unchecked {
                    // The liquidityDelta is at most -type(uint128).max, so -liquidityDelta will not overflow here
                    uint256 liquidityDeltaCast = uint256(-_liquidityDelta);
                    _metrics.liquidity -= uint128(liquidityDeltaCast);
                    _metrics.liquidityTimesUnrealizedLoss -= _liquidityDeltaEntryUnrealizedLoss * liquidityDeltaCast;
                }
            }
        }
    }

    /// @notice Calculate the realized profit of the specified LP position
    function calculateRealizedProfit(
        IPoolLiquidityPosition.LiquidityPosition memory _positionCache,
        IPoolLiquidityPosition.GlobalLiquidityPosition memory _globalPositionCache
    ) internal pure returns (uint256 realizedProfit) {
        uint256 deltaX64;
        unchecked {
            deltaX64 = _globalPositionCache.realizedProfitGrowthX64 - _positionCache.entryRealizedProfitGrowthX64;
        }
        realizedProfit = Math.mulDiv(deltaX64, _positionCache.liquidity, Constants.Q64);
    }

    /// @notice Calculate the unrealized loss for the specified LP position
    /// @param _globalLiquidity The total liquidity of all LPs
    /// @param _unrealizedLoss The current unrealized loss of the net position held by all LPs,
    /// see `calculateUnrealizedLoss`
    /// @return positionUnrealizedLoss The unrealized loss incurred by the position at the time of closing
    function calculatePositionUnrealizedLoss(
        IPoolLiquidityPosition.LiquidityPosition memory _positionCache,
        IPoolLiquidityPosition.GlobalUnrealizedLossMetrics memory _metricsCache,
        uint128 _globalLiquidity,
        uint256 _unrealizedLoss
    ) internal pure returns (uint128 positionUnrealizedLoss) {
        unchecked {
            if (_positionCache.entryTime > _metricsCache.lastZeroLossTime) {
                if (_unrealizedLoss > _positionCache.entryUnrealizedLoss)
                    positionUnrealizedLoss = Math
                        .mulDivUp(
                            _unrealizedLoss - _positionCache.entryUnrealizedLoss,
                            _positionCache.liquidity,
                            _globalLiquidity
                        )
                        .toUint128();
            } else {
                uint256 wamUnrealizedLoss = calculateWAMUnrealizedLoss(_metricsCache);
                uint128 liquidityDelta = _globalLiquidity - _metricsCache.liquidity;
                if (_unrealizedLoss > wamUnrealizedLoss) {
                    positionUnrealizedLoss = Math
                        .mulDivUp(_unrealizedLoss - wamUnrealizedLoss, _positionCache.liquidity, _globalLiquidity)
                        .toUint128();
                    positionUnrealizedLoss += Math
                        .mulDivUp(wamUnrealizedLoss, _positionCache.liquidity, liquidityDelta)
                        .toUint128();
                } else {
                    positionUnrealizedLoss = Math
                        .mulDivUp(_unrealizedLoss, _positionCache.liquidity, liquidityDelta)
                        .toUint128();
                }
            }
        }
    }

    /// @notice Calculate the weighted average mean (WAM) component of the unrealized loss
    /// for the specified LP position
    function calculateWAMUnrealizedLoss(
        IPoolLiquidityPosition.GlobalUnrealizedLossMetrics memory _metricsCache
    ) internal pure returns (uint256 wamUnrealizedLoss) {
        if (_metricsCache.liquidity > 0)
            wamUnrealizedLoss = Math.ceilDiv(_metricsCache.liquidityTimesUnrealizedLoss, _metricsCache.liquidity);
    }

    /// @notice Calculate the realized PnL and next entry price of the LP net position
    /// @param _side The side of the trader's position adjustment, long for increasing long position
    /// or decreasing short position, short for increasing short position or decreasing long position
    /// @param _tradePriceX96 The trade price of the trader's position adjustment, as a Q64.96
    /// @param _sizeDelta The size adjustment of the trader's position
    /// @return realizedPnL The realized PnL of the LP net position
    /// @param entryPriceAfterX96 The next entry price of the LP net position, as a Q64.96
    function calculateRealizedPnLAndNextEntryPriceX96(
        IPoolLiquidityPosition.GlobalLiquidityPosition memory _positionCache,
        Side _side,
        uint160 _tradePriceX96,
        uint128 _sizeDelta
    ) internal pure returns (int256 realizedPnL, uint160 entryPriceAfterX96) {
        entryPriceAfterX96 = _positionCache.entryPriceX96;

        unchecked {
            uint256 netSizeAfter = uint256(_positionCache.netSize) + _positionCache.liquidationBufferNetSize;
            if (netSizeAfter > 0 && _side == _positionCache.side) {
                uint128 sizeUsed = _sizeDelta > netSizeAfter ? uint128(netSizeAfter) : _sizeDelta;
                realizedPnL = PositionUtil.calculateUnrealizedPnL(
                    _side,
                    sizeUsed,
                    _positionCache.entryPriceX96,
                    _tradePriceX96
                );

                _sizeDelta -= sizeUsed;
                netSizeAfter -= sizeUsed;

                if (netSizeAfter == 0) entryPriceAfterX96 = 0;
            }

            if (_sizeDelta > 0)
                entryPriceAfterX96 = PositionUtil.calculateNextEntryPriceX96(
                    _side.flip(),
                    netSizeAfter.toUint128(),
                    entryPriceAfterX96,
                    _sizeDelta,
                    _tradePriceX96
                );
        }
    }

    /// @notice `Gov` uses the risk buffer fund
    /// @return riskBufferFundAfter The total risk buffer fund after the use
    function govUseRiskBufferFund(
        IPoolLiquidityPosition.GlobalLiquidityPosition storage _position,
        IPoolLiquidityPosition.GlobalRiskBufferFund storage _riskBufferFund,
        uint160 _indexPriceX96,
        uint128 _riskBufferFundDelta
    ) public returns (int256 riskBufferFundAfter) {
        // Calculate the unrealized loss of the net position held by all LPs
        int256 unrealizedLoss = PositionUtil.calculateUnrealizedPnL(
            _position.side,
            _position.netSize + _position.liquidationBufferNetSize,
            _position.entryPriceX96,
            _indexPriceX96
        );
        unrealizedLoss = unrealizedLoss >= 0 ? int256(0) : -unrealizedLoss;

        riskBufferFundAfter = _riskBufferFund.riskBufferFund - int256(uint256(_riskBufferFundDelta));
        if (riskBufferFundAfter - unrealizedLoss - _riskBufferFund.liquidity.toInt256() < 0)
            revert InsufficientRiskBufferFund(unrealizedLoss, _riskBufferFundDelta);

        _riskBufferFund.riskBufferFund = riskBufferFundAfter;
    }

    /// @notice Increase the liquidity of a risk buffer fund position
    /// @return positionLiquidityAfter The total liquidity of the position after the increase
    /// @return unlockTimeAfter The unlock time of the position after the increase
    /// @return riskBufferFundAfter The total risk buffer fund after the increase
    function increaseRiskBufferFundPosition(
        IPoolLiquidityPosition.GlobalRiskBufferFund storage _riskBufferFund,
        mapping(address => IPoolLiquidityPosition.RiskBufferFundPosition) storage _positions,
        address _account,
        uint128 _liquidityDelta
    ) public returns (uint128 positionLiquidityAfter, uint64 unlockTimeAfter, int256 riskBufferFundAfter) {
        _riskBufferFund.liquidity += _liquidityDelta;

        IPoolLiquidityPosition.RiskBufferFundPosition storage position = _positions[_account];
        positionLiquidityAfter = position.liquidity + _liquidityDelta;
        unlockTimeAfter = block.timestamp.toUint64() + Constants.RISK_BUFFER_FUND_LOCK_PERIOD;

        position.liquidity = positionLiquidityAfter;
        position.unlockTime = unlockTimeAfter;

        riskBufferFundAfter = _riskBufferFund.riskBufferFund + _liquidityDelta.toInt256();
        _riskBufferFund.riskBufferFund = riskBufferFundAfter;
    }

    /// @notice Decrease the liquidity of a risk buffer fund position
    /// @return positionLiquidityAfter The total liquidity of the position after the decrease
    /// @return riskBufferFundAfter The total risk buffer fund after the decrease
    function decreaseRiskBufferFundPosition(
        IPoolLiquidityPosition.GlobalLiquidityPosition storage _globalPosition,
        IPoolLiquidityPosition.GlobalRiskBufferFund storage _riskBufferFund,
        mapping(address => IPoolLiquidityPosition.RiskBufferFundPosition) storage _positions,
        uint160 _indexPriceX96,
        address _account,
        uint128 _liquidityDelta
    ) public returns (uint128 positionLiquidityAfter, int256 riskBufferFundAfter) {
        IPoolLiquidityPosition.RiskBufferFundPosition memory positionCache = _positions[_account];

        if (positionCache.unlockTime >= block.timestamp) revert UnlockTimeNotReached(positionCache.unlockTime);

        if (positionCache.liquidity < _liquidityDelta)
            revert InsufficientLiquidity(positionCache.liquidity, _liquidityDelta);

        int256 unrealizedPnL = PositionUtil.calculateUnrealizedPnL(
            _globalPosition.side,
            _globalPosition.netSize + _globalPosition.liquidationBufferNetSize,
            _globalPosition.entryPriceX96,
            _indexPriceX96
        );
        if (_riskBufferFund.riskBufferFund + unrealizedPnL - _riskBufferFund.liquidity.toInt256() < 0)
            revert RiskBufferFundLoss();

        unchecked {
            positionLiquidityAfter = positionCache.liquidity - _liquidityDelta;

            if (positionLiquidityAfter == 0) delete _positions[_account];
            else _positions[_account].liquidity = positionLiquidityAfter;

            _riskBufferFund.liquidity -= _liquidityDelta;
        }

        riskBufferFundAfter = _riskBufferFund.riskBufferFund - _liquidityDelta.toInt256();
        _riskBufferFund.riskBufferFund = riskBufferFundAfter;
    }
}
