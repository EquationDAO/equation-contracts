import {ethers} from "hardhat";
import {expect} from "chai";
import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {
    BASIS_POINTS_DIVISOR,
    DECIMALS_18,
    DECIMALS_6,
    isLongSide,
    mulDiv,
    PREMIUM_RATE_AVG_DENOMINATOR,
    PREMIUM_RATE_CLAMP_BOUNDARY_X96,
    Q96,
    Rounding,
    Side,
    SIDE_LONG,
    SIDE_SHORT,
    toPriceX96,
    toX96,
} from "../shared/Constants";

describe("FundingRateUtil", () => {
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

        return {
            fundingRateUtil,
            _fundingRateUtil,
        };
    }

    describe("#samplePremiumRate", () => {
        it("should not adjust funding rate when time delta is less than 5 seconds", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, 1000_0000n * 10n ** 6n);
            await fundingRateUtil.updateSample(nextHourBegin, 0, 0);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, 1669924655746900478036363838n);

            await fundingRateUtil.samplePremiumRate(125, nextHourBegin + 3);
            expect(await fundingRateUtil.shouldAdjustFundingRate()).to.false;
        });

        it("should not adjust sample when time delta is less than 5 seconds", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, 1000_0000n * 10n ** 6n);
            await fundingRateUtil.updateSample(nextHourBegin, 1, 2);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, 1669924655746900478036363838n);

            await fundingRateUtil.samplePremiumRate(125, nextHourBegin + 9);

            const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} = await fundingRateUtil.sample();
            expect(lastAdjustFundingRateTime).to.eq(nextHourBegin);
            expect(sampleCount).to.eq(1);
            expect(cumulativePremiumRateX96).to.eq(2);
        });

        it("should adjust sample when time delta is greater than 5 seconds", async () => {
            const {fundingRateUtil, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updateSample(nextHourBegin, 3, 2);

            const netSize = 10n;
            const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidity = 100n * 10n ** 6n;
            await fundingRateUtil.updatePosition(SIDE_LONG, netSize, priceX96, liquidity);
            const premiumRateX96 = mulDiv(netSize, priceX96, liquidity, Rounding.Up);
            const premiumRateX96Int = -premiumRateX96;
            const sampleCountDelta = (24n - 3n * 5n) / 5n;
            const sampleCountAfter = 3n + sampleCountDelta;
            const cumulativePremiumRateAfterX96 =
                2n + (premiumRateX96Int * (3n + 1n + sampleCountAfter) * sampleCountDelta) / 2n;

            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, liquidity);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, premiumRateX96);
            await expect(fundingRateUtil.samplePremiumRate(125, nextHourBegin + 24))
                .to.emit(_fundingRateUtil.attach(fundingRateUtil.address), "GlobalFundingRateSampleAdjusted")
                .withArgs(sampleCountAfter, cumulativePremiumRateAfterX96);

            const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} = await fundingRateUtil.sample();
            expect(lastAdjustFundingRateTime).to.eq(nextHourBegin);
            expect(sampleCount).to.eq(sampleCountAfter);
            expect(cumulativePremiumRateX96).to.eq(cumulativePremiumRateAfterX96);
        });

        it("should not adjust funding rate when sample count is less than 720", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updateSample(nextHourBegin, 718, -2);

            const netSize = 10n;
            const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidity = 100n * 10n ** 6n;
            await fundingRateUtil.updatePosition(SIDE_LONG, netSize, priceX96, liquidity);
            const premiumRateX96 = mulDiv(netSize, priceX96, liquidity, Rounding.Up);
            const sampleCountDelta = (3599n - 718n * 5n) / 5n;
            const sampleCountAfter = 718n + sampleCountDelta;
            expect(sampleCountAfter).to.lt(720);

            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, liquidity);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, premiumRateX96);
            await fundingRateUtil.samplePremiumRate(125, nextHourBegin + 3599);
            expect(await fundingRateUtil.shouldAdjustFundingRate()).to.false;
        });

        it("should adjust sample when sample count is less than 720", async () => {
            const {fundingRateUtil, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updateSample(nextHourBegin, 718, 2);

            const netSize = 10n;
            const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidity = 100n * 10n ** 6n;
            await fundingRateUtil.updatePosition(SIDE_LONG, netSize, priceX96, liquidity);
            const premiumRateX96 = mulDiv(netSize, priceX96, liquidity, Rounding.Up);
            const premiumRateX96Int = -premiumRateX96;
            const sampleCountDelta = (3599n - 718n * 5n) / 5n;
            const sampleCountAfter = 718n + sampleCountDelta;
            expect(sampleCountAfter).to.lt(720);
            const cumulativePremiumRateAfterX96 =
                2n + (premiumRateX96Int * (718n + 1n + sampleCountAfter) * sampleCountDelta) / 2n;

            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, liquidity);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, premiumRateX96);
            await expect(fundingRateUtil.samplePremiumRate(125, nextHourBegin + 3599))
                .to.emit(_fundingRateUtil.attach(fundingRateUtil.address), "GlobalFundingRateSampleAdjusted")
                .withArgs(sampleCountAfter, cumulativePremiumRateAfterX96);
            const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} = await fundingRateUtil.sample();
            expect(lastAdjustFundingRateTime).to.eq(nextHourBegin);
            expect(sampleCount).to.eq(sampleCountAfter);
            expect(cumulativePremiumRateX96).to.eq(cumulativePremiumRateAfterX96);
        });

        it("should adjust sample when time delta is greater than 60 seconds", async () => {
            const {fundingRateUtil, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updateSample(nextHourBegin, 3, 2);

            const netSize = 10n;
            const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidity = 100n * 10n ** 6n;
            await fundingRateUtil.updatePosition(SIDE_SHORT, netSize, priceX96, liquidity);
            const premiumRateX96 = mulDiv(netSize, priceX96, liquidity, Rounding.Up);
            const premiumRateX96Int = -premiumRateX96;
            const sampleCountDelta = (87n - 3n * 5n) / 5n;
            const sampleCountAfter = 3n + sampleCountDelta;
            expect(sampleCountAfter).to.lt(720);
            const cumulativePremiumRateAfterX96 =
                2n + (premiumRateX96Int * (3n + 1n + sampleCountAfter) * sampleCountDelta) / 2n;

            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, liquidity);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, premiumRateX96);
            await expect(fundingRateUtil.samplePremiumRate(125, nextHourBegin + 87))
                .to.emit(_fundingRateUtil.attach(fundingRateUtil.address), "GlobalFundingRateSampleAdjusted")
                .withArgs(sampleCountAfter, cumulativePremiumRateAfterX96);
            const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} = await fundingRateUtil.sample();
            expect(lastAdjustFundingRateTime).to.eq(nextHourBegin);
            expect(sampleCount).to.eq(sampleCountAfter);
            expect(cumulativePremiumRateX96).to.eq(cumulativePremiumRateAfterX96);
        });

        it("should adjust funding rate when sample count is equal to 720", async () => {
            const {fundingRateUtil, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updateSample(nextHourBegin, 3, 2);

            const netSize = 10n;
            const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidity = 100n * 10n ** 6n;
            await fundingRateUtil.updatePosition(SIDE_SHORT, netSize, priceX96, liquidity);
            const premiumRateX96 = mulDiv(netSize, priceX96, liquidity, Rounding.Up);
            const premiumRateX96Int = premiumRateX96;
            const sampleCountDelta = (3604n - 3n * 5n) / 5n;
            const sampleCountAfter = 3n + sampleCountDelta;
            expect(sampleCountAfter).to.eq(720);
            const cumulativePremiumRateAfterX96 =
                2n + (premiumRateX96Int * (3n + 1n + sampleCountAfter) * sampleCountDelta) / 2n;

            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, liquidity);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, premiumRateX96);
            await expect(fundingRateUtil.samplePremiumRate(125, nextHourBegin + 3604))
                .to.emit(_fundingRateUtil.attach(fundingRateUtil.address), "GlobalFundingRateSampleAdjusted")
                .withArgs(0n, 0n);
            const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} = await fundingRateUtil.sample();
            expect(lastAdjustFundingRateTime).to.eq(nextHourBegin + 3600);
            expect(sampleCount).to.eq(0);
            expect(cumulativePremiumRateX96).to.eq(0n);

            expect(await fundingRateUtil.shouldAdjustFundingRate()).to.true;
            const balanceRateAvgX96 =
                cumulativePremiumRateAfterX96 >= 0n
                    ? mulDiv(cumulativePremiumRateAfterX96, 1n, 259560n * 8n, Rounding.Up)
                    : -mulDiv(-cumulativePremiumRateAfterX96, 1n, 259560n * 8n, Rounding.Up);
            const fundingRateDeltaX96 = balanceRateAvgX96 + clamp(balanceRateAvgX96, 125n);
            expect(await fundingRateUtil.fundingRateDeltaX96()).to.eq(fundingRateDeltaX96);
        });

        it("should adjust funding rate when sample count is greater than 1440", async () => {
            const {fundingRateUtil, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updateSample(nextHourBegin, 3, 2);

            const netSize = 10n;
            const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidity = 100n * 10n ** 6n;
            await fundingRateUtil.updatePosition(SIDE_SHORT, netSize, priceX96, liquidity);
            const premiumRateX96 = mulDiv(netSize, priceX96, liquidity, Rounding.Up);
            const premiumRateX96Int = premiumRateX96;
            const sampleCountDelta = (3600n - 3n * 5n) / 5n;
            const sampleCountAfter = 3n + sampleCountDelta;
            const cumulativePremiumRateAfterX96 =
                2n + (premiumRateX96Int * (3n + 1n + sampleCountAfter) * sampleCountDelta) / 2n;

            await fundingRateUtil.updatePosition(SIDE_LONG, 0n, 0n, liquidity);
            await fundingRateUtil.updatePriceState(1000_0000n * 10n ** 6n, premiumRateX96);
            await expect(fundingRateUtil.samplePremiumRate(125, nextHourBegin + 36004))
                .to.emit(_fundingRateUtil.attach(fundingRateUtil.address), "GlobalFundingRateSampleAdjusted")
                .withArgs(0n, 0n);
            const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} = await fundingRateUtil.sample();
            expect(lastAdjustFundingRateTime).to.eq(nextHourBegin + 3600);
            expect(sampleCount).to.eq(0);
            expect(cumulativePremiumRateX96).to.eq(0n);

            expect(await fundingRateUtil.shouldAdjustFundingRate()).to.true;
            const balanceRateAvgX96 =
                cumulativePremiumRateAfterX96 >= 0n
                    ? mulDiv(cumulativePremiumRateAfterX96, 1n, PREMIUM_RATE_AVG_DENOMINATOR, Rounding.Up)
                    : -mulDiv(-cumulativePremiumRateAfterX96, 1n, PREMIUM_RATE_AVG_DENOMINATOR, Rounding.Up);
            const fundingRateDeltaX96 = balanceRateAvgX96 + clamp(balanceRateAvgX96, 125n);
            expect(await fundingRateUtil.fundingRateDeltaX96()).to.eq(fundingRateDeltaX96);
        });
    });

    describe("#calculateFundingRateGrowthX96", () => {
        it("should pass if fundingRateDeltaX96 is zero", async () => {
            const {fundingRateUtil} = await loadFixture(deployFixture);

            let globalPosition = newGlobalPosition();
            globalPosition.longSize = 10000n;
            globalPosition.shortSize = 10000n;
            globalPosition.longFundingRateGrowthX96 = toX96("10000");
            globalPosition.shortFundingRateGrowthX96 = toX96("10000");
            let fundingRateDeltaX96 = 0n;
            const maxFundingRate = 10000n;
            const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

            await fundingRateUtil.calculateFundingRateGrowthX96(
                globalPosition,
                fundingRateDeltaX96,
                maxFundingRate,
                indexPriceX96
            );
            expect(await fundingRateUtil.longFundingRateGrowthAfterX96()).to.eq(
                globalPosition.longFundingRateGrowthX96
            );
            expect(await fundingRateUtil.shortFundingRateGrowthAfterX96()).to.eq(
                globalPosition.shortFundingRateGrowthX96
            );
        });

        describe("fundingRateDeltaX96 is positive", () => {
            it("should pass if fundingRateDeltaX96 is greater than maxFundingRateX96", async () => {
                const {fundingRateUtil} = await loadFixture(deployFixture);

                let globalPosition = newGlobalPosition();
                globalPosition.longSize = 10000n;
                globalPosition.shortSize = 15000n;
                globalPosition.longFundingRateGrowthX96 = toX96("10000");
                globalPosition.shortFundingRateGrowthX96 = toX96("10000");
                let fundingRateDeltaX96 = mulDiv(11000n, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
                const maxFundingRate = 10000n;
                const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

                const maxFundingRateX96 = mulDiv(maxFundingRate, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
                const paidFundingRateGrowthDeltaX96 = mulDiv(indexPriceX96, maxFundingRateX96, Q96, Rounding.Up);
                expect(paidFundingRateGrowthDeltaX96).to.gt(0n);
                const receivedFundingRateGrowthDeltaX96 = mulDiv(
                    globalPosition.longSize,
                    paidFundingRateGrowthDeltaX96,
                    globalPosition.shortSize
                );
                expect(receivedFundingRateGrowthDeltaX96).to.gt(0n);

                await fundingRateUtil.calculateFundingRateGrowthX96(
                    globalPosition,
                    fundingRateDeltaX96,
                    maxFundingRate,
                    indexPriceX96
                );
                expect(await fundingRateUtil.longFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.longFundingRateGrowthX96 - paidFundingRateGrowthDeltaX96
                );
                expect(await fundingRateUtil.shortFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.shortFundingRateGrowthX96 + receivedFundingRateGrowthDeltaX96
                );
                expect(await fundingRateUtil.clampedFundingRateDeltaX96()).to.eq(maxFundingRateX96);
            });

            it("should pass if shortSize is zero", async () => {
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

                const paidFundingRateGrowthDeltaX96 = mulDiv(indexPriceX96, fundingRateDeltaX96, Q96, Rounding.Up);
                expect(paidFundingRateGrowthDeltaX96).to.gt(0n);
                const riskBufferFundDelta = mulDiv(globalPosition.longSize, paidFundingRateGrowthDeltaX96, Q96);
                expect(riskBufferFundDelta).to.gt(0n);
                await fundingRateUtil.calculateFundingRateGrowthX96(
                    globalPosition,
                    fundingRateDeltaX96,
                    maxFundingRate,
                    indexPriceX96
                );
                expect(await fundingRateUtil.longFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.longFundingRateGrowthX96 - paidFundingRateGrowthDeltaX96
                );
                expect(await fundingRateUtil.shortFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.shortFundingRateGrowthX96
                );
                expect(await fundingRateUtil.clampedFundingRateDeltaX96()).to.eq(fundingRateDeltaX96);
                const globalRiskBufferFund = await fundingRateUtil.globalRiskBufferFund();
                expect(globalRiskBufferFund.riskBufferFund).to.eq(10000n + riskBufferFundDelta);
            });
        });

        describe("fundingRateDeltaX96 is negative", () => {
            it("should pass if fundingRateDeltaX96 is less than -maxFundingRateX96", async () => {
                const {fundingRateUtil} = await loadFixture(deployFixture);

                let globalPosition = newGlobalPosition();
                globalPosition.longSize = 10000n;
                globalPosition.shortSize = 15000n;
                globalPosition.longFundingRateGrowthX96 = toX96("10000");
                globalPosition.shortFundingRateGrowthX96 = toX96("10000");
                let fundingRateDeltaX96 = -mulDiv(11000n, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
                const maxFundingRate = 10000n;
                const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

                const maxFundingRateX96 = mulDiv(maxFundingRate, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
                const paidFundingRateGrowthDeltaX96 = mulDiv(indexPriceX96, maxFundingRateX96, Q96, Rounding.Up);
                expect(paidFundingRateGrowthDeltaX96).to.gt(0n);
                const receivedFundingRateGrowthDeltaX96 = mulDiv(
                    globalPosition.shortSize,
                    paidFundingRateGrowthDeltaX96,
                    globalPosition.longSize
                );
                expect(receivedFundingRateGrowthDeltaX96).to.gt(0n);

                await fundingRateUtil.calculateFundingRateGrowthX96(
                    globalPosition,
                    fundingRateDeltaX96,
                    maxFundingRate,
                    indexPriceX96
                );
                expect(await fundingRateUtil.shortFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.shortFundingRateGrowthX96 - paidFundingRateGrowthDeltaX96
                );
                expect(await fundingRateUtil.longFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.longFundingRateGrowthX96 + receivedFundingRateGrowthDeltaX96
                );
                expect(await fundingRateUtil.clampedFundingRateDeltaX96()).to.eq(-maxFundingRateX96);
            });

            it("should pass if longSize is zero", async () => {
                const {fundingRateUtil} = await loadFixture(deployFixture);

                await fundingRateUtil.updateGlobalRiskBufferFund(10000n, 10002n);
                let globalPosition = newGlobalPosition();
                globalPosition.longSize = 0n;
                globalPosition.shortSize = Q96;
                globalPosition.longFundingRateGrowthX96 = toX96("10000");
                globalPosition.shortFundingRateGrowthX96 = toX96("10000");
                let fundingRateDeltaX96 = -mulDiv(10000n, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
                const maxFundingRate = 10000n;
                const indexPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);

                const paidFundingRateGrowthDeltaX96 = mulDiv(indexPriceX96, -fundingRateDeltaX96, Q96, Rounding.Up);
                expect(paidFundingRateGrowthDeltaX96).to.gt(0n);
                const riskBufferFundDelta = mulDiv(globalPosition.shortSize, paidFundingRateGrowthDeltaX96, Q96);
                expect(riskBufferFundDelta).to.gt(0n);
                await fundingRateUtil.calculateFundingRateGrowthX96(
                    globalPosition,
                    fundingRateDeltaX96,
                    maxFundingRate,
                    indexPriceX96
                );
                expect(await fundingRateUtil.longFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.longFundingRateGrowthX96
                );
                expect(await fundingRateUtil.shortFundingRateGrowthAfterX96()).to.eq(
                    globalPosition.shortFundingRateGrowthX96 - paidFundingRateGrowthDeltaX96
                );
                expect(await fundingRateUtil.clampedFundingRateDeltaX96()).to.eq(fundingRateDeltaX96);
                const globalRiskBufferFund = await fundingRateUtil.globalRiskBufferFund();
                expect(globalRiskBufferFund.riskBufferFund).to.eq(10000n + riskBufferFundDelta);
            });
        });
    });

    describe("#_samplePremiumRate", () => {
        it("should not overflow if premiumRateX96 is equal to type(uint128).max and sample count is equal to 720", async () => {
            const {fundingRateUtil, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await fundingRateUtil.updateSample(nextHourBegin, 0, 0);

            const premiumRateX96 = (1n << 128n) - 1n;
            async function test(side: Side) {
                await fundingRateUtil._samplePremiumRate(side, premiumRateX96, 125, nextHourBegin + 3600, 3600);
                const premiumRateX96Int = isLongSide(side) ? -premiumRateX96 : premiumRateX96;
                const sampleCountDelta = 720n;
                const sampleCountAfter = 720n;
                expect(sampleCountAfter).to.eq(720);
                const cumulativePremiumRateAfterX96 =
                    0n + (premiumRateX96Int * (0n + 1n + sampleCountAfter) * sampleCountDelta) / 2n;

                const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} =
                    await fundingRateUtil.sample();
                expect(lastAdjustFundingRateTime).to.eq(nextHourBegin + 3600);
                expect(sampleCount).to.eq(0);
                expect(cumulativePremiumRateX96).to.eq(0n);

                expect(await fundingRateUtil.shouldAdjustFundingRate()).to.true;
                const balanceRateAvgX96 =
                    cumulativePremiumRateAfterX96 >= 0n
                        ? mulDiv(cumulativePremiumRateAfterX96, 1n, 259560n * 8n, Rounding.Up)
                        : -mulDiv(-cumulativePremiumRateAfterX96, 1n, 259560n * 8n, Rounding.Up);
                const fundingRateDeltaX96 = balanceRateAvgX96 + clamp(balanceRateAvgX96, 125n);
                expect(fundingRateDeltaX96).to.not.eq(0n);
                expect(await fundingRateUtil.fundingRateDeltaX96()).to.eq(fundingRateDeltaX96);
            }
            await test(SIDE_LONG);
            await test(SIDE_SHORT);
        });
    });
});

function clamp(balanceRateAvgX96: bigint, interestRate: bigint): bigint {
    const interestRateX96 = mulDiv(interestRate, Q96, BASIS_POINTS_DIVISOR, Rounding.Up);
    const rateDeltaX96 = interestRateX96 - balanceRateAvgX96;
    if (rateDeltaX96 > PREMIUM_RATE_CLAMP_BOUNDARY_X96) {
        return PREMIUM_RATE_CLAMP_BOUNDARY_X96;
    } else if (rateDeltaX96 < -PREMIUM_RATE_CLAMP_BOUNDARY_X96) {
        return -PREMIUM_RATE_CLAMP_BOUNDARY_X96;
    } else {
        return rateDeltaX96;
    }
}

function newGlobalPosition() {
    return {
        longSize: 0n,
        shortSize: 0n,
        longFundingRateGrowthX96: 0n,
        shortFundingRateGrowthX96: 0n,
    };
}
