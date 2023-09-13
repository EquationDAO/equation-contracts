// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../libraries/FundingRateUtil.sol";
import "../core/interfaces/IPoolPosition.sol";
import "../core/interfaces/IPoolLiquidityPosition.sol";

contract FundingRateUtilTest {
    IPoolLiquidityPosition.GlobalLiquidityPosition public position;
    IPoolLiquidityPosition.GlobalRiskBufferFund public globalRiskBufferFund;
    IPoolPosition.GlobalFundingRateSample public sample;
    IPool.PriceState public priceState;

    uint256 public gasUsed;
    bool public shouldAdjustFundingRate;
    int256 public fundingRateDeltaX96;

    int256 public clampedFundingRateDeltaX96;
    int192 public longFundingRateGrowthAfterX96;
    int192 public shortFundingRateGrowthAfterX96;

    function updatePosition(Side _side, uint128 _netSize, uint160 _entryPriceX96, uint128 _liquidity) external {
        position.side = _side;
        position.netSize = _netSize;
        position.entryPriceX96 = _entryPriceX96;
        position.liquidity = _liquidity;
    }

    function updateGlobalRiskBufferFund(int256 _riskBufferFund, uint256 _liquidity) external {
        globalRiskBufferFund.riskBufferFund = _riskBufferFund;
        globalRiskBufferFund.liquidity = _liquidity;
    }

    function updateSample(
        uint64 _lastAdjustFundingRateTime,
        uint16 _sampleCount,
        int176 _cumulativePremiumRateX96
    ) external {
        sample.lastAdjustFundingRateTime = _lastAdjustFundingRateTime;
        sample.sampleCount = _sampleCount;
        sample.cumulativePremiumRateX96 = _cumulativePremiumRateX96;
    }

    function updatePriceState(uint128 _maxPriceImpactLiquidity, uint128 _premiumRateX96) external {
        priceState.maxPriceImpactLiquidity = _maxPriceImpactLiquidity;
        priceState.premiumRateX96 = _premiumRateX96;
    }

    function samplePremiumRate(uint32 _interestRate, uint64 _currentTimestamp) external {
        uint256 gasBefore = gasleft();
        (bool _shouldAdjustFundingRate, int256 _fundingRateDeltaX96) = FundingRateUtil.samplePremiumRate(
            sample,
            position,
            priceState,
            _interestRate,
            _currentTimestamp
        );
        gasUsed = gasBefore - gasleft();
        shouldAdjustFundingRate = _shouldAdjustFundingRate;
        fundingRateDeltaX96 = _fundingRateDeltaX96;
    }

    function calculateFundingRateGrowthX96(
        IPoolPosition.GlobalPosition memory _globalPositionCache,
        int256 _fundingRateDeltaX96,
        uint32 _maxFundingRate,
        uint160 _indexPriceX96
    ) external {
        uint256 gasBefore = gasleft();
        (
            int256 _clampedFundingRateDeltaX96,
            int192 _longFundingRateGrowthAfterX96,
            int192 _shortFundingRateGrowthAfterX96
        ) = FundingRateUtil.calculateFundingRateGrowthX96(
                globalRiskBufferFund,
                _globalPositionCache,
                _fundingRateDeltaX96,
                _maxFundingRate,
                _indexPriceX96
            );
        gasUsed = gasBefore - gasleft();
        clampedFundingRateDeltaX96 = _clampedFundingRateDeltaX96;
        longFundingRateGrowthAfterX96 = _longFundingRateGrowthAfterX96;
        shortFundingRateGrowthAfterX96 = _shortFundingRateGrowthAfterX96;
    }

    function _samplePremiumRate(
        Side _side,
        uint128 _premiumRateX96,
        uint32 _interestRate,
        uint64 _maxSamplingTime,
        uint16 _timeDelta
    ) external {
        (bool _shouldAdjustFundingRate, int256 _fundingRateDeltaX96) = FundingRateUtil._samplePremiumRate(
            sample,
            _side,
            _premiumRateX96,
            _interestRate,
            _maxSamplingTime,
            _timeDelta
        );
        shouldAdjustFundingRate = _shouldAdjustFundingRate;
        fundingRateDeltaX96 = _fundingRateDeltaX96;
    }
}
