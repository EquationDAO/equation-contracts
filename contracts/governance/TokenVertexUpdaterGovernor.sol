// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../core/interfaces/IPoolFactory.sol";
import "../types/PackedValue.sol";
import "../core/interfaces/IConfigurable.sol";
import "../libraries/Constants.sol";

contract TokenVertexUpdaterGovernor is AccessControl {
    /// @notice Config data is out-of-date
    /// @param timestamp Update timestamp
    error StaleConfig(uint32 timestamp);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TOKEN_VERTEX_UPDATER_ROLE = keccak256("TOKEN_VERTEX_UPDATER_ROLE");

    IPoolFactory public immutable poolFactory;
    uint32 public maxUpdateTimeDeviation = 60;

    constructor(address _admin, address _tokenVertexUpdater, IPoolFactory _poolFactory) {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TOKEN_VERTEX_UPDATER_ROLE, ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(TOKEN_VERTEX_UPDATER_ROLE, _tokenVertexUpdater);
        poolFactory = _poolFactory;
    }

    function execute(address _target, uint256 _value, bytes calldata _data) public virtual onlyRole(ADMIN_ROLE) {
        Address.functionCallWithValue(_target, _data, _value);
    }

    function setMaxUpdateTimeDeviation(uint32 _maxUpdateTimeDeviation) public virtual onlyRole(ADMIN_ROLE) {
        maxUpdateTimeDeviation = _maxUpdateTimeDeviation;
    }

    function updateTokenVertexConfig(
        PackedValue _packedTokenTimestamp,
        PackedValue _packedBalanceRates,
        PackedValue _packedPremiumRates
    ) public virtual onlyRole(TOKEN_VERTEX_UPDATER_ROLE) {
        IERC20 token = IERC20(_packedTokenTimestamp.unpackAddress(0));
        uint32 timestamp = _packedTokenTimestamp.unpackUint32(160);
        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeDelta = timestamp > blockTimestamp ? timestamp - blockTimestamp : blockTimestamp - timestamp;
        if (timeDelta > maxUpdateTimeDeviation) revert StaleConfig(timestamp);
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
        ) = poolFactory.tokenConfigs(token);

        (
            tokenFeeRateConfig.tradingFeeRate,
            tokenFeeRateConfig.liquidityFeeRate,
            tokenFeeRateConfig.protocolFeeRate,
            tokenFeeRateConfig.referralReturnFeeRate,
            tokenFeeRateConfig.referralParentReturnFeeRate,
            tokenFeeRateConfig.referralDiscountRate
        ) = poolFactory.tokenFeeRateConfigs(token);

        IConfigurable.VertexConfig[] memory vertices = new IConfigurable.VertexConfig[](Constants.VERTEX_NUM);
        unchecked {
            for (uint8 i; i < Constants.VERTEX_NUM; ++i) {
                vertices[i].balanceRate = _packedBalanceRates.unpackUint32(i * 32);
                vertices[i].premiumRate = _packedPremiumRates.unpackUint32(i * 32);
            }
        }

        (tokenPriceConfig.maxPriceImpactLiquidity, tokenPriceConfig.liquidationVertexIndex) = poolFactory
            .tokenPriceConfigs(token);
        IPool pool = poolFactory.pools(token);
        if (address(pool) != address(0)) {
            (, , , , tokenPriceConfig.maxPriceImpactLiquidity, ) = pool.globalLiquidityPosition();
        }
        tokenPriceConfig.vertices = vertices;
        poolFactory.updateTokenConfig(token, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
    }
}
