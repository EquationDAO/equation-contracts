// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./PositionUtil.sol";

/// @notice Utility library for calculating funding rates
library FundingRateUtil {
    using SafeCast for *;

    /// @notice Emitted when the funding rate sample is adjusted
    /// @param sampleCountAfter The adjusted `sampleCount`
    /// @param cumulativePremiumRateAfterX96 The adjusted `cumulativePremiumRateX96`, as a Q80.96
    event GlobalFundingRateSampleAdjusted(uint16 sampleCountAfter, int176 cumulativePremiumRateAfterX96);

    /// @notice Emitted when the risk buffer fund is changed
    event GlobalRiskBufferFundChanged(int256 riskBufferFundAfter);

    /// @notice Sample the premium rate
    /// @param _sample The global funding rate sample
    /// @param _position The global liquidity position
    /// @param _priceState The global price state
    /// @param _interestRate The interest rate used to calculate the funding rate,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @param _currentTimestamp The current timestamp
    /// @return shouldAdjustFundingRate Whether to adjust the funding rate
    /// @return fundingRateDeltaX96 The delta of the funding rate, as a Q160.96
    function samplePremiumRate(
        IPoolPosition.GlobalFundingRateSample storage _sample,
        IPoolLiquidityPosition.GlobalLiquidityPosition storage _position,
        IPool.PriceState storage _priceState,
        uint32 _interestRate,
        uint64 _currentTimestamp
    ) public returns (bool shouldAdjustFundingRate, int256 fundingRateDeltaX96) {
        uint64 lastAdjustFundingRateTime = _sample.lastAdjustFundingRateTime;
        uint64 maxSamplingTime = lastAdjustFundingRateTime + Constants.ADJUST_FUNDING_RATE_INTERVAL;

        // At most 1 hour of premium rate sampling
        if (maxSamplingTime < _currentTimestamp) _currentTimestamp = maxSamplingTime;

        unchecked {
            uint64 lastSamplingTime = lastAdjustFundingRateTime +
                _sample.sampleCount *
                Constants.SAMPLE_PREMIUM_RATE_INTERVAL;

            uint16 timeDelta = uint16(_currentTimestamp - lastSamplingTime);
            if (timeDelta < Constants.SAMPLE_PREMIUM_RATE_INTERVAL) return (false, 0);

            uint128 premiumRateX96 = _position.liquidity > _priceState.maxPriceImpactLiquidity
                ? uint128(
                    Math.mulDivUp(_priceState.premiumRateX96, _priceState.maxPriceImpactLiquidity, _position.liquidity)
                )
                : _priceState.premiumRateX96;

            (shouldAdjustFundingRate, fundingRateDeltaX96) = _samplePremiumRate(
                _sample,
                _position.side,
                premiumRateX96,
                _interestRate,
                maxSamplingTime,
                timeDelta
            );

            emit GlobalFundingRateSampleAdjusted(_sample.sampleCount, _sample.cumulativePremiumRateX96);
        }
    }

    /// @notice Calculate the funding rate growth
    /// @dev If the opposite position is 0, the funding fee will be accumulated into the risk buffer fund
    /// @param _globalRiskBufferFund The global risk buffer fund
    /// @param _globalPositionCache The global position cache
    /// @param _fundingRateDeltaX96 The delta of the funding rate, as a Q160.96
    /// @param _maxFundingRate The maximum funding rate, denominated in ten thousandths of a bip (i.e. 1e-8).
    /// If the funding rate exceeds the maximum funding rate, the funding rate will be clamped to the maximum funding
    /// rate. If the funding rate is less than the negative value of the maximum funding rate, the funding rate will
    /// be clamped to the negative value of the maximum funding rate
    /// @param _indexPriceX96 The index price, as a Q64.96
    /// @return clampedFundingRateDeltaX96 The clamped delta of the funding rate, as a Q160.96
    /// @return longFundingRateGrowthAfterX96 The long funding rate growth after the funding rate is updated, as
    /// a Q96.96
    /// @return shortFundingRateGrowthAfterX96 The short funding rate growth after the funding rate is updated, as
    /// a Q96.96
    function calculateFundingRateGrowthX96(
        IPoolLiquidityPosition.GlobalRiskBufferFund storage _globalRiskBufferFund,
        IPoolPosition.GlobalPosition memory _globalPositionCache,
        int256 _fundingRateDeltaX96,
        uint32 _maxFundingRate,
        uint160 _indexPriceX96
    )
        public
        returns (
            int256 clampedFundingRateDeltaX96,
            int192 longFundingRateGrowthAfterX96,
            int192 shortFundingRateGrowthAfterX96
        )
    {
        // The funding rate is clamped to the maximum funding rate
        int256 maxFundingRateX96 = _calculateMaxFundingRateX96(_maxFundingRate);
        if (_fundingRateDeltaX96 > maxFundingRateX96) clampedFundingRateDeltaX96 = maxFundingRateX96;
        else if (_fundingRateDeltaX96 < -maxFundingRateX96) clampedFundingRateDeltaX96 = -maxFundingRateX96;
        else clampedFundingRateDeltaX96 = _fundingRateDeltaX96;

        (uint128 paidSize, uint128 receivedSize, uint256 clampedFundingRateDeltaAbsX96) = clampedFundingRateDeltaX96 >=
            0
            ? (_globalPositionCache.longSize, _globalPositionCache.shortSize, uint256(clampedFundingRateDeltaX96))
            : (_globalPositionCache.shortSize, _globalPositionCache.longSize, uint256(-clampedFundingRateDeltaX96));

        // paidFundingRateGrowthDelta = (paidSize * price * fundingRate) / paidSize = price * fundingRate
        int192 paidFundingRateGrowthDeltaX96 = Math
            .mulDivUp(_indexPriceX96, clampedFundingRateDeltaAbsX96, Constants.Q96)
            .toInt256()
            .toInt192();

        int192 receivedFundingRateGrowthDeltaX96;
        if (paidFundingRateGrowthDeltaX96 > 0) {
            if (receivedSize > 0) {
                // receivedFundingRateGrowthDelta = (paidSize * price * fundingRate) / receivedSize
                //                                = (paidSize * paidFundingRateGrowthDelta) / receivedSize
                receivedFundingRateGrowthDeltaX96 = Math
                    .mulDiv(paidSize, uint192(paidFundingRateGrowthDeltaX96), receivedSize)
                    .toInt256()
                    .toInt192();
            } else {
                // riskBufferFundDelta = paidSize * price * fundingRate
                int256 riskBufferFundDelta = int256(
                    Math.mulDiv(paidSize, uint192(paidFundingRateGrowthDeltaX96), Constants.Q96)
                );
                int256 riskBufferFundAfter = _globalRiskBufferFund.riskBufferFund + riskBufferFundDelta;
                _globalRiskBufferFund.riskBufferFund = riskBufferFundAfter;
                emit GlobalRiskBufferFundChanged(riskBufferFundAfter);
            }
        }

        longFundingRateGrowthAfterX96 = _globalPositionCache.longFundingRateGrowthX96;
        shortFundingRateGrowthAfterX96 = _globalPositionCache.shortFundingRateGrowthX96;
        if (clampedFundingRateDeltaX96 >= 0) {
            longFundingRateGrowthAfterX96 -= paidFundingRateGrowthDeltaX96;
            shortFundingRateGrowthAfterX96 += receivedFundingRateGrowthDeltaX96;
        } else {
            shortFundingRateGrowthAfterX96 -= paidFundingRateGrowthDeltaX96;
            longFundingRateGrowthAfterX96 += receivedFundingRateGrowthDeltaX96;
        }
    }

    function _calculateMaxFundingRateX96(uint32 _maxFundingRate) private pure returns (int256 maxFundingRateX96) {
        return int256(Math.mulDivUp(_maxFundingRate, Constants.Q96, Constants.BASIS_POINTS_DIVISOR));
    }

    function _samplePremiumRate(
        IPoolPosition.GlobalFundingRateSample storage _sample,
        Side _side,
        uint128 _premiumRateX96,
        uint32 _interestRate,
        uint64 _maxSamplingTime,
        uint16 _timeDelta
    ) internal returns (bool shouldAdjustFundingRate, int256 fundingRateDeltaX96) {
        // When the net position held by LP is long, the premium rate is negative, otherwise it is positive
        int176 premiumRateX96 = _side.isLong() ? -int176(uint176(_premiumRateX96)) : int176(uint176(_premiumRateX96));

        int176 cumulativePremiumRateX96;
        unchecked {
            // The number of samples is limited to a maximum of 720, so there will be no overflow here
            uint16 sampleCountDelta = _timeDelta / Constants.SAMPLE_PREMIUM_RATE_INTERVAL;
            uint16 sampleCountAfter = _sample.sampleCount + sampleCountDelta;
            // formula: cumulativePremiumRateDeltaX96 = premiumRateX96 * (n + (n+1) + (n+2) + ... + (n+m))
            // Since (n + (n+1) + (n+2) + ... + (n+m)) is at most equal to 259560, it can be stored using int24.
            // Additionally, since the type of premiumRateX96 is int136, storing the result of
            // type(int136).max * type(int24).max in int176 will not overflow
            int176 cumulativePremiumRateDeltaX96 = premiumRateX96 *
                int24(((uint24(_sample.sampleCount) + 1 + sampleCountAfter) * sampleCountDelta) >> 1);
            cumulativePremiumRateX96 = _sample.cumulativePremiumRateX96 + cumulativePremiumRateDeltaX96;

            // If the sample count is less than the required sample count, there is no need to update the funding rate
            if (sampleCountAfter < Constants.REQUIRED_SAMPLE_COUNT) {
                _sample.sampleCount = sampleCountAfter;
                _sample.cumulativePremiumRateX96 = cumulativePremiumRateX96;
                return (false, 0);
            }
        }

        int256 premiumRateAvgX96 = cumulativePremiumRateX96 >= 0
            ? int256(Math.ceilDiv(uint256(int256(cumulativePremiumRateX96)), Constants.PREMIUM_RATE_AVG_DENOMINATOR))
            : -int256(Math.ceilDiv(uint256(-int256(cumulativePremiumRateX96)), Constants.PREMIUM_RATE_AVG_DENOMINATOR));

        fundingRateDeltaX96 = premiumRateAvgX96 + _clamp(premiumRateAvgX96, _interestRate);

        // Update the sample data
        _sample.lastAdjustFundingRateTime = _maxSamplingTime;
        _sample.sampleCount = 0;
        _sample.cumulativePremiumRateX96 = 0;

        return (true, fundingRateDeltaX96);
    }

    function _clamp(int256 _premiumRateAvgX96, uint32 _interestRate) private pure returns (int256) {
        int256 interestRateX96 = int256(Math.mulDivUp(_interestRate, Constants.Q96, Constants.BASIS_POINTS_DIVISOR));
        int256 rateDeltaX96 = interestRateX96 - _premiumRateAvgX96;
        if (rateDeltaX96 > Constants.PREMIUM_RATE_CLAMP_BOUNDARY_X96) return Constants.PREMIUM_RATE_CLAMP_BOUNDARY_X96;
        else if (rateDeltaX96 < -Constants.PREMIUM_RATE_CLAMP_BOUNDARY_X96)
            return -Constants.PREMIUM_RATE_CLAMP_BOUNDARY_X96;
        else return rateDeltaX96;
    }
}
