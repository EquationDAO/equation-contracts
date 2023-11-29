// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "../core/interfaces/IPoolFactory.sol";
import "../types/PackedValue.sol";
import "../core/interfaces/IConfigurable.sol";
import "../libraries/Constants.sol";
import "../libraries/SafeCast.sol";

contract TokenVertexUpdaterGovernor is AccessControl, Multicall {
    using SafeCast for uint256;
    /// @notice Config data is out-of-date
    /// @param timestamp Update timestamp
    error StaleConfig(uint64 timestamp);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TOKEN_VERTEX_UPDATER_ROLE = keccak256("TOKEN_VERTEX_UPDATER_ROLE");

    IPoolFactory public immutable poolFactory;
    uint64 public maxUpdateTimeDeviation = 60;

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

    function setMaxUpdateTimeDeviation(uint64 _maxUpdateTimeDeviation) public virtual onlyRole(ADMIN_ROLE) {
        maxUpdateTimeDeviation = _maxUpdateTimeDeviation;
    }

    function updateTokenVertexConfigPremiumRates(
        PackedValue _packedTokenTimestamp,
        PackedValue _packedPremiumRates
    ) public virtual onlyRole(TOKEN_VERTEX_UPDATER_ROLE) {
        _updateTokenVertexConfig(_packedTokenTimestamp, _packedPremiumRates, _verticesUpdatePremiumRates);
    }

    function updateTokenVertexConfigBalanceRates(
        PackedValue _packedTokenTimestamp,
        PackedValue _packedBalanceRates
    ) public virtual onlyRole(TOKEN_VERTEX_UPDATER_ROLE) {
        return _updateTokenVertexConfig(_packedTokenTimestamp, _packedBalanceRates, _verticesUpdateBalanceRates);
    }

    function _updateTokenVertexConfig(
        PackedValue _packedTokenTimestamp,
        PackedValue _packedData,
        function(IERC20, PackedValue) returns (IConfigurable.VertexConfig[] memory) _verticesFn
    ) internal virtual {
        unchecked {
            IERC20 token = IERC20(_packedTokenTimestamp.unpackAddress(0));
            uint64 timestamp = _packedTokenTimestamp.unpackUint64(160);
            uint64 blockTimestamp = block.timestamp.toUint64();
            uint64 timeDelta = timestamp > blockTimestamp ? timestamp - blockTimestamp : blockTimestamp - timestamp;
            if (timeDelta > maxUpdateTimeDeviation) revert StaleConfig(timestamp);

            IPoolFactory.TokenConfig memory tokenConfig;
            IPoolFactory.TokenFeeRateConfig memory tokenFeeRateConfig;

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

            IPoolFactory.TokenPriceConfig memory tokenPriceConfig;
            (, tokenPriceConfig.liquidationVertexIndex) = poolFactory.tokenPriceConfigs(token);
            IPool pool = poolFactory.pools(token);
            (, , , , tokenPriceConfig.maxPriceImpactLiquidity, ) = pool.globalLiquidityPosition();

            IConfigurable.VertexConfig[] memory vertices = _verticesFn(token, _packedData);
            tokenPriceConfig.vertices = vertices;

            poolFactory.updateTokenConfig(token, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
        }
    }

    function _verticesUpdateBalanceRates(
        IERC20 _token,
        PackedValue _packedBalanceRates
    ) internal view virtual returns (IConfigurable.VertexConfig[] memory) {
        unchecked {
            IConfigurable.VertexConfig[] memory vertices = new IConfigurable.VertexConfig[](Constants.VERTEX_NUM);
            for (uint8 i; i < Constants.VERTEX_NUM; ++i) {
                vertices[i].balanceRate = _packedBalanceRates.unpackUint32(i * 32);
                (, vertices[i].premiumRate) = poolFactory.tokenPriceVertexConfigs(_token, i);
            }
            return vertices;
        }
    }

    function _verticesUpdatePremiumRates(
        IERC20 _token,
        PackedValue _packedPremiumRates
    ) internal view virtual returns (IConfigurable.VertexConfig[] memory) {
        unchecked {
            IConfigurable.VertexConfig[] memory vertices = new IConfigurable.VertexConfig[](Constants.VERTEX_NUM);
            for (uint8 i; i < Constants.VERTEX_NUM; ++i) {
                (vertices[i].balanceRate, ) = poolFactory.tokenPriceVertexConfigs(_token, i);
                vertices[i].premiumRate = _packedPremiumRates.unpackUint32(i * 32);
            }
            return vertices;
        }
    }
}
