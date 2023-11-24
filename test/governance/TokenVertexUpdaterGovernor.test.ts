import {ethers} from "hardhat";
import {expect} from "chai";
import {concatPoolCreationCode} from "../shared/creationCode";
import {newTokenConfig, newTokenFeeRateConfig, newTokenPriceConfig} from "../shared/tokenConfig";
import {initializePoolByteCode} from "../shared/address";

describe("TokenVertexUpdaterGovernor", () => {
    async function deployFixture() {
        const [s0, s1, s2] = await ethers.getSigners();

        const zeroAddress = "0x0000000000000000000000000000000000000000";

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

        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        const poolFactory = await PoolFactory.deploy(
            zeroAddress,
            zeroAddress,
            zeroAddress,
            zeroAddress,
            zeroAddress,
            zeroAddress
        );
        await poolFactory.deployed();
        await concatPoolCreationCode(poolFactory);
        await poolFactory.enableToken(zeroAddress, newTokenConfig(), newTokenFeeRateConfig(), newTokenPriceConfig());

        const TokenVertexUpdaterGovernor = await ethers.getContractFactory("TokenVertexUpdaterGovernor");
        const tokenVertexUpdaterGovernor = await TokenVertexUpdaterGovernor.deploy(
            s0.address,
            s1.address,
            poolFactory.address
        );

        await poolFactory.changeGov(tokenVertexUpdaterGovernor.address);
        await tokenVertexUpdaterGovernor.execute(
            poolFactory.address,
            0,
            PoolFactory.interface.encodeFunctionData("acceptGov", [])
        );

        return {s0, s1, s2, zeroAddress, tokenVertexUpdaterGovernor, poolFactory};
    }

    it("updateTokenVertexConfig test", async () => {
        const {s0, s1, s2, zeroAddress, tokenVertexUpdaterGovernor, poolFactory} = await deployFixture();
        const balanceRateList = [0n, 100000n, 2000000n, 3000000n, 4000000n, 5000000n, 6000000n]; // 0->1%->2%...6%
        const premiumRateList = [0n, 60000n, 200000n, 250000n, 300000n, 700000n, 11000000n]; // [0%. 0.06%, 0.2%, 0.25%, 0.3%, 0.7%, 11%]
        let packedBalanceRate = 0n;
        let packedPremiumRate = 0n;
        for (let i = 0; i < balanceRateList.length; i++) {
            packedBalanceRate += balanceRateList[i] << (32n * BigInt(i));
            packedPremiumRate += premiumRateList[i] << (32n * BigInt(i));
        }
        const regexp: RegExp = /is missing role 0x0833596c19f8afe7d32bf2c778d80a2e2b0dcaa54c9ed6c8df6d646a481f4f89$/;
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s0)
                .updateTokenVertexConfig(zeroAddress, 100000000000000n, packedBalanceRate, packedPremiumRate)
        ).to.be.revertedWith(regexp);
        await expect(
            tokenVertexUpdaterGovernor
                .connect(s2)
                .updateTokenVertexConfig(zeroAddress, 100000000000000n, packedBalanceRate, packedPremiumRate)
        ).to.be.revertedWith(regexp);

        const beforeTokenConfigs = await poolFactory.tokenConfigs(zeroAddress);
        const beforeTokenFeeRateConfigs = await poolFactory.tokenFeeRateConfigs(zeroAddress);

        await tokenVertexUpdaterGovernor
            .connect(s1)
            .updateTokenVertexConfig(zeroAddress, 100000000000000n, packedBalanceRate, packedPremiumRate);
        for (let i = 0; i < balanceRateList.length; i++) {
            const {balanceRate, premiumRate} = await poolFactory.tokenPriceVertexConfigs(zeroAddress, i);
            expect(balanceRate).eq(balanceRateList[i]);
            expect(premiumRate).eq(premiumRateList[i]);
        }
        const {maxPriceImpactLiquidity} = await poolFactory.tokenPriceConfigs(zeroAddress);
        expect(maxPriceImpactLiquidity).eq(100000000000000n);
        const afterTokenConfigs = await poolFactory.tokenConfigs(zeroAddress);
        const afterTokenFeeRateConfigs = await poolFactory.tokenFeeRateConfigs(zeroAddress);
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
