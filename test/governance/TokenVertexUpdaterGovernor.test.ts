import {ethers} from "hardhat";
import {expect} from "chai";
import {concatPoolCreationCode} from "../shared/creationCode";
import {newTokenConfig, newTokenFeeRateConfig, newTokenPriceConfig} from "../shared/tokenConfig";
import {computePoolAddress, initializePoolByteCode} from "../shared/address";
import {time} from "@nomicfoundation/hardhat-network-helpers";
import {ERC20Test} from "../../typechain-types";
import {DECIMALS_18, DECIMALS_6, toPriceX96} from "../shared/Constants";
import {BigNumber} from "ethers";

describe("TokenVertexUpdaterGovernor", () => {
    async function deployFixture() {
        const [s0, s1, s2] = await ethers.getSigners();

        const PoolUtil = await ethers.getContractFactory("PoolUtil");
        const poolUtil = await PoolUtil.deploy();
        await poolUtil.deployed();

        const FundingRateUtil = await ethers.getContractFactory("FundingRateUtil");
        const fundingRateUtil = await FundingRateUtil.deploy();
        await fundingRateUtil.deployed();

        const PriceUtil = await ethers.getContractFactory("PriceUtil");
        const priceUtil = await PriceUtil.deploy();
        await priceUtil.deployed();

        const PositionUtil = await ethers.getContractFactory("PositionUtil");
        const positionUtil = await PositionUtil.deploy();
        await positionUtil.deployed();

        const LiquidityPositionUtil = await ethers.getContractFactory("LiquidityPositionUtil");
        const liquidityPositionUtil = await LiquidityPositionUtil.deploy();
        await liquidityPositionUtil.deployed();

        await initializePoolByteCode(
            poolUtil.address,
            fundingRateUtil.address,
            priceUtil.address,
            positionUtil.address,
            liquidityPositionUtil.address
        );

        const ERC20 = await ethers.getContractFactory("ERC20Test");
        const USDC = (await ERC20.deploy("USDC", "USDC", 6, 100_000_000n * 10n ** 18n)) as ERC20Test;
        await USDC.deployed();
        const ETH = (await ERC20.deploy("ETH", "ETH", 18, 100_000_000n * 10n ** 18n)) as ERC20Test;
        await ETH.deployed();

        const FeeDistributor = await ethers.getContractFactory("MockFeeDistributor");
        const feeDistributor = await FeeDistributor.deploy();
        await feeDistributor.deployed();

        const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
        const mockPriceFeed = await MockPriceFeed.deploy();
        await mockPriceFeed.deployed();
        await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1808.234", DECIMALS_18, DECIMALS_6));
        await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1808.235", DECIMALS_18, DECIMALS_6));

        const MockRewardFarmCallback = await ethers.getContractFactory("MockRewardFarmCallback");
        const mockRewardFarmCallback = await MockRewardFarmCallback.deploy();
        await mockRewardFarmCallback.deployed();

        const MockFeeDistributorCallback = await ethers.getContractFactory("MockFeeDistributorCallback");
        const mockFeeDistributorCallback = await MockFeeDistributorCallback.deploy();
        await mockFeeDistributorCallback.deployed();

        const EFC = await ethers.getContractFactory("MockEFC");
        const efc = await EFC.deploy();
        await efc.deployed();
        await efc.initialize(100n, mockRewardFarmCallback.address);

        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        const poolFactory = await PoolFactory.deploy(
            USDC.address,
            efc.address,
            s0.address,
            mockPriceFeed.address,
            feeDistributor.address,
            mockRewardFarmCallback.address
        );
        await poolFactory.deployed();
        await concatPoolCreationCode(poolFactory);
        await poolFactory.enableToken(ETH.address, newTokenConfig(), newTokenFeeRateConfig(), newTokenPriceConfig());
        await poolFactory.createPool(ETH.address);

        const TokenVertexUpdaterGovernor = await ethers.getContractFactory("TokenVertexUpdaterGovernor");
        const tokenVertexUpdaterGovernor = await TokenVertexUpdaterGovernor.deploy(
            s0.address,
            s1.address,
            poolFactory.address
        );
        const poolAddress = computePoolAddress(poolFactory.address, ETH.address, USDC.address);
        const Pool = await ethers.getContractFactory("Pool", {
            libraries: {
                PoolUtil: poolUtil.address,
                FundingRateUtil: fundingRateUtil.address,
                PriceUtil: priceUtil.address,
                PositionUtil: positionUtil.address,
                LiquidityPositionUtil: liquidityPositionUtil.address,
            },
        });
        const pool = Pool.attach(poolAddress);

        await poolFactory.changeGov(tokenVertexUpdaterGovernor.address);
        await tokenVertexUpdaterGovernor.execute(
            poolFactory.address,
            0,
            PoolFactory.interface.encodeFunctionData("acceptGov", [])
        );

        return {s0, s1, s2, tokenVertexUpdaterGovernor, poolFactory, pool, ETH, USDC};
    }

    it("updateTokenVertexConfigBalanceRates test", async () => {
        const {s0, s1, s2, tokenVertexUpdaterGovernor, poolFactory, pool, ETH, USDC} = await deployFixture();
        let balanceRateList = [0n, 100000n, 2000000n, 3000000n, 4000000n, 5000000n, 6000000n]; // 0->1%->2%...6%
        let previousPremiumRateList = [];
        for (let i = 0; i < balanceRateList.length; i++) {
            const {balanceRate, premiumRate} = await poolFactory.tokenPriceVertexConfigs(ETH.address, i);
            previousPremiumRateList.push(BigInt(premiumRate));
        }
        let packedBalanceRate = 0n;
        for (let i = 0; i < balanceRateList.length; i++) {
            packedBalanceRate += balanceRateList[i] << (32n * BigInt(i));
        }
        const regexp: RegExp = /is missing role 0x0833596c19f8afe7d32bf2c778d80a2e2b0dcaa54c9ed6c8df6d646a481f4f89$/;
        const now = await time.latest();
        const packedTokenTimestamp = BigNumber.from(ETH.address).toBigInt() + BigInt(now) * 2n ** 160n;
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s0)
                .updateTokenVertexConfigBalanceRates(packedTokenTimestamp, packedBalanceRate)
        ).to.be.revertedWith(regexp);
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s2)
                .updateTokenVertexConfigBalanceRates(packedTokenTimestamp, packedBalanceRate)
        ).to.be.revertedWith(regexp);

        const beforeTokenConfigs = await poolFactory.tokenConfigs(ETH.address);
        const beforeTokenFeeRateConfigs = await poolFactory.tokenFeeRateConfigs(ETH.address);
        await USDC.transfer(pool.address, beforeTokenConfigs.minMarginPerPosition);
        await pool.openLiquidityPosition(
            s0.address,
            beforeTokenConfigs.minMarginPerPosition,
            beforeTokenConfigs.minMarginPerPosition.mul(200n)
        );

        const stalePackedTokenTimestamp = BigNumber.from(ETH.address).toBigInt() + BigInt(now - 61) * 2n ** 160n;
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s1)
                .updateTokenVertexConfigBalanceRates(stalePackedTokenTimestamp, packedBalanceRate)
        ).to.be.revertedWithCustomError(tokenVertexUpdaterGovernor, "StaleConfig");

        await tokenVertexUpdaterGovernor
            .connect(s1)
            .updateTokenVertexConfigBalanceRates(packedTokenTimestamp, packedBalanceRate);
        for (let i = 0; i < balanceRateList.length; i++) {
            const {balanceRate, premiumRate} = await poolFactory.tokenPriceVertexConfigs(ETH.address, i);
            expect(balanceRate).eq(balanceRateList[i]);
            expect(premiumRate).eq(previousPremiumRateList[i]);
        }
        const {maxPriceImpactLiquidity} = await poolFactory.tokenPriceConfigs(ETH.address);
        expect(maxPriceImpactLiquidity).eq(beforeTokenConfigs.minMarginPerPosition.mul(200n));
        const afterTokenConfigs = await poolFactory.tokenConfigs(ETH.address);
        const afterTokenFeeRateConfigs = await poolFactory.tokenFeeRateConfigs(ETH.address);
        expect(JSON.stringify(beforeTokenConfigs)).equals(JSON.stringify(afterTokenConfigs));
        expect(JSON.stringify(beforeTokenFeeRateConfigs)).equals(JSON.stringify(afterTokenFeeRateConfigs));
    });

    it("updateTokenVertexConfigPremiumRate test", async () => {
        const {s0, s1, s2, tokenVertexUpdaterGovernor, poolFactory, pool, ETH, USDC} = await deployFixture();
        let previousBalanceRateList = []; // 0->1%->2%...6%
        let premiumRateList = [0n, 60000n, 200000n, 250000n, 300000n, 700000n, 11000000n]; // [0%. 0.06%, 0.2%, 0.25%, 0.3%, 0.7%, 11%]
        for (let i = 0; i < premiumRateList.length; i++) {
            const {balanceRate, premiumRate} = await poolFactory.tokenPriceVertexConfigs(ETH.address, i);
            previousBalanceRateList.push(BigInt(balanceRate));
        }
        let packedPremiumRate = 0n;
        for (let i = 0; i < premiumRateList.length; i++) {
            packedPremiumRate += premiumRateList[i] << (32n * BigInt(i));
        }
        const regexp: RegExp = /is missing role 0x0833596c19f8afe7d32bf2c778d80a2e2b0dcaa54c9ed6c8df6d646a481f4f89$/;
        const now = await time.latest();
        const packedTokenTimestamp = BigNumber.from(ETH.address).toBigInt() + BigInt(now) * 2n ** 160n;
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s0)
                .updateTokenVertexConfigPremiumRates(packedTokenTimestamp, packedPremiumRate)
        ).to.be.revertedWith(regexp);
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s2)
                .updateTokenVertexConfigPremiumRates(packedTokenTimestamp, packedPremiumRate)
        ).to.be.revertedWith(regexp);

        const beforeTokenConfigs = await poolFactory.tokenConfigs(ETH.address);
        const beforeTokenFeeRateConfigs = await poolFactory.tokenFeeRateConfigs(ETH.address);
        await USDC.transfer(pool.address, beforeTokenConfigs.minMarginPerPosition);
        await pool.openLiquidityPosition(
            s0.address,
            beforeTokenConfigs.minMarginPerPosition,
            beforeTokenConfigs.minMarginPerPosition.mul(200n)
        );

        const stalePackedTokenTimestamp = BigNumber.from(ETH.address).toBigInt() + BigInt(now - 61) * 2n ** 160n;
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s1)
                .updateTokenVertexConfigPremiumRates(stalePackedTokenTimestamp, packedPremiumRate)
        ).to.be.revertedWithCustomError(tokenVertexUpdaterGovernor, "StaleConfig");

        await tokenVertexUpdaterGovernor
            .connect(s1)
            .updateTokenVertexConfigPremiumRates(packedTokenTimestamp, packedPremiumRate);
        for (let i = 0; i < premiumRateList.length; i++) {
            const {balanceRate, premiumRate} = await poolFactory.tokenPriceVertexConfigs(ETH.address, i);
            expect(balanceRate).eq(previousBalanceRateList[i]);
            expect(premiumRate).eq(premiumRateList[i]);
        }
        const {maxPriceImpactLiquidity} = await poolFactory.tokenPriceConfigs(ETH.address);
        expect(maxPriceImpactLiquidity).eq(beforeTokenConfigs.minMarginPerPosition.mul(200n));
        const afterTokenConfigs = await poolFactory.tokenConfigs(ETH.address);
        const afterTokenFeeRateConfigs = await poolFactory.tokenFeeRateConfigs(ETH.address);
        expect(JSON.stringify(beforeTokenConfigs)).equals(JSON.stringify(afterTokenConfigs));
        expect(JSON.stringify(beforeTokenFeeRateConfigs)).equals(JSON.stringify(afterTokenFeeRateConfigs));
    });

    it("execute test", async () => {
        const {s0, s1, s2, tokenVertexUpdaterGovernor, poolFactory} = await deployFixture();
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        const regexp: RegExp = /is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775$/;
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s1)
                .execute(poolFactory.address, 0, PoolFactory.interface.encodeFunctionData("changeGov", [s2.address]))
        ).to.be.revertedWith(regexp);
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s2)
                .execute(poolFactory.address, 0, PoolFactory.interface.encodeFunctionData("changeGov", [s2.address]))
        ).to.be.revertedWith(regexp);
        await tokenVertexUpdaterGovernor
            .connect(s0)
            .execute(poolFactory.address, 0, PoolFactory.interface.encodeFunctionData("changeGov", [s2.address]));
        await poolFactory.connect(s2).acceptGov();
        expect(await poolFactory.gov()).to.equal(s2.address);
    });
});
