// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Configurable Interface
/// @notice This interface defines the functions for manage USD stablecoins and token configurations
interface IConfigurable {
    /// @notice Emitted when a USD stablecoin is enabled
    /// @param usd The ERC20 token representing the USD stablecoin used in pools
    event USDEnabled(IERC20 indexed usd);

    /// @notice Emitted when a token's configuration is changed
    /// @param token The ERC20 token used in the pool
    /// @param newCfg The new token configuration
    /// @param newFeeRateCfg The new token fee rate configuration
    /// @param newPriceCfg The new token price configuration
    event TokenConfigChanged(
        IERC20 indexed token,
        TokenConfig newCfg,
        TokenFeeRateConfig newFeeRateCfg,
        TokenPriceConfig newPriceCfg
    );

    /// @notice Token is not enabled
    error TokenNotEnabled(IERC20 token);
    /// @notice Token is already enabled
    error TokenAlreadyEnabled(IERC20 token);
    /// @notice Invalid maximum risk rate for LP positions
    error InvalidMaxRiskRatePerLiquidityPosition(uint32 maxRiskRatePerLiquidityPosition);
    /// @notice Invalid maximum leverage for LP positions
    error InvalidMaxLeveragePerLiquidityPosition(uint32 maxLeveragePerLiquidityPosition);
    /// @notice Invalid maximum leverage for trader positions
    error InvalidMaxLeveragePerPosition(uint32 maxLeveragePerPosition);
    /// @notice Invalid liquidation fee rate for trader positions
    error InvalidLiquidationFeeRatePerPosition(uint32 liquidationFeeRatePerPosition);
    /// @notice Invalid interest rate
    error InvalidInterestRate(uint32 interestRate);
    /// @notice Invalid maximum funding rate
    error InvalidMaxFundingRate(uint32 maxFundingRate);
    /// @notice Invalid trading fee rate
    error InvalidTradingFeeRate(uint32 tradingFeeRate);
    /// @notice Invalid liquidity fee rate
    error InvalidLiquidityFeeRate(uint32 liquidityFeeRate);
    /// @notice Invalid protocol fee rate
    error InvalidProtocolFeeRate(uint32 protocolFeeRate);
    /// @notice Invalid referral return fee rate
    error InvalidReferralReturnFeeRate(uint32 referralReturnFeeRate);
    /// @notice Invalid referral parent return fee rate
    error InvalidReferralParentReturnFeeRate(uint32 referralParentReturnFeeRate);
    /// @notice Invalid referral discount rate
    error InvalidReferralDiscountRate(uint32 referralDiscountRate);
    /// @notice Invalid fee rate
    error InvalidFeeRate(
        uint32 liquidityFeeRate,
        uint32 protocolFeeRate,
        uint32 referralReturnFeeRate,
        uint32 referralParentReturnFeeRate
    );
    /// @notice Invalid maximum price impact liquidity
    error InvalidMaxPriceImpactLiquidity(uint128 maxPriceImpactLiquidity);
    /// @notice Invalid vertices length
    /// @dev The length of vertices must be equal to the `VERTEX_NUM`
    error InvalidVerticesLength(uint256 length, uint256 requiredLength);
    /// @notice Invalid liquidation vertex index
    /// @dev The liquidation vertex index must be less than the length of vertices
    error InvalidLiquidationVertexIndex(uint8 liquidationVertexIndex);
    /// @notice Invalid vertex
    /// @param index The index of the vertex
    error InvalidVertex(uint8 index);

    struct TokenConfig {
        // ==================== LP Position Configuration ====================
        uint64 minMarginPerLiquidityPosition;
        uint32 maxRiskRatePerLiquidityPosition;
        uint32 maxLeveragePerLiquidityPosition;
        // ==================== Trader Position Configuration ==================
        uint64 minMarginPerPosition;
        uint32 maxLeveragePerPosition;
        uint32 liquidationFeeRatePerPosition;
        // ==================== Other Configuration ==========================
        uint64 liquidationExecutionFee;
        uint32 interestRate;
        uint32 maxFundingRate;
    }

    struct TokenFeeRateConfig {
        uint32 tradingFeeRate;
        uint32 liquidityFeeRate;
        uint32 protocolFeeRate;
        uint32 referralReturnFeeRate;
        uint32 referralParentReturnFeeRate;
        uint32 referralDiscountRate;
    }

    struct VertexConfig {
        uint32 balanceRate;
        uint32 premiumRate;
    }

    struct TokenPriceConfig {
        uint128 maxPriceImpactLiquidity;
        uint8 liquidationVertexIndex;
        VertexConfig[] vertices;
    }

