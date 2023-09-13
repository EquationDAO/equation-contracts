import {ethers} from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {concatPoolCreationCode} from "./shared/creationCode";
import {expectSnapshotGasCost} from "./shared/snapshotGasCost";
import {initializePoolByteCode} from "./shared/address";
import {ERC20Test} from "../typechain-types";
import {DECIMALS_18, DECIMALS_6, toPriceX96} from "./shared/Constants";
import {newTokenConfig, newTokenFeeRateConfig, newTokenPriceConfig} from "./shared/tokenConfig";

describe("PoolFactory gas tests", () => {
    async function deployFixture() {
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

        const MockRewardFarmCallback = await ethers.getContractFactory("MockRewardFarmCallback");
        const mockRewardFarmCallback = await MockRewardFarmCallback.deploy();
        await mockRewardFarmCallback.deployed();

        const ERC20 = await ethers.getContractFactory("ERC20Test");
        const USD = (await ERC20.deploy("USDC", "USDC", 6, 100_000_000n * 10n ** 18n)) as ERC20Test;
        await USD.deployed();
        const ETH = (await ERC20.deploy("ETH", "ETH", 18, 100_000_000n * 10n ** 18n)) as ERC20Test;
        await ETH.deployed();

        const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
        const priceFeed = await MockPriceFeed.deploy();
        await priceFeed.deployed();
        await priceFeed.setMinPriceX96(ETH.address, toPriceX96("1808.234", DECIMALS_18, DECIMALS_6));
        await priceFeed.setMaxPriceX96(ETH.address, toPriceX96("1808.235", DECIMALS_18, DECIMALS_6));

        const EFC = await ethers.getContractFactory("MockEFC");
        const efc = await EFC.deploy();
        await efc.deployed();
        await efc.initialize(100n, mockRewardFarmCallback.address);

        const [gov, other, router, feeDistributor] = await ethers.getSigners();
        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        const poolFactory = await PoolFactory.deploy(
            USD.address,
            efc.address,
            router.address,
            priceFeed.address,
            feeDistributor.address,
            mockRewardFarmCallback.address
        );
        await poolFactory.deployed();
        await concatPoolCreationCode(poolFactory);

        const Pool = await ethers.getContractFactory("Pool", {
            libraries: {
                PoolUtil: poolUtil.address,
                FundingRateUtil: fundingRateUtil.address,
                PriceUtil: priceUtil.address,
                PositionUtil: positionUtil.address,
                LiquidityPositionUtil: liquidityPositionUtil.address,
            },
        });

        return {
            gov,
            other,
            USD,
            ETH,
            router,
            priceFeed,
            feeDistributor,
            efc,
            mockRewardFarmCallback,
            poolFactory,
            Pool,
        };
    }

    it("#createPool", async () => {
        const {poolFactory, ETH} = await loadFixture(deployFixture);
        await poolFactory.enableToken(ETH.address, newTokenConfig(), newTokenFeeRateConfig(), newTokenPriceConfig());

        await expectSnapshotGasCost(poolFactory.estimateGas.createPool(ETH.address));
    });
});
