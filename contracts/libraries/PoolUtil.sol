// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Constants.sol";
import "../core/interfaces/IPoolFactory.sol";

/// @notice Utility library for Pool
library PoolUtil {
    function changeTokenConfig(
        IConfigurable.TokenConfig storage _tokenConfig,
        IConfigurable.TokenFeeRateConfig storage _tokenFeeRateConfig,
        IPool.PriceState storage _priceState,
        IPoolFactory _poolFactory,
        IERC20 _token
    ) public {
        _changeTokenConfig(_tokenConfig, _poolFactory, _token);

        _changeTokenFeeRateConfig(_tokenFeeRateConfig, _poolFactory, _token);

        _changeTokenPriceConfig(_priceState, _poolFactory, _token);
    }

    function _changeTokenConfig(
        IConfigurable.TokenConfig storage _tokenConfig,
        IPoolFactory _poolFactory,
        IERC20 _token
    ) private {
        (
            _tokenConfig.minMarginPerLiquidityPosition,
            _tokenConfig.maxRiskRatePerLiquidityPosition,
            _tokenConfig.maxLeveragePerLiquidityPosition,
            _tokenConfig.minMarginPerPosition,
            _tokenConfig.maxLeveragePerPosition,
            _tokenConfig.liquidationFeeRatePerPosition,
            _tokenConfig.liquidationExecutionFee,
            _tokenConfig.interestRate,
            _tokenConfig.maxFundingRate
        ) = _poolFactory.tokenConfigs(_token);
    }

    function _changeTokenFeeRateConfig(
        IConfigurable.TokenFeeRateConfig storage _tokenFeeRateConfig,
        IPoolFactory _poolFactory,
        IERC20 _token
    ) private {
        (
            _tokenFeeRateConfig.tradingFeeRate,
            _tokenFeeRateConfig.liquidityFeeRate,
            _tokenFeeRateConfig.protocolFeeRate,
            _tokenFeeRateConfig.referralReturnFeeRate,
            _tokenFeeRateConfig.referralParentReturnFeeRate,
            _tokenFeeRateConfig.referralDiscountRate
        ) = _poolFactory.tokenFeeRateConfigs(_token);
    }

    function _changeTokenPriceConfig(
        IPool.PriceState storage _priceState,
        IPoolFactory _poolFactory,
        IERC20 _token
    ) private {
        (uint128 _liquidity, uint8 _index) = _poolFactory.tokenPriceConfigs(_token);
        (_priceState.maxPriceImpactLiquidity, _priceState.liquidationVertexIndex) = (_liquidity, _index);
    }
}