    /// @notice Get the USD stablecoin used in pools
    /// @return The ERC20 token representing the USD stablecoin used in pools
    function USD() external view returns (IERC20);

    /// @notice Checks if a token is enabled
    /// @param token The ERC20 token used in the pool
    /// @return True if the token is enabled, false otherwise
    function isEnabledToken(IERC20 token) external view returns (bool);

    /// @notice Get token configuration
    /// @param token The ERC20 token used in the pool
    /// @return minMarginPerLiquidityPosition The minimum entry margin required for LP positions
    /// @return maxRiskRatePerLiquidityPosition The maximum risk rate for LP positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return maxLeveragePerLiquidityPosition The maximum leverage for LP positions
    /// @return minMarginPerPosition The minimum entry margin required for trader positions
    /// @return maxLeveragePerPosition The maximum leverage for trader positions
    /// @return liquidationFeeRatePerPosition The liquidation fee rate for trader positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return liquidationExecutionFee The liquidation execution fee for LP and trader positions
    /// @return interestRate The interest rate used to calculate the funding rate,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return maxFundingRate The maximum funding rate, denominated in ten thousandths of a bip (i.e. 1e-8)
    function tokenConfigs(
        IERC20 token
    )
        external
        view
        returns (
            uint64 minMarginPerLiquidityPosition,
            uint32 maxRiskRatePerLiquidityPosition,
            uint32 maxLeveragePerLiquidityPosition,
            uint64 minMarginPerPosition,
            uint32 maxLeveragePerPosition,
            uint32 liquidationFeeRatePerPosition,
            uint64 liquidationExecutionFee,
            uint32 interestRate,
            uint32 maxFundingRate
        );

    /// @notice Get token fee rate configuration
    /// @param token The ERC20 token used in the pool
    /// @return tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return liquidityFeeRate The liquidity fee rate as a percentage of trading fee,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return protocolFeeRate The protocol fee rate as a percentage of trading fee,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return referralReturnFeeRate The referral return fee rate as a percentage of trading fee,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return referralParentReturnFeeRate The referral parent return fee rate as a percentage of trading fee,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return referralDiscountRate The discount rate for referrals,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    function tokenFeeRateConfigs(
        IERC20 token
    )
        external
        view
        returns (
            uint32 tradingFeeRate,
            uint32 liquidityFeeRate,
            uint32 protocolFeeRate,
            uint32 referralReturnFeeRate,
            uint32 referralParentReturnFeeRate,
            uint32 referralDiscountRate
        );

    /// @notice Get token price configuration
    /// @param token The ERC20 token used in the pool
    /// @return maxPriceImpactLiquidity The maximum LP liquidity value used to calculate
    /// premium rate when trader increase or decrease positions
    /// @return liquidationVertexIndex The index used to store the net position of the liquidation
    function tokenPriceConfigs(
        IERC20 token
    ) external view returns (uint128 maxPriceImpactLiquidity, uint8 liquidationVertexIndex);

    /// @notice Get token price vertex configuration
    /// @param token The ERC20 token used in the pool
    /// @param index The index of the vertex
    /// @return balanceRate The balance rate of the vertex, denominated in a bip (i.e. 1e-8)
    /// @return premiumRate The premium rate of the vertex, denominated in a bip (i.e. 1e-8)
    function tokenPriceVertexConfigs(
        IERC20 token,
        uint8 index
    ) external view returns (uint32 balanceRate, uint32 premiumRate);

    /// @notice Enable a token
    /// @dev The call will fail if caller is not the governor or the token is already enabled
    /// @param token The ERC20 token used in the pool
    /// @param cfg The token configuration
    /// @param feeRateCfg The token fee rate configuration
    /// @param priceCfg The token price configuration
    function enableToken(
        IERC20 token,
        TokenConfig calldata cfg,
        TokenFeeRateConfig calldata feeRateCfg,
        TokenPriceConfig calldata priceCfg
    ) external;

    /// @notice Update a token configuration
    /// @dev The call will fail if caller is not the governor or the token is not enabled
    /// @param token The ERC20 token used in the pool
    /// @param newCfg The new token configuration
    /// @param newFeeRateCfg The new token fee rate configuration
    /// @param newPriceCfg The new token price configuration
    function updateTokenConfig(
        IERC20 token,
        TokenConfig calldata newCfg,
        TokenFeeRateConfig calldata newFeeRateCfg,
        TokenPriceConfig calldata newPriceCfg
    ) external;
}
