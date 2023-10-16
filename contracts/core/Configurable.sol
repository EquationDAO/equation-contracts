// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import "../governance/Governable.sol";
import "./interfaces/IConfigurable.sol";

abstract contract Configurable is IConfigurable, Governable, ReentrancyGuard {
    IERC20 internal immutable usd;
    /// @inheritdoc IConfigurable
    mapping(IERC20 => TokenConfig) public override tokenConfigs;
    /// @inheritdoc IConfigurable
    mapping(IERC20 => TokenFeeRateConfig) public override tokenFeeRateConfigs;
    mapping(IERC20 => TokenPriceConfig) private tokenPriceConfigs0;

    constructor(IERC20 _usd) {
        usd = _usd;
        emit USDEnabled(_usd);
    }

    /// @inheritdoc IConfigurable
    function USD() external view override returns (IERC20) {
        return usd;
    }

    /// @inheritdoc IConfigurable
    function isEnabledToken(IERC20 _token) external view override returns (bool) {
        return _isEnabledToken(_token);
    }

    /// @inheritdoc IConfigurable
    function enableToken(
        IERC20 _token,
        TokenConfig calldata _cfg,
        TokenFeeRateConfig calldata _feeRateCfg,
        TokenPriceConfig calldata _priceCfg
    ) external override nonReentrant {
        _onlyGov();

        if (tokenConfigs[_token].maxLeveragePerLiquidityPosition > 0) revert TokenAlreadyEnabled(_token);

        _setTokenConfig(_token, _cfg, _feeRateCfg, _priceCfg);
    }

    /// @inheritdoc IConfigurable
    function updateTokenConfig(
        IERC20 _token,
        TokenConfig calldata _newCfg,
        TokenFeeRateConfig calldata _newFeeRateCfg,
        TokenPriceConfig calldata _newPriceCfg
    ) external override nonReentrant {
        _onlyGov();

        if (tokenConfigs[_token].maxLeveragePerLiquidityPosition == 0) revert TokenNotEnabled(_token);

        _setTokenConfig(_token, _newCfg, _newFeeRateCfg, _newPriceCfg);
    }

    function _isEnabledToken(IERC20 _token) internal view returns (bool) {
        return tokenConfigs[_token].maxLeveragePerLiquidityPosition != 0;
    }

    function _setTokenConfig(
        IERC20 _token,
        TokenConfig calldata _newCfg,
        TokenFeeRateConfig calldata _newFeeRateCfg,
        TokenPriceConfig calldata _newPriceCfg
    ) private {
        _validateTokenConfig(_newCfg);
        _validateTokenFeeRateConfig(_newFeeRateCfg);
        _validatePriceConfig(_newPriceCfg);

        tokenConfigs[_token] = _newCfg;
        tokenFeeRateConfigs[_token] = _newFeeRateCfg;
        tokenPriceConfigs0[_token] = _newPriceCfg;

        afterTokenConfigChanged(_token);

        emit TokenConfigChanged(_token, _newCfg, _newFeeRateCfg, _newPriceCfg);
    }

    function afterTokenConfigChanged(IERC20 _token) internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IConfigurable
    function tokenPriceConfigs(
        IERC20 _token
    ) external view override returns (uint128 maxPriceImpactLiquidity, uint8 liquidationVertexIndex) {
        TokenPriceConfig memory cfg = tokenPriceConfigs0[_token];
        return (cfg.maxPriceImpactLiquidity, cfg.liquidationVertexIndex);
    }

    /// @inheritdoc IConfigurable
    function tokenPriceVertexConfigs(
        IERC20 _token,
        uint8 _index
    ) external view override returns (uint32 balanceRate, uint32 premiumRate) {
        VertexConfig memory cfg = tokenPriceConfigs0[_token].vertices[_index];
        return (cfg.balanceRate, cfg.premiumRate);
    }

    function _validateTokenConfig(TokenConfig calldata _newCfg) private pure {
        if (_newCfg.maxRiskRatePerLiquidityPosition > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidMaxRiskRatePerLiquidityPosition(_newCfg.maxRiskRatePerLiquidityPosition);

        if (_newCfg.maxLeveragePerLiquidityPosition == 0)
            revert InvalidMaxLeveragePerLiquidityPosition(_newCfg.maxLeveragePerLiquidityPosition);

        if (_newCfg.maxLeveragePerPosition == 0) revert InvalidMaxLeveragePerPosition(_newCfg.maxLeveragePerPosition);

        if (_newCfg.liquidationFeeRatePerPosition > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidLiquidationFeeRatePerPosition(_newCfg.liquidationFeeRatePerPosition);

        if (_newCfg.interestRate > Constants.BASIS_POINTS_DIVISOR) revert InvalidInterestRate(_newCfg.interestRate);

        if (_newCfg.maxFundingRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidMaxFundingRate(_newCfg.maxFundingRate);
    }

    function _validateTokenFeeRateConfig(TokenFeeRateConfig calldata _newCfg) private pure {
        if (_newCfg.tradingFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidTradingFeeRate(_newCfg.tradingFeeRate);

        if (_newCfg.liquidityFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidLiquidityFeeRate(_newCfg.liquidityFeeRate);

        if (_newCfg.protocolFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidProtocolFeeRate(_newCfg.protocolFeeRate);

        if (_newCfg.referralReturnFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidReferralReturnFeeRate(_newCfg.referralReturnFeeRate);

        if (_newCfg.referralParentReturnFeeRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidReferralParentReturnFeeRate(_newCfg.referralParentReturnFeeRate);

        if (_newCfg.referralDiscountRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidReferralDiscountRate(_newCfg.referralDiscountRate);

        if (
            uint256(_newCfg.liquidityFeeRate) +
                _newCfg.protocolFeeRate +
                _newCfg.referralReturnFeeRate +
                _newCfg.referralParentReturnFeeRate >
            Constants.BASIS_POINTS_DIVISOR
        )
            revert InvalidFeeRate(
                _newCfg.liquidityFeeRate,
                _newCfg.protocolFeeRate,
                _newCfg.referralReturnFeeRate,
                _newCfg.referralParentReturnFeeRate
            );
    }

    function _validatePriceConfig(TokenPriceConfig calldata _newCfg) private pure {
        if (_newCfg.maxPriceImpactLiquidity == 0)
            revert InvalidMaxPriceImpactLiquidity(_newCfg.maxPriceImpactLiquidity);

        if (_newCfg.vertices.length != Constants.VERTEX_NUM)
            revert InvalidVerticesLength(_newCfg.vertices.length, Constants.VERTEX_NUM);

        if (_newCfg.liquidationVertexIndex >= Constants.LATEST_VERTEX)
            revert InvalidLiquidationVertexIndex(_newCfg.liquidationVertexIndex);

        unchecked {
            // first vertex must be (0, 0)
            if (_newCfg.vertices[0].balanceRate != 0 || _newCfg.vertices[0].premiumRate != 0) revert InvalidVertex(0);

            for (uint8 i = 2; i < Constants.VERTEX_NUM; ++i) {
                if (
                    _newCfg.vertices[i - 1].balanceRate > _newCfg.vertices[i].balanceRate ||
                    _newCfg.vertices[i - 1].premiumRate > _newCfg.vertices[i].premiumRate
                ) revert InvalidVertex(i);
            }
            if (
                _newCfg.vertices[Constants.LATEST_VERTEX].balanceRate > Constants.BASIS_POINTS_DIVISOR ||
                _newCfg.vertices[Constants.LATEST_VERTEX].premiumRate > Constants.BASIS_POINTS_DIVISOR
            ) revert InvalidVertex(Constants.LATEST_VERTEX);
        }
    }
}
