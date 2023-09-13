// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../libraries/PositionUtil.sol";
import "../core/interfaces/IPoolPosition.sol";
import "../core/interfaces/IPoolLiquidityPosition.sol";

contract PositionUtilTest {
    IPoolPosition.GlobalPosition public globalPosition;
    IPoolPosition.PreviousGlobalFundingRate public previousGlobalFundingRate;
    IPoolLiquidityPosition.GlobalLiquidityPosition public globalLiquidityPosition;

    function setGlobalPosition(
        uint128 _longSize,
        uint128 _shortSize,
        int192 _longFundingRateGrowthX96,
        int192 _shortFundingRateGrowthX96
    ) external {
        globalPosition.longSize = _longSize;
        globalPosition.shortSize = _shortSize;
        globalPosition.longFundingRateGrowthX96 = _longFundingRateGrowthX96;
        globalPosition.shortFundingRateGrowthX96 = _shortFundingRateGrowthX96;
    }

    function setPreviousGlobalFundingRate(
        int192 _longFundingRateGrowthX96,
        int192 _shortFundingRateGrowthX96
    ) external {
        previousGlobalFundingRate.longFundingRateGrowthX96 = _longFundingRateGrowthX96;
        previousGlobalFundingRate.shortFundingRateGrowthX96 = _shortFundingRateGrowthX96;
    }

    function setGlobalLiquidityPosition(
        uint128 _liquidity,
        uint128 _netSize,
        uint128 _entryPriceX96,
        Side _side,
        uint256 _realizedProfitGrowthX64
    ) external {
        globalLiquidityPosition.liquidity = _liquidity;
        globalLiquidityPosition.netSize = _netSize;
        globalLiquidityPosition.entryPriceX96 = _entryPriceX96;
        globalLiquidityPosition.side = _side;
        globalLiquidityPosition.realizedProfitGrowthX64 = _realizedProfitGrowthX64;
    }

    function calculateNextEntryPriceX96(
        Side _side,
        uint128 _sizeBefore,
        uint160 _entryPriceBeforeX96,
        uint128 _sizeDelta,
        uint160 _tradePriceX96
    ) external pure returns (uint160 nextEntryPriceX96) {
        return
            PositionUtil.calculateNextEntryPriceX96(
                _side,
                _sizeBefore,
                _entryPriceBeforeX96,
                _sizeDelta,
                _tradePriceX96
            );
    }

    function calculateLiquidity(uint128 _size, uint128 _priceX96) external pure returns (uint128) {
        return PositionUtil.calculateLiquidity(_size, _priceX96);
    }

    function calculateUnrealizedPnL(
        Side _side,
        uint128 _size,
        uint160 _entryPriceX96,
        uint160 _priceX96
    ) external pure returns (int256 unrealizedPnL) {
        return PositionUtil.calculateUnrealizedPnL(_side, _size, _entryPriceX96, _priceX96);
    }

    function getGasCostCalculateUnrealizedPnL(
        Side _side,
        uint128 _size,
        uint160 _entryPriceX96,
        uint160 _priceX96
    ) external view returns (uint256 gasCost) {
        uint256 gasBefore = gasleft();
        PositionUtil.calculateUnrealizedPnL(_side, _size, _entryPriceX96, _priceX96);
        uint256 gasAfter = gasleft();
        gasCost = gasBefore - gasAfter;
    }

    function chooseFundingRateGrowthX96(Side _side) external view returns (int192) {
        return PositionUtil.chooseFundingRateGrowthX96(globalPosition, _side);
    }

    function calculateTradingFee(
        uint128 _size,
        uint160 _tradePriceX96,
        uint32 _tradingFeeRate
    ) external pure returns (uint128 tradingFee) {
        return PositionUtil.calculateTradingFee(_size, _tradePriceX96, _tradingFeeRate);
    }

    function calculateLiquidationFee(
        uint128 _size,
        uint160 _entryPriceX96,
        uint32 _liquidationFeeRate
    ) external pure returns (uint128 liquidationFee) {
        return PositionUtil.calculateLiquidationFee(_size, _entryPriceX96, _liquidationFeeRate);
    }

    function calculateFundingFee(
        int192 _globalFundingRateGrowthX96,
        int192 _positionFundingRateGrowthX96,
        uint128 _positionSize
    ) external pure returns (int256 fundingFee) {
        return
            PositionUtil.calculateFundingFee(_globalFundingRateGrowthX96, _positionFundingRateGrowthX96, _positionSize);
    }

    function calculateMaintenanceMargin(
        uint128 _size,
        uint160 _entryPriceX96,
        uint160 _indexPriceX96,
        uint32 _liquidationFeeRate,
        uint32 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) external pure returns (uint256 maintenanceMargin) {
        return
            PositionUtil.calculateMaintenanceMargin(
                _size,
                _entryPriceX96,
                _indexPriceX96,
                _liquidationFeeRate,
                _tradingFeeRate,
                _liquidationExecutionFee
            );
    }

    function getGasCostCalculateMaintenanceMargin(
        uint128 _liquidity,
        uint128 _size,
        uint160 _indexPriceX96,
        uint32 _liquidationFeeRate,
        uint32 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) external view returns (uint256 gasCost) {
        uint256 gasBefore = gasleft();
        PositionUtil.calculateMaintenanceMargin(
            _liquidity,
            _size,
            _indexPriceX96,
            _liquidationFeeRate,
            _tradingFeeRate,
            _liquidationExecutionFee
        );
        uint256 gasAfter = gasleft();
        gasCost = gasBefore - gasAfter;
    }

    function calculateLiquidationPriceX96(
        IPool.Position memory _positionCache,
        Side _side,
        int256 _fundingFee,
        uint32 _liquidationFeeRate,
        uint32 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) external view returns (uint160 liquidationPriceX96, int256 adjustedFundingFee) {
        return
            PositionUtil.calculateLiquidationPriceX96(
                _positionCache,
                previousGlobalFundingRate,
                _side,
                _fundingFee,
                _liquidationFeeRate,
                _tradingFeeRate,
                _liquidationExecutionFee
            );
    }

    function getGasCostCalculateLiquidationPriceX96(
        IPool.Position memory _positionCache,
        Side _side,
        int256 _fundingFee,
        uint32 _liquidationFeeRate,
        uint32 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) external view returns (uint256 gasCost) {
        uint256 gasBefore = gasleft();
        PositionUtil.calculateLiquidationPriceX96(
            _positionCache,
            previousGlobalFundingRate,
            _side,
            _fundingFee,
            _liquidationFeeRate,
            _tradingFeeRate,
            _liquidationExecutionFee
        );
        uint256 gasAfter = gasleft();
        gasCost = gasBefore - gasAfter;
    }
}
