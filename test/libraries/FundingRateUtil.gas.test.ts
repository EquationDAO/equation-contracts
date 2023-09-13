import {ethers} from "hardhat";
import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {expectSnapshotGasCost} from "../shared/snapshotGasCost";
import {
    DECIMALS_18,
    DECIMALS_6,
    BASIS_POINTS_DIVISOR,
    mulDiv,
    Q96,
    Rounding,
    SIDE_LONG,
    toPriceX96,
    toX96,
} from "../shared/Constants";

describe("FundingRateUtil gas tests", () => {
    async function deployFixture() {
        const FundingRateUtil = await ethers.getContractFactory("FundingRateUtil");
        const _fundingRateUtil = await FundingRateUtil.deploy();
        await _fundingRateUtil.deployed();

        const FundingRateUtilTest = await ethers.getContractFactory("FundingRateUtilTest", {
            libraries: {
                FundingRateUtil: _fundingRateUtil.address,
            },
        });
        const fundingRateUtil = await FundingRateUtilTest.deploy();
        await fundingRateUtil.deployed();
        const lastTimestamp = await time.latest();
        const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
        await time.setNextBlockTimestamp(nextHourBegin);
        await fundingRateUtil.updateSample(nextHourBegin, 0, 0);
        return {fundingRateUtil, nextHourBegin};
    }

    describe("#samplePremiumRate", () => {
        const secondsDelta = [3, 24, 1900, 3700, 7200, 9000];
        secondsDelta.forEach((delta) => {
            it(`time delta is ${delta} seconds`, async () => {
                const {fundingRateUtil, nextHourBegin} = await loadFixture(deployFixture);
                await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, 1000_0000n * 10n ** 6n);
                await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, 1669924655746900478036363838n);
                await fundingRateUtil.samplePremiumRate(125, nextHourBegin + delta);

                await expectSnapshotGasCost(fundingRateUtil.gasUsed());
            });
        });
    });

    describe("#calculateFundingRateGrowthX96", () => {
        it("fundingRateDeltaX96 is positive", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);

            let globalPosition = newGlobalPosition();
            globalPosition.longSize = 10000n;
            globalPosition.shortSize = 15000n;
            globalPosition.longFundingRateGrowthX96 = toX96("10000");
            globalPosition.shortFundingRateGrowthX96 = toX96("10000");
            let fundingRateDeltaX96 = mulDiv(10000n, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
            const maxFundingRate = 10000n;
            const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

            await fundingRateUtil.calculateFundingRateGrowthX96(
                globalPosition,
                fundingRateDeltaX96,
                maxFundingRate,
                indexPriceX96
            );
            await expectSnapshotGasCost(fundingRateUtil.gasUsed());
        });

        it("fundingRateDeltaX96 is negative", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);

            let globalPosition = newGlobalPosition();
            globalPosition.longSize = 10000n;
            globalPosition.shortSize = 15000n;
            globalPosition.longFundingRateGrowthX96 = toX96("10000");
            globalPosition.shortFundingRateGrowthX96 = toX96("10000");
            let fundingRateDeltaX96 = -mulDiv(10000n, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
            const maxFundingRate = 10000n;
            const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

            await fundingRateUtil.calculateFundingRateGrowthX96(
                globalPosition,
                fundingRateDeltaX96,
                maxFundingRate,
                indexPriceX96
            );
            await expectSnapshotGasCost(fundingRateUtil.gasUsed());
        });

        it("receivedSize is zero and globalLiquidity is positive", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);

            await fundingRateUtil.updateGlobalRiskBufferFund(10000n, 10002n);
            let globalPosition = newGlobalPosition();
            globalPosition.longSize = Q96;
            globalPosition.shortSize = 0n;
            globalPosition.longFundingRateGrowthX96 = toX96("10000");
            globalPosition.shortFundingRateGrowthX96 = toX96("10000");
            let fundingRateDeltaX96 = mulDiv(10000n, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
            const maxFundingRate = 10000n;
            const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

            await fundingRateUtil.calculateFundingRateGrowthX96(
                globalPosition,
                fundingRateDeltaX96,
                maxFundingRate,
                indexPriceX96
            );
            await expectSnapshotGasCost(fundingRateUtil.gasUsed());
        });

        it("receivedSize is zero and globalLiquidity is zero", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);

            await fundingRateUtil.updateGlobalRiskBufferFund(10000n, 10002n);
            let globalPosition = newGlobalPosition();
            globalPosition.longSize = Q96;
            globalPosition.shortSize = 0n;
            globalPosition.longFundingRateGrowthX96 = toX96("10000");
            globalPosition.shortFundingRateGrowthX96 = toX96("10000");
            let fundingRateDeltaX96 = mulDiv(10000n, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
            const maxFundingRate = 10000n;
            const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

            await fundingRateUtil.calculateFundingRateGrowthX96(
                globalPosition,
                fundingRateDeltaX96,
                maxFundingRate,
                indexPriceX96
            );
            await expectSnapshotGasCost(fundingRateUtil.gasUsed());
        });
    });
});

function newGlobalPosition() {
    return {
        longSize: 0n,
        shortSize: 0n,
        longFundingRateGrowthX96: 0n,
        shortFundingRateGrowthX96: 0n,
    };
}
