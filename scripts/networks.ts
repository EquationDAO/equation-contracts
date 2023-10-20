import {ethers} from "hardhat";
import {parsePercent} from "./util";

const defaultTokenCfg = {
    minMarginPerLiquidityPosition: 10n * 10n ** 6n,
    maxRiskRatePerLiquidityPosition: parsePercent("99.5%"),
    maxLeveragePerLiquidityPosition: 200,

    minMarginPerPosition: 10n * 10n ** 6n,
    maxLeveragePerPosition: 200,
    liquidationFeeRatePerPosition: parsePercent("0.2%"),
    liquidationExecutionFee: 500_000n, // 0.5 USD
    interestRate: parsePercent("0.00125%"),
    maxFundingRate: parsePercent("0.25%"),
};

const defaultTokenFeeCfg = {
    tradingFeeRate: parsePercent("0.05%"),
    liquidityFeeRate: parsePercent("16%"),
    protocolFeeRate: parsePercent("50%"),
    referralReturnFeeRate: parsePercent("10%"),
    referralParentReturnFeeRate: parsePercent("1%"),
    referralDiscountRate: parsePercent("90%"),
};

const defaultVertices = [
    {
        balanceRate: parsePercent("0%"),
        premiumRate: parsePercent("0%"),
    },
    {
        balanceRate: parsePercent("4%"),
        premiumRate: parsePercent("0.05%"),
    },
    {
        balanceRate: parsePercent("8%"),
        premiumRate: parsePercent("0.1%"),
    },
    {
        balanceRate: parsePercent("10%"),
        premiumRate: parsePercent("0.15%"),
    },
    {
        balanceRate: parsePercent("12%"),
        premiumRate: parsePercent("0.2%"),
    },
    {
        balanceRate: parsePercent("20%"),
        premiumRate: parsePercent("0.6%"),
    },
    {
        balanceRate: parsePercent("100%"),
        premiumRate: parsePercent("10%"),
    },
];

const defaultTokenPriceCfg = {
    maxPriceImpactLiquidity: 1_0000_0000n * 10n ** 6n,
    liquidationVertexIndex: 4,
    vertices: defaultVertices,
};

const defaultMaxCumulativeDeltaDiff = 100n * 1000n; // 10%

export const networks = {
    "arbitrum-goerli": {
        usd: "0x58e7F6b126eCC1A694B19062317b60Cf474E3D17",
        usdChainLinkPriceFeed: "0x0a023a3423D9b27A0BE48c768CCF2dD7877fEf5E",
        weth: "0xe39Ab88f8A4777030A534146A9Ca3B52bd5D43A3",
        minPositionRouterExecutionFee: ethers.utils.parseUnits("0.00021", "ether"),
        minOrderBookExecutionFee: ethers.utils.parseUnits("0.0003", "ether"),
        farmMintTime: Math.floor(new Date().getTime() / 1000) + 1 * 60 * 60,
        uniswapV3Factory: "0x4893376342d5d7b3e31d4184c08b265e5ab2a3f6",
        uniswapV3PositionManager: "0x622e4726a167799826d1E1D150b076A7725f5D81",
        sequencerUpTimeFeed: "0x4da69F028a5790fCCAfe81a75C0D24f46ceCDd69",
        efcBaseURL: "https://raw.githubusercontent.com/EquationDAO/nft-metadatas/main/EFC/",
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
    "arbitrum-mainnet": {
        usd: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
        usdChainLinkPriceFeed: "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
        weth: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        minPositionRouterExecutionFee: ethers.utils.parseUnits("0.00021", "ether"),
        minOrderBookExecutionFee: ethers.utils.parseUnits("0.0003", "ether"),
        farmMintTime: Math.floor(new Date("2023-10-28T00:00:00.000Z").getTime() / 1000),
        uniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        uniswapV3PositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        sequencerUpTimeFeed: "0xFdB631F5EE196F0ed6FAa767959853A9F217697D",
        efcBaseURL: "https://raw.githubusercontent.com/EquationDAO/nft-metadatas/main/EFC/",
        tokens: [
            {
                name: "ETH",
                address: undefined,
                chainLinkPriceFeed: "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 37037037037037037n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 60_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "BTC",
                address: undefined,
                chainLinkPriceFeed: "0x6ce185860a4963106506C203335A2910413708e9",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 61728395061728395n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 100_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "SOL",
                address: undefined,
                chainLinkPriceFeed: "0x24ceA4b8ce57cdA5058b924B9B9987992450590c",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 4629629629629629n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 7_500_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "ARB",
                address: undefined,
                chainLinkPriceFeed: "0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 2469135802469135n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 4_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "OP",
                address: undefined,
                chainLinkPriceFeed: "0x205aaD468a11fd5D34fA7211bC6Bad5b3deB9b98",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 2469135802469135n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 4_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "MATIC",
                address: undefined,
                chainLinkPriceFeed: "0x52099D4523531f678Dfc568a7B1e5038aadcE1d6",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 2469135802469135n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 4_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "AVAX",
                address: undefined,
                chainLinkPriceFeed: "0x8bf61728eeDCE2F32c456454d87B5d6eD6150208",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 2469135802469135n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 4_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
            {
                name: "LINK",
                address: undefined,
                chainLinkPriceFeed: "0x86E53CF1B870786351Da77A57575e79CB55812CB",
                maxCumulativeDeltaDiff: defaultMaxCumulativeDeltaDiff,
                rewardsPerSecond: 2469135802469135n,
                tokenCfg: defaultTokenCfg,
                tokenFeeCfg: defaultTokenFeeCfg,
                tokenPriceCfg: {
                    maxPriceImpactLiquidity: 4_000_000n * 10n ** 6n,
                    liquidationVertexIndex: 4,
                    vertices: defaultVertices,
                },
            },
        ],
        mixedExecutors: [
            "0x50C66c2299964882bd0E81112D305A970Eb08d02",
            "0x3b75Dd318Dd0f3E1Faa50128f1B3B0d67Cf5eF50",
            "0x587C4526d4134cad229E8beA5007ACf30Dc7e8Dd",
            "0xE6d7Ccc73e0F7E1063E2204ffFA7742CC25E3B38",
            "0x095A52eccB642AC82FF5Cb9059A82D5c4d2272df",
            "0x71324d35F7bCA2Db7D5afe3824531101C3e0Bf33",
            "0x70186F7e49FD47EEacDc842C51BDB3598614a162",
            "0xba0D0DdC2f2D479A53154db77002A3deC5f6e0b9",
            "0xc7BDeC4B5FE52BD0DF67929B42DD7db86397783e",
            "0x79b4194C0dA918bd73737B97977A5999329f8764",
        ],
    },
};
