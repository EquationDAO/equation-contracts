// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {M as Math} from "./Math.sol";
import "./Constants.sol";
import "./SafeCast.sol";
import "../core/interfaces/IPool.sol";
import {Side} from "../types/Side.sol";

/// @notice Utility library for trader positions
library PositionUtil {
    using SafeCast for *;

    /// @notice Calculate the next entry price of a position
    /// @param _side The side of the position (Long or Short)
    /// @param _sizeBefore The size of the position before the trade
    /// @param _entryPriceBeforeX96 The entry price of the position before the trade, as a Q64.96
    /// @param _sizeDelta The size of the trade
    /// @param _tradePriceX96 The price of the trade, as a Q64.96
    /// @return nextEntryPriceX96 The entry price of the position after the trade, as a Q64.96
    function calculateNextEntryPriceX96(
        Side _side,
        uint128 _sizeBefore,
        uint160 _entryPriceBeforeX96,
        uint128 _sizeDelta,
        uint160 _tradePriceX96
    ) internal pure returns (uint160 nextEntryPriceX96) {
        if ((_sizeBefore | _sizeDelta) == 0) nextEntryPriceX96 = 0;
        else if (_sizeBefore == 0) nextEntryPriceX96 = _tradePriceX96;
        else if (_sizeDelta == 0) nextEntryPriceX96 = _entryPriceBeforeX96;
        else {
            uint256 liquidityAfterX96 = uint256(_sizeBefore) * _entryPriceBeforeX96;
            liquidityAfterX96 += uint256(_sizeDelta) * _tradePriceX96;
            unchecked {
                uint256 sizeAfter = uint256(_sizeBefore) + _sizeDelta;
                nextEntryPriceX96 = (
                    _side.isLong() ? Math.ceilDiv(liquidityAfterX96, sizeAfter) : liquidityAfterX96 / sizeAfter
                ).toUint160();
            }
        }
    }

    /// @notice Calculate the liquidity (value) of a position
    /// @param _size The size of the position
    /// @param _priceX96 The trade price, as a Q64.96
    /// @return liquidity The liquidity (value) of the position
    function calculateLiquidity(uint128 _size, uint160 _priceX96) internal pure returns (uint128 liquidity) {
        liquidity = Math.mulDivUp(_size, _priceX96, Constants.Q96).toUint128();
    }

    /// @dev Calculate the unrealized PnL of a position based on entry price
    /// @param _side The side of the position (Long or Short)
    /// @param _size The size of the position
    /// @param _entryPriceX96 The entry price of the position, as a Q64.96
    /// @param _priceX96 The trade price or index price, as a Q64.96
    /// @return unrealizedPnL The unrealized PnL of the position, positive value means profit,
    /// negative value means loss
    function calculateUnrealizedPnL(
        Side _side,
        uint128 _size,
        uint160 _entryPriceX96,
        uint160 _priceX96
    ) internal pure returns (int256 unrealizedPnL) {
        unchecked {
            // Because the maximum value of size is type(uint128).max, and the maximum value of entryPriceX96 and
            // priceX96 is type(uint160).max, so the maximum value of
            //      size * (entryPriceX96 - priceX96) / Q96
            // is type(uint192).max, so it is safe to convert the type to int256.
            if (_side.isLong()) {
                if (_entryPriceX96 > _priceX96)
                    unrealizedPnL = -int256(Math.mulDivUp(_size, _entryPriceX96 - _priceX96, Constants.Q96));
                else unrealizedPnL = int256(Math.mulDiv(_size, _priceX96 - _entryPriceX96, Constants.Q96));
            } else {
                if (_entryPriceX96 < _priceX96)
                    unrealizedPnL = -int256(Math.mulDivUp(_size, _priceX96 - _entryPriceX96, Constants.Q96));
                else unrealizedPnL = int256(Math.mulDiv(_size, _entryPriceX96 - _priceX96, Constants.Q96));
            }
        }
    }

    function chooseFundingRateGrowthX96(
        IPoolPosition.GlobalPosition storage _globalPosition,
        Side _side
    ) internal view returns (int192) {
        return _side.isLong() ? _globalPosition.longFundingRateGrowthX96 : _globalPosition.shortFundingRateGrowthX96;
    }

    /// @notice Calculate the trading fee of a trade
    /// @param _size The size of the trade
    /// @param _tradePriceX96 The price of the trade, as a Q64.96
    /// @param _tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    function calculateTradingFee(
        uint128 _size,
        uint160 _tradePriceX96,
        uint32 _tradingFeeRate
    ) internal pure returns (uint128 tradingFee) {
        unchecked {
            uint256 denominator = Constants.BASIS_POINTS_DIVISOR * Constants.Q96;
            tradingFee = Math.mulDivUp(uint256(_size) * _tradingFeeRate, _tradePriceX96, denominator).toUint128();
        }
    }

    /// @notice Calculate the liquidation fee of a position
    /// @param _size The size of the position
    /// @param _entryPriceX96 The entry price of the position, as a Q64.96
    /// @param _liquidationFeeRate The liquidation fee rate for trader positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return liquidationFee The liquidation fee of the position
    function calculateLiquidationFee(
        uint128 _size,
        uint160 _entryPriceX96,
        uint32 _liquidationFeeRate
    ) internal pure returns (uint128 liquidationFee) {
        unchecked {
            uint256 denominator = Constants.BASIS_POINTS_DIVISOR * Constants.Q96;
            liquidationFee = Math
                .mulDivUp(uint256(_size) * _liquidationFeeRate, _entryPriceX96, denominator)
                .toUint128();
        }
    }

    /// @notice Calculate the funding fee of a position
    /// @param _globalFundingRateGrowthX96 The global funding rate growth, as a Q96.96
    /// @param _positionFundingRateGrowthX96 The position funding rate growth, as a Q96.96
    /// @param _positionSize The size of the position
    /// @return fundingFee The funding fee of the position, a positive value means the position receives
    /// funding fee, while a negative value means the position pays funding fee
    function calculateFundingFee(
        int192 _globalFundingRateGrowthX96,
        int192 _positionFundingRateGrowthX96,
        uint128 _positionSize
    ) internal pure returns (int256 fundingFee) {
        int256 deltaX96 = _globalFundingRateGrowthX96 - _positionFundingRateGrowthX96;
        if (deltaX96 >= 0) fundingFee = Math.mulDiv(uint256(deltaX96), _positionSize, Constants.Q96).toInt256();
        else fundingFee = -Math.mulDivUp(uint256(-deltaX96), _positionSize, Constants.Q96).toInt256();
    }

    /// @notice Calculate the maintenance margin
    /// @dev maintenanceMargin = size * (entryPrice * liquidationFeeRate
    ///                          + indexPrice * tradingFeeRate)
    ///                          + liquidationExecutionFee
    /// @param _size The size of the position
    /// @param _entryPriceX96 The entry price of the position, as a Q64.96
    /// @param _indexPriceX96 The index price, as a Q64.96
    /// @param _liquidationFeeRate The liquidation fee rate for trader positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @param _tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @param _liquidationExecutionFee The liquidation execution fee paid by the position
    /// @return maintenanceMargin The maintenance margin
    function calculateMaintenanceMargin(
        uint128 _size,
        uint160 _entryPriceX96,
        uint160 _indexPriceX96,
        uint32 _liquidationFeeRate,
        uint32 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) internal pure returns (uint256 maintenanceMargin) {
        unchecked {
            maintenanceMargin = Math.mulDivUp(
                _size,
                uint256(_entryPriceX96) * _liquidationFeeRate + uint256(_indexPriceX96) * _tradingFeeRate,
                Constants.BASIS_POINTS_DIVISOR * Constants.Q96
            );
            // Because the maximum value of size is type(uint128).max, and the maximum value of entryPriceX96 and
            // indexPriceX96 is type(uint160).max, and liquidationFeeRate + tradingFeeRate is at most 2 * DIVISOR,
            // so the maximum value of
            //      size * (entryPriceX96 * liquidationFeeRate + indexPriceX96 * tradingFeeRate) / (Q96 * DIVISOR)
            // is type(uint193).max, so there will be no overflow here.
            maintenanceMargin += _liquidationExecutionFee;
        }
    }

    /// @notice calculate the liquidation price
    /// @param _positionCache The cache of position
    /// @param _side The side of the position (Long or Short)
    /// @param _fundingFee The funding fee, a positive value means the position receives a funding fee,
    /// while a negative value means the position pays funding fee
    /// @param _liquidationFeeRate The liquidation fee rate for trader positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @param _tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @param _liquidationExecutionFee The liquidation execution fee paid by the position
    /// @return liquidationPriceX96 The liquidation price of the position, as a Q64.96
    /// @return adjustedFundingFee The liquidation price based on the funding fee. If `_fundingFee` is negative,
    /// then this value is not less than `_fundingFee`
    function calculateLiquidationPriceX96(
        IPool.Position memory _positionCache,
        IPool.PreviousGlobalFundingRate storage _previousGlobalFundingRate,
        Side _side,
        int256 _fundingFee,
        uint32 _liquidationFeeRate,
        uint32 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) public view returns (uint160 liquidationPriceX96, int256 adjustedFundingFee) {
        int256 marginInt256 = int256(uint256(_positionCache.margin));
        if ((marginInt256 + _fundingFee) > 0) {
            liquidationPriceX96 = _calculateLiquidationPriceX96(
                _positionCache,
                _side,
                _fundingFee,
                _liquidationFeeRate,
                _tradingFeeRate,
                _liquidationExecutionFee
            );
            if (_isAcceptableLiquidationPriceX96(_side, liquidationPriceX96, _positionCache.entryPriceX96))
                return (liquidationPriceX96, _fundingFee);
        }
        // Try to use the previous funding rate to calculate the funding fee
        adjustedFundingFee = calculateFundingFee(
            _choosePreviousGlobalFundingRateGrowthX96(_previousGlobalFundingRate, _side),
            _positionCache.entryFundingRateGrowthX96,
            _positionCache.size
        );
        if (adjustedFundingFee > _fundingFee && (marginInt256 + adjustedFundingFee) > 0) {
            liquidationPriceX96 = _calculateLiquidationPriceX96(
                _positionCache,
                _side,
                adjustedFundingFee,
                _liquidationFeeRate,
                _tradingFeeRate,
                _liquidationExecutionFee
            );
            if (_isAcceptableLiquidationPriceX96(_side, liquidationPriceX96, _positionCache.entryPriceX96))
                return (liquidationPriceX96, adjustedFundingFee);
        } else adjustedFundingFee = _fundingFee;

        // Only try to use zero funding fee calculation when the current best funding fee is negative,
        // then zero funding fee is the best
        if (adjustedFundingFee < 0) {
            adjustedFundingFee = 0;
            liquidationPriceX96 = _calculateLiquidationPriceX96(
                _positionCache,
                _side,
                adjustedFundingFee,
                _liquidationFeeRate,
                _tradingFeeRate,
                _liquidationExecutionFee
            );
        }
    }

    function _choosePreviousGlobalFundingRateGrowthX96(
        IPool.PreviousGlobalFundingRate storage _pgrf,
        Side _side
    ) private view returns (int192) {
        return _side.isLong() ? _pgrf.longFundingRateGrowthX96 : _pgrf.shortFundingRateGrowthX96;
    }

    function _isAcceptableLiquidationPriceX96(
        Side _side,
        uint160 _liquidationPriceX96,
        uint160 _entryPriceX96
    ) private pure returns (bool) {
        return
            (_side.isLong() && _liquidationPriceX96 < _entryPriceX96) ||
            (_side.isShort() && _liquidationPriceX96 > _entryPriceX96);
    }

    /// @notice Calculate the liquidation price
    /// @dev Given the liquidation condition as:
    /// For long position: margin + fundingFee - positionSize * (entryPrice - liquidationPrice)
    ///                     = entryPrice * positionSize * liquidationFeeRate
    ///                         + liquidationPrice * positionSize * tradingFeeRate + liquidationExecutionFee
    /// For short position: margin + fundingFee - positionSize * (liquidationPrice - entryPrice)
    ///                     = entryPrice * positionSize * liquidationFeeRate
    ///                         + liquidationPrice * positionSize * tradingFeeRate + liquidationExecutionFee
    /// We can get:
    /// Long position liquidation price:
    ///     liquidationPrice
    ///       = [margin + fundingFee - liquidationExecutionFee - entryPrice * positionSize * (1 + liquidationFeeRate)]
    ///       / [positionSize * (tradingFeeRate - 1)]
    /// Short position liquidation price:
    ///     liquidationPrice
    ///       = [margin + fundingFee - liquidationExecutionFee + entryPrice * positionSize * (1 - liquidationFeeRate)]
    ///       / [positionSize * (tradingFeeRate + 1)]
    /// @param _positionCache The cache of position
    /// @param _side The side of the position (Long or Short)
    /// @param _fundingFee The funding fee, a positive value means the position receives a funding fee,
    /// while a negative value means the position pays funding fee
    /// @param _liquidationFeeRate The liquidation fee rate for trader positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @param _tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @param _liquidationExecutionFee The liquidation execution fee paid by the position
    /// @return liquidationPriceX96 The liquidation price of the position, as a Q64.96
    function _calculateLiquidationPriceX96(
        IPool.Position memory _positionCache,
        Side _side,
        int256 _fundingFee,
        uint32 _liquidationFeeRate,
        uint32 _tradingFeeRate,
        uint64 _liquidationExecutionFee
    ) private pure returns (uint160 liquidationPriceX96) {
        uint256 marginAfter = uint256(_positionCache.margin);
        if (_fundingFee >= 0) marginAfter += uint256(_fundingFee);
        else marginAfter -= uint256(-_fundingFee);

        (uint256 numeratorX96, uint256 denominator) = _side.isLong()
            ? (Constants.BASIS_POINTS_DIVISOR + _liquidationFeeRate, Constants.BASIS_POINTS_DIVISOR - _tradingFeeRate)
            : (Constants.BASIS_POINTS_DIVISOR - _liquidationFeeRate, Constants.BASIS_POINTS_DIVISOR + _tradingFeeRate);

        uint256 numeratorPart2X96 = marginAfter >= _liquidationExecutionFee
            ? marginAfter - _liquidationExecutionFee
            : _liquidationExecutionFee - marginAfter;

        numeratorX96 *= uint256(_positionCache.entryPriceX96) * _positionCache.size;
        denominator *= _positionCache.size;
        numeratorPart2X96 *= Constants.BASIS_POINTS_DIVISOR * Constants.Q96;

        if (_side.isLong()) {
            numeratorX96 = marginAfter >= _liquidationExecutionFee
                ? numeratorX96 - numeratorPart2X96
                : numeratorX96 + numeratorPart2X96;
        } else {
            numeratorX96 = marginAfter >= _liquidationExecutionFee
                ? numeratorX96 + numeratorPart2X96
                : numeratorX96 - numeratorPart2X96;
        }
        liquidationPriceX96 = _side.isLong()
            ? (numeratorX96 / denominator).toUint160()
            : Math.ceilDiv(numeratorX96, denominator).toUint160();
    }
}
