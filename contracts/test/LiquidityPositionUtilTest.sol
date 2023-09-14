// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../libraries/LiquidityPositionUtil.sol";
import "../core/interfaces/IPoolLiquidityPosition.sol";

contract LiquidityPositionUtilTest {
    IPoolLiquidityPosition.GlobalUnrealizedLossMetrics public metrics;
    IPoolLiquidityPosition.GlobalLiquidityPosition public globalLiquidityPosition;
    IPoolLiquidityPosition.GlobalRiskBufferFund public globalRiskBufferFund;
    mapping(address => IPoolLiquidityPosition.RiskBufferFundPosition) public riskBufferFundPositions;

    uint128 public positionLiquidityAfter;
    uint64 public unlockTimeAfter;
    int256 public riskBufferFundAfter;

    function setGlobalLiquidityPosition(
        uint128 _liquidity,
        uint128 _netSize,
        uint160 _entryPriceX96,
        Side _side,
        uint256 _realizedProfitGrowthX64
    ) external {
        globalLiquidityPosition.side = _side;
        globalLiquidityPosition.liquidity = _liquidity;
        globalLiquidityPosition.netSize = _netSize;
        globalLiquidityPosition.entryPriceX96 = _entryPriceX96;
        globalLiquidityPosition.realizedProfitGrowthX64 = _realizedProfitGrowthX64;
    }

    function setGlobalRiskBufferFund(int256 _riskBufferFund, uint256 _liquidity) external {
        globalRiskBufferFund.riskBufferFund = _riskBufferFund;
        globalRiskBufferFund.liquidity = _liquidity;
    }

    function setRiskBufferFundPosition(address _owner, uint128 _liquidity, uint64 _unlockTime) external {
        riskBufferFundPositions[_owner] = IPoolLiquidityPosition.RiskBufferFundPosition({
            liquidity: _liquidity,
            unlockTime: _unlockTime
        });
    }

    function calculateUnrealizedLoss(
        Side _side,
        uint128 _netSize,
        uint128 _netLiquidity,
        uint160 _indexPriceX96,
        int256 _riskBufferFund
    ) external pure returns (uint256) {
        return
            LiquidityPositionUtil.calculateUnrealizedLoss(
                _side,
                _netSize,
                _netLiquidity,
                _indexPriceX96,
                _riskBufferFund
            );
    }

    function deleteMetrics() external {
        delete metrics;
    }

    function updateUnrealizedLossMetrics(
        uint256 _currentUnrealizedLoss,
        uint64 _currentTimestamp,
        int256 _liquidityDelta,
        uint64 _liquidityDeltaEntryTime,
        uint256 _liquidityDeltaEntryUnrealizedLoss
    ) external {
        LiquidityPositionUtil.updateUnrealizedLossMetrics(
            metrics,
            _currentUnrealizedLoss,
            _currentTimestamp,
            _liquidityDelta,
            _liquidityDeltaEntryTime,
            _liquidityDeltaEntryUnrealizedLoss
        );
    }

    function calculateRealizedProfit(
        IPoolLiquidityPosition.LiquidityPosition memory _positionCache,
        IPoolLiquidityPosition.GlobalLiquidityPosition memory _globalPositionCache
    ) external pure returns (uint256) {
        return LiquidityPositionUtil.calculateRealizedProfit(_positionCache, _globalPositionCache);
    }

    function calculatePositionUnrealizedLoss(
        IPoolLiquidityPosition.LiquidityPosition memory _positionCache,
        IPoolLiquidityPosition.GlobalUnrealizedLossMetrics memory _metricsCache,
        uint128 _globalLiquidity,
        uint256 _unrealizedLoss
    ) external pure returns (uint128 positionUnrealizedLoss) {
        return
            LiquidityPositionUtil.calculatePositionUnrealizedLoss(
                _positionCache,
                _metricsCache,
                _globalLiquidity,
                _unrealizedLoss
            );
    }

    function getGasCostCalculatePositionUnrealizedLoss(
        IPoolLiquidityPosition.LiquidityPosition memory _positionCache,
        IPoolLiquidityPosition.GlobalUnrealizedLossMetrics memory _metricsCache,
        uint128 _globalLiquidity,
        uint256 _unrealizedLoss
    ) external view returns (uint256 gasCost) {
        uint256 gasBefore = gasleft();
        LiquidityPositionUtil.calculatePositionUnrealizedLoss(
            _positionCache,
            _metricsCache,
            _globalLiquidity,
            _unrealizedLoss
        );
        uint256 gasAfter = gasleft();
        gasCost = gasBefore - gasAfter;
    }

    function calculateWAMUnrealizedLoss(
        IPoolLiquidityPosition.GlobalUnrealizedLossMetrics memory _metricsCache
    ) external pure returns (uint256 wamUnrealizedLoss) {
        return LiquidityPositionUtil.calculateWAMUnrealizedLoss(_metricsCache);
    }

    function calculateRealizedPnLAndNextEntryPriceX96(
        IPoolLiquidityPosition.GlobalLiquidityPosition memory _positionCache,
        Side _side,
        uint160 _tradePriceX96,
        uint128 _sizeDelta
    ) external pure returns (int256 realizedPnL, uint160 entryPriceAfterX96) {
        return
            LiquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                _positionCache,
                _side,
                _tradePriceX96,
                _sizeDelta
            );
    }

    function getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
        IPoolLiquidityPosition.GlobalLiquidityPosition memory _positionCache,
        Side _side,
        uint160 _tradePriceX96,
        uint128 _sizeDelta
    ) external view returns (uint256 gasCost) {
        uint256 gasBefore = gasleft();
        LiquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
            _positionCache,
            _side,
            _tradePriceX96,
            _sizeDelta
        );
        uint256 gasAfter = gasleft();
        gasCost = gasBefore - gasAfter;
    }

    function govUseRiskBufferFund(uint160 _indexPriceX96, uint128 _riskBufferFundDelta) external {
        riskBufferFundAfter = LiquidityPositionUtil.govUseRiskBufferFund(
            globalLiquidityPosition,
            globalRiskBufferFund,
            _indexPriceX96,
            _riskBufferFundDelta
        );
    }

    function increaseRiskBufferFundPosition(address _account, uint128 _liquidityDelta) external {
        (positionLiquidityAfter, unlockTimeAfter, riskBufferFundAfter) = LiquidityPositionUtil
            .increaseRiskBufferFundPosition(globalRiskBufferFund, riskBufferFundPositions, _account, _liquidityDelta);
    }

    function getGasCostIncreaseRiskBufferFundPosition(
        address _account,
        uint128 _liquidityDelta
    ) external returns (uint256 gasCost) {
        uint256 gasBefore = gasleft();
        LiquidityPositionUtil.increaseRiskBufferFundPosition(
            globalRiskBufferFund,
            riskBufferFundPositions,
            _account,
            _liquidityDelta
        );
        uint256 gasAfter = gasleft();
        gasCost = gasBefore - gasAfter;
    }

    function decreaseRiskBufferFundPosition(
        uint160 _indexPriceX96,
        address _account,
        uint128 _liquidityDelta
    ) external {
        (positionLiquidityAfter, riskBufferFundAfter) = LiquidityPositionUtil.decreaseRiskBufferFundPosition(
            globalLiquidityPosition,
            globalRiskBufferFund,
            riskBufferFundPositions,
            _indexPriceX96,
            _account,
            _liquidityDelta
        );
    }

    function getGasCostDecreaseRiskBufferFundPosition(
        uint160 _indexPriceX96,
        address _account,
        uint128 _liquidityDelta
    ) external returns (uint256 gasCost) {
        uint256 gasBefore = gasleft();
        LiquidityPositionUtil.decreaseRiskBufferFundPosition(
            globalLiquidityPosition,
            globalRiskBufferFund,
            riskBufferFundPositions,
            _indexPriceX96,
            _account,
            _liquidityDelta
        );
        uint256 gasAfter = gasleft();
        gasCost = gasBefore - gasAfter;
    }
}
