import {ethers} from "hardhat";
import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {expectSnapshotGasCost} from "../shared/snapshotGasCost";
import {DECIMALS_18, DECIMALS_6, Q96, SIDE_LONG, SIDE_SHORT, toPriceX96} from "../shared/Constants";
import {IPoolLiquidityPosition} from "../../typechain-types/contracts/test/LiquidityPositionUtilTest";
import LiquidityPositionStruct = IPoolLiquidityPosition.LiquidityPositionStruct;
import GlobalUnrealizedLossMetricsStruct = IPoolLiquidityPosition.GlobalUnrealizedLossMetricsStruct;

describe("LiquidityPositionUtil gas tests", () => {
    async function deployFixture() {
        const LiquidityPositionUtil = await ethers.getContractFactory("LiquidityPositionUtil");
        const _liquidityPositionUtil = await LiquidityPositionUtil.deploy();
        await _liquidityPositionUtil.deployed();

        const LiquidityPositionUtilTest = await ethers.getContractFactory("LiquidityPositionUtilTest", {
            libraries: {
                LiquidityPositionUtil: _liquidityPositionUtil.address,
            },
        });
        const liquidityPositionUtil = await LiquidityPositionUtilTest.deploy();
        await liquidityPositionUtil.deployed();
        return {
            liquidityPositionUtil,
        };
    }

    describe("#updateUnrealizedLossMetrics", () => {
        describe("current unrealized loss is zero", () => {
            it("metrics before is zero", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                await expectSnapshotGasCost(
                    liquidityPositionUtil.updateUnrealizedLossMetrics(
                        0n,
                        Math.floor(new Date().getTime() / 1000),
                        10n ** 18n,
                        Math.floor(new Date().getTime() / 1000),
                        0n
                    )
                );
            });

            it("metrics before is not zero", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    123456n,
                    Math.floor(new Date().getTime() / 1000),
                    10n ** 18n,
                    Math.floor(new Date().getTime() / 1000),
                    123456n
                );

                await expectSnapshotGasCost(
                    liquidityPositionUtil.updateUnrealizedLossMetrics(
                        0n,
                        Math.floor(new Date().getTime() / 1000),
                        10n ** 18n,
                        Math.floor(new Date().getTime() / 1000),
                        0n
                    )
                );
            });
        });

        describe("current unrealized loss is not zero", () => {
            it("liquidity delta is zero", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                await expectSnapshotGasCost(
                    liquidityPositionUtil.updateUnrealizedLossMetrics(
                        123456n,
                        Math.floor(new Date().getTime() / 1000),
                        0n,
                        Math.floor(new Date().getTime() / 1000),
                        123456n
                    )
                );
            });

            it("liquidity delta is positive", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                await expectSnapshotGasCost(
                    liquidityPositionUtil.updateUnrealizedLossMetrics(
                        123456n,
                        Math.floor(new Date().getTime() / 1000),
                        10n ** 18n,
                        Math.floor(new Date().getTime() / 1000),
                        123456n
                    )
                );
            });

            it("liquidity delta is negative", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    123456n,
                    Math.floor(new Date().getTime() / 1000),
                    10n ** 18n,
                    Math.floor(new Date().getTime() / 1000),
                    123456n
                );

                await expectSnapshotGasCost(
                    liquidityPositionUtil.updateUnrealizedLossMetrics(
                        123456n,
                        Math.floor(new Date().getTime() / 1000),
                        -(10n ** 18n),
                        Math.floor(new Date().getTime() / 1000),
                        123456n
                    )
                );
            });
        });
    });

    describe("#calculatePositionUnrealizedLoss", () => {
        it("entry time is greater than last zero loss time", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            const lastTimestamp = Math.floor(new Date().getTime() / 1000);

            const globalPosition = newGlobalLiquidityPosition();
            globalPosition.liquidity = 1000n * 10n ** 6n;

            const position = newLiquidityPosition();
            position.liquidity = 333n * 10n ** 6n;
            position.entryTime = lastTimestamp;

            const metrics = newGlobalUnrealizedLossMetrics();
            metrics.lastZeroLossTime = lastTimestamp - 100;
            await expectSnapshotGasCost(
                liquidityPositionUtil.getGasCostCalculatePositionUnrealizedLoss(
                    position,
                    metrics,
                    globalPosition.liquidity,
                    100n * 10n ** 6n
                )
            );
        });

        describe("entry time is not greater than last zero loss time", () => {
            it("unrealized loss is greater than WAM unrealized loss", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const lastTimestamp = Math.floor(new Date().getTime() / 1000);

                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = 1000n * 10n ** 6n;

                const position = newLiquidityPosition();
                position.liquidity = 333n * 10n ** 6n;
                position.entryTime = lastTimestamp;

                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.liquidity = 444n * 10n ** 6n;
                metrics.liquidityTimesUnrealizedLoss = metrics.liquidity * (20n * 10n ** 6n);
                metrics.lastZeroLossTime = lastTimestamp + 1;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculatePositionUnrealizedLoss(
                        position,
                        metrics,
                        globalPosition.liquidity,
                        300n * 10n ** 6n
                    )
                );
            });

            it("unrealized loss is less than WAM unrealized loss", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const lastTimestamp = Math.floor(new Date().getTime() / 1000);

                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = 1000n * 10n ** 6n;

                const position = newLiquidityPosition();
                position.liquidity = 333n * 10n ** 6n;
                position.entryTime = lastTimestamp;

                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.liquidity = 444n * 10n ** 6n;
                metrics.liquidityTimesUnrealizedLoss = metrics.liquidity * (200n * 10n ** 6n);
                metrics.lastZeroLossTime = lastTimestamp + 1;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculatePositionUnrealizedLoss(
                        position,
                        metrics,
                        globalPosition.liquidity,
                        10n * 10n ** 6n
                    )
                );
            });
        });
    });

    describe("#calculateRealizedPnLAndNextEntryPriceX96", () => {
        it("the sum of netSize and liquidationBufferNetSize is zero", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);

            const globalPosition = newGlobalLiquidityPosition();
            globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
            {
                globalPosition.side = SIDE_SHORT;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
            }

            {
                globalPosition.side = SIDE_LONG;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
            }
        });

        it("the side of the trader's position adjustment is different from the side of global liquidity position", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);

            const globalPosition = newGlobalLiquidityPosition();
            globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
            globalPosition.netSize = Q96;
            globalPosition.liquidationBufferNetSize = Q96;

            {
                globalPosition.side = SIDE_SHORT;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
            }

            {
                globalPosition.side = SIDE_LONG;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        0n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                        1000n
                    )
                );
            }
        });

        it("the sum of netSize and liquidationBufferNetSize is positive and the side of the trader's position adjustment is same as the side of global liquidity position", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);

            const globalPosition = newGlobalLiquidityPosition();
            globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
            globalPosition.netSize = Q96;
            globalPosition.liquidationBufferNetSize = Q96;
            const tradePriceX96 = toPriceX96("1810", DECIMALS_18, DECIMALS_6);
            {
                globalPosition.side = SIDE_SHORT;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        tradePriceX96,
                        Q96
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        tradePriceX96,
                        Q96 * 2n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        tradePriceX96,
                        Q96 * 3n
                    )
                );
            }

            {
                globalPosition.side = SIDE_LONG;
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        tradePriceX96,
                        Q96
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        tradePriceX96,
                        Q96 * 2n
                    )
                );
                await expectSnapshotGasCost(
                    liquidityPositionUtil.getGasCostCalculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        tradePriceX96,
                        Q96 * 3n
                    )
                );
            }
        });
    });

    it("#increaseRiskBufferFundPosition", async () => {
        const {liquidityPositionUtil} = await loadFixture(deployFixture);

        const [owner, other] = await ethers.getSigners();
        await expectSnapshotGasCost(liquidityPositionUtil.getGasCostIncreaseRiskBufferFundPosition(owner.address, Q96));
        await expectSnapshotGasCost(liquidityPositionUtil.getGasCostIncreaseRiskBufferFundPosition(owner.address, 1n));
        await expectSnapshotGasCost(liquidityPositionUtil.getGasCostIncreaseRiskBufferFundPosition(other.address, 1n));
    });

    it("#decreaseRiskBufferFundPosition", async () => {
        const {liquidityPositionUtil} = await loadFixture(deployFixture);

        const [owner, other] = await ethers.getSigners();
        await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, 1000n);
        await liquidityPositionUtil.increaseRiskBufferFundPosition(other.address, 100n);
        await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
        await expectSnapshotGasCost(
            liquidityPositionUtil.getGasCostDecreaseRiskBufferFundPosition(
                toPriceX96("1808.123", DECIMALS_18, DECIMALS_6),
                owner.address,
                1n
            )
        );
    });
});

function newGlobalLiquidityPosition() {
    return {
        netSize: 0n,
        liquidationBufferNetSize: 0n,
        entryPriceX96: 0n,
        side: 0,
        liquidity: 0n,
        realizedProfitGrowthX64: 0n,
    };
}

function newLiquidityPosition(): LiquidityPositionStruct {
    return {
        margin: 0n,
        liquidity: 0n,
        entryUnrealizedLoss: 0n,
        entryRealizedProfitGrowthX64: 0n,
        entryTime: 0,
        account: ethers.constants.AddressZero,
    };
}

function newGlobalUnrealizedLossMetrics(): GlobalUnrealizedLossMetricsStruct {
    return {
        lastZeroLossTime: 0n,
        liquidity: 0n,
        liquidityTimesUnrealizedLoss: 0n,
    };
}
