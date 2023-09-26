const defaultTokenCfg = {
    minMarginPerLiquidityPosition: 10n * 10n ** 6n,
    maxRiskRatePerLiquidityPosition: 99_500_000n, // 99.5%
    maxLeveragePerLiquidityPosition: 200,

    minMarginPerPosition: 10n * 10n ** 6n,
    maxLeveragePerPosition: 200,
    liquidationFeeRatePerPosition: 200_000n, // 0.2%
    liquidationExecutionFee: 600_000n, // 0.6 USDC
    interestRate: 1250, // 0.00125%
    maxFundingRate: 150_000n, // 0.15%
};

const defaultTokenFeeCfg = {
    tradingFeeRate: 50_000n, // 0.05%
    liquidityFeeRate: 50_000_000n, // 50%
    protocolFeeRate: 30_000_000n, // 30%
    referralReturnFeeRate: 10_000_000n, // 10%
    referralParentReturnFeeRate: 1_000_000n, // 1%
    referralDiscountRate: 90_000_000n, // 90%
};

const defaultVertices = [
    {
        balanceRate: 0n, // 0%
        premiumRate: 0n, // 0%
    },
    {
        balanceRate: 4000000n, // 4%
        premiumRate: 50000n, // 0.05%
    },
    {
        balanceRate: 8000000n, // 8%
        premiumRate: 100000n, // 0.1%
    },
    {
        balanceRate: 10000000n, // 10%
        premiumRate: 150000n, // 0.15%
    },
    {
        balanceRate: 12000000n, // 12%
        premiumRate: 200000n, // 0.2%
    },
    {
        balanceRate: 20000000n, // 20%
        premiumRate: 600000n, // 0.6%
    },
    {
        balanceRate: 100000000n, // 100%
        premiumRate: 10000000n, // 10%
    },
];

const defaultTokenPriceCfg = {
    maxPriceImpactLiquidity: 1_0000_0000n * 10n ** 6n,
    liquidationVertexIndex: 4,
    vertices: defaultVertices,
};

const defaultMaxCumulativeDeltaDiff = 100n * 1000n; // 10%
const defaultMinExecutionFee = 300_000_000_000_000n; // 0.0003 ETH

export const networks = {
    "arbitrum-goerli": {
        usd: "0x58e7F6b126eCC1A694B19062317b60Cf474E3D17",
        weth: "0xe39Ab88f8A4777030A534146A9Ca3B52bd5D43A3",
        minExecutionFee: defaultMinExecutionFee,
        farmMintTime: Math.floor(new Date().getTime() / 1000) + 12 * 60 * 60, // FIXME
        uniswapV3Factory: "0x4893376342d5d7b3e31d4184c08b265e5ab2a3f6",
        uniswapV3PositionManager: "0x622e4726a167799826d1E1D150b076A7725f5D81",
        sequencerUpTimeFeed: "0x4da69F028a5790fCCAfe81a75C0D24f46ceCDd69",
        efcBaseURL: "https://nftstorage.link/ipfs/bafybeiasc336sq3os7ioif44tqefi6crh3pk2j7fknwc7tnnzbqf5bi274/",
        efcMemberBaseURL: "https://nftstorage.link/ipfs/bafybeiasc336sq3os7ioif44tqefi6crh3pk2j7fknwc7tnnzbqf5bi274",
        tokens: [
            {
                name: "ETH",
                address: "0xECF628c20E5E1C0e0A90226d60FAd547AF850E0F",
                chainLinkPriceFeed: "0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 0n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 75_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "BTC",
                address: "0x6f0763010F979B83837327FF9a37Ff93cC95A51c",
                chainLinkPriceFeed: "0x6550bc2301936011c1334555e62A87705A81C12C",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 0n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 100_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "ARB",
                address: "0x3eF7a2C0fA0dBAc93421692e7E6f1551b4af696A",
                chainLinkPriceFeed: "0x2eE9BFB2D319B31A573EA15774B755715988E99D",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 0n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 10_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "LINK",
                address: "0x12fA61ac9929BD6a4FecFcad7316af92eC32bED6",
                chainLinkPriceFeed: "0xd28Ba6CA3bB72bF371b80a2a0a33cBcf9073C954",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 0n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 10_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
        ],
        mixedExecutors: ["0x748b44dA671C256b9f1F1c2098FA9e477F84B141", "0x866D7d4C811Eb0845D7952F40934dC1F3F2B3Bc0"],
    },
};
