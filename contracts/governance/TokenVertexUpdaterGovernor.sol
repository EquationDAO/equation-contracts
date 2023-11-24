// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../core/interfaces/IPoolFactory.sol";
import "../types/PackedValue.sol";
import "../core/interfaces/IConfigurable.sol";
import "../libraries/Constants.sol";

contract TokenVertexUpdaterGovernor is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TOKEN_VERTEX_UPDATER_ROLE = keccak256("TOKEN_VERTEX_UPDATER_ROLE");

    IPoolFactory public immutable poolFactory;

    constructor(address _admin, address _tokenVertexUpdater, IPoolFactory _poolFactory) {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TOKEN_VERTEX_UPDATER_ROLE, ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(TOKEN_VERTEX_UPDATER_ROLE, _tokenVertexUpdater);
        poolFactory = _poolFactory;
    }

    function execute(address _target, uint256 _value, bytes calldata _data) public onlyRole(ADMIN_ROLE) {
        (bool success, ) = _target.call{value: _value}(_data);
        require(success, "transaction reverted");
    }

    function updateTokenVertexConfig(
        IERC20 _token,
        uint128 _maxPriceImpactLiquidity,
        PackedValue _packedBalanceRate,
        PackedValue _packedPremiumRate
    ) public onlyRole(TOKEN_VERTEX_UPDATER_ROLE) {
        IPoolFactory.TokenConfig memory tokenConfig;
        IPoolFactory.TokenFeeRateConfig memory tokenFeeRateConfig;
        IPoolFactory.TokenPriceConfig memory tokenPriceConfig;

        (
            tokenConfig.minMarginPerLiquidityPosition,
            tokenConfig.maxRiskRatePerLiquidityPosition,
            tokenConfig.maxLeveragePerLiquidityPosition,
            tokenConfig.minMarginPerPosition,
            tokenConfig.maxLeveragePerPosition,
            tokenConfig.liquidationFeeRatePerPosition,
            tokenConfig.liquidationExecutionFee,
            tokenConfig.interestRate,
            tokenConfig.maxFundingRate
        ) = poolFactory.tokenConfigs(_token);

        (
            tokenFeeRateConfig.tradingFeeRate,
            tokenFeeRateConfig.liquidityFeeRate,
            tokenFeeRateConfig.protocolFeeRate,
            tokenFeeRateConfig.referralReturnFeeRate,
            tokenFeeRateConfig.referralParentReturnFeeRate,
            tokenFeeRateConfig.referralDiscountRate
        ) = poolFactory.tokenFeeRateConfigs(_token);

        IConfigurable.VertexConfig[] memory vertices = new IConfigurable.VertexConfig[](Constants.VERTEX_NUM);
        unchecked {
            for (uint8 i; i < Constants.VERTEX_NUM; ++i) {
                vertices[i].balanceRate = _packedBalanceRate.unpackUint32(i * 32);
                vertices[i].premiumRate = _packedPremiumRate.unpackUint32(i * 32);
            }
        }

        (, tokenPriceConfig.liquidationVertexIndex) = poolFactory.tokenPriceConfigs(_token);
        tokenPriceConfig.maxPriceImpactLiquidity = _maxPriceImpactLiquidity;
        tokenPriceConfig.vertices = vertices;
        poolFactory.updateTokenConfig(_token, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
    }
}
