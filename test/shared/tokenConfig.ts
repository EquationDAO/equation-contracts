export function newTokenConfig() {
    return {
        minMarginPerLiquidityPosition: 10n * 10n ** 6n,
        maxRiskRatePerLiquidityPosition: 99_500_000n, // 99.5%
        maxLeveragePerLiquidityPosition: 200n,

        minMarginPerPosition: 10n * 10n ** 6n,
        maxLeveragePerPosition: 200n,
        liquidationFeeRatePerPosition: 200_000n, // 0.2%
        liquidationExecutionFee: 600_000n, // 0.6 USDC
        interestRate: 1250n, // 0.00125%
        maxFundingRate: 150_000n, // 0.15%
    };
}

export function newTokenFeeRateConfig() {
    return {
        tradingFeeRate: 50_000n, // 0.05%
        liquidityFeeRate: 50_000_000n, // 50%
        protocolFeeRate: 30_000_000n, // 30%
        referralReturnFeeRate: 10_000_000n, // 10%
        referralParentReturnFeeRate: 1_000_000n, // 1%
        referralDiscountRate: 90_000_000n, // 90%
    };
}

export function newTokenPriceConfig() {
    return {
        maxPriceImpactLiquidity: 1_0000_0000n * 10n ** 6n,
        liquidationVertexIndex: 4n,
        vertices: [
            {
                balanceRate: 0n, // 0%
                premiumRate: 0n, // 0%
            },
            {
                balanceRate: 2000000n, // 2%
                premiumRate: 50000n, // 0.05%
            },
            {
                balanceRate: 3000000n, // 3%
                premiumRate: 100000n, // 0.1%
            },
            {
                balanceRate: 4000000n, // 4%
                premiumRate: 150000n, // 0.15%
            },
            {
                balanceRate: 5000000n, // 5%
                premiumRate: 200000n, // 0.2%
            },
            {
                balanceRate: 10000000n, // 10%
                premiumRate: 1000000n, // 1%
            },
            {
                balanceRate: 100000000n, // 100%
                premiumRate: 20000000n, // 20%
            },
        ],
    };
}
