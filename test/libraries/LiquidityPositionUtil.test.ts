import {ethers} from "hardhat";
import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {
    DECIMALS_18,
    DECIMALS_6,
    mulDiv,
    Q64,
    Q96,
    Rounding,
    SIDE_LONG,
    SIDE_SHORT,
    toPriceX96,
} from "../shared/Constants";
import {expect} from "chai";
import {IPoolLiquidityPosition} from "../../typechain-types/contracts/test/LiquidityPositionUtilTest";
import {BigNumberish} from "ethers";
import LiquidityPositionStruct = IPoolLiquidityPosition.LiquidityPositionStruct;
import GlobalUnrealizedLossMetricsStruct = IPoolLiquidityPosition.GlobalUnrealizedLossMetricsStruct;

describe("LiquidityPositionUtil", () => {
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

        const PositionUtil = await ethers.getContractFactory("PositionUtil");
        const _positionUtil = await PositionUtil.deploy();
        await _positionUtil.deployed();
        const PositionUtilTest = await ethers.getContractFactory("PositionUtilTest", {
            libraries: {
                PositionUtil: _positionUtil.address,
            },
        });
        const positionUtil = await PositionUtilTest.deploy();
        await positionUtil.deployed();

        return {
            _liquidityPositionUtil,
            liquidityPositionUtil,
            positionUtil,
        };
    }

    describe("#calculateUnrealizedLoss", () => {
        describe("side is long", () => {
            it("entry price is greater than current price", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.789", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_LONG,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    0n
                );
                expect(unrealizedLoss).to.eq(mulDiv(netSize, entryPriceX96 - indexPriceX96, Q96, Rounding.Up));
            });

            it("entry price is less than current price", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.789", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_LONG,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    0n
                );
                expect(unrealizedLoss).to.eq(0);
            });

            it("entry price equal to current price", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_LONG,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    0n
                );
                expect(unrealizedLoss).to.eq(0n);
            });

            it("risk buffer fund is equal to type(int256).min", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                expect(
                    await liquidityPositionUtil.calculateUnrealizedLoss(
                        SIDE_LONG,
                        0n,
                        0n,
                        0n,
                        -57896044618658097711785492504343953926634992332820282019728792003956564819968n
                    )
                ).to.eq(57896044618658097711785492504343953926634992332820282019728792003956564819968n);
            });
        });

        describe("side is short", () => {
            it("entry price is less than current price", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.789", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_SHORT,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    0n
                );
                expect(unrealizedLoss).to.eq(mulDiv(netSize, indexPriceX96 - entryPriceX96, Q96, Rounding.Up));
            });

            it("entry price is greater than current price", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.789", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_SHORT,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    0n
                );
                expect(unrealizedLoss).to.eq(0);
            });

            it("entry price equal to current price", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_SHORT,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    0n
                );
                expect(unrealizedLoss).to.eq(0n);
            });
        });

        describe("riskBufferFund is not negative", () => {
            it("should subtract riskBufferFund from unrealizedLoss if unrealizedLoss is greater than riskBufferFund", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.789", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_LONG,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    10n
                );
                expect(unrealizedLoss).to.eq(mulDiv(netSize, entryPriceX96 - indexPriceX96, Q96, Rounding.Up) - 10n);
            });

            it("should be zero if unrealizedLoss is not greater than riskBufferFund", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const entryPriceX96 = toPriceX96("1808.789", DECIMALS_18, DECIMALS_6);
                const indexPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const netSize = 3n * 10n ** 18n;

                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    SIDE_LONG,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    mulDiv(netSize, entryPriceX96 - indexPriceX96, Q96, Rounding.Up) + 1n
                );
                expect(unrealizedLoss).to.eq(0n);
            });
        });

        it("should add riskBufferFund to unrealizedLoss if riskBufferFund is negative", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            const entryPriceX96 = toPriceX96("1808.789", DECIMALS_18, DECIMALS_6);
            const indexPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const netSize = 3n * 10n ** 18n;

            const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                SIDE_LONG,
                netSize,
                entryPriceX96,
                indexPriceX96,
                -1n
            );
            expect(unrealizedLoss).to.eq(mulDiv(netSize, entryPriceX96 - indexPriceX96, Q96, Rounding.Up) + 1n);
        });
    });

    describe("#updateUnrealizedLossMetrics", () => {
        describe("current unrealized loss is positive", () => {
            describe("liquidity delta entry time is greater than last zero time", () => {
                describe("liquidity delta is positive", () => {
                    it("should update metrics", async () => {
                        const {liquidityPositionUtil} = await loadFixture(deployFixture);
                        const timestamp = Math.ceil(Date.now() / 1000);
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            9999n,
                            timestamp,
                            1000n
                        );
                        const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                            await liquidityPositionUtil.metrics();
                        expect(lastZeroLossTime).to.eq(0);
                        expect(liquidity).to.eq(9999n);
                        expect(liquidityTimesUnrealizedLoss).to.eq(1000n * 9999n);
                    });

                    it("should accumulate unrealized loss", async () => {
                        const {liquidityPositionUtil} = await loadFixture(deployFixture);
                        const timestamp = Math.ceil(Date.now() / 1000);
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            9999n,
                            timestamp,
                            1000n
                        );
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            9999n,
                            timestamp,
                            1000n
                        );
                        const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                            await liquidityPositionUtil.metrics();
                        expect(lastZeroLossTime).to.eq(0);
                        expect(liquidity).to.eq(9999n * 2n);
                        expect(liquidityTimesUnrealizedLoss).to.eq(1000n * 9999n * 2n);
                    });

                    it("liquidity should overflow", async () => {
                        const {liquidityPositionUtil} = await loadFixture(deployFixture);
                        const timestamp = Math.ceil(Date.now() / 1000);
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            (1n << 128n) - 1n,
                            timestamp,
                            1000n
                        );
                        await expect(
                            liquidityPositionUtil.updateUnrealizedLossMetrics(1000n, timestamp, 1n, timestamp, 1000n)
                        ).to.revertedWithPanic("0x11");
                    });

                    it("liquidity times unrealized loss should overflow", async () => {
                        const {liquidityPositionUtil} = await loadFixture(deployFixture);
                        const timestamp = Math.ceil(Date.now() / 1000);
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            (1n << 256n) - 1n,
                            timestamp,
                            1n,
                            timestamp,
                            (1n << 256n) - 1n
                        );
                        await expect(
                            liquidityPositionUtil.updateUnrealizedLossMetrics(1n, timestamp, 1n, timestamp, 1n)
                        ).to.revertedWithPanic("0x11");
                    });
                });

                describe("liquidity delta is negative", () => {
                    it("should update metrics", async () => {
                        const {liquidityPositionUtil} = await loadFixture(deployFixture);
                        const timestamp = Math.ceil(Date.now() / 1000);
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            9999n,
                            timestamp,
                            9999n
                        );

                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            -9999n,
                            timestamp,
                            9999n
                        );
                        const {liquidity, liquidityTimesUnrealizedLoss, lastZeroLossTime} =
                            await liquidityPositionUtil.metrics();
                        expect(liquidity).to.eq(0n);
                        expect(liquidityTimesUnrealizedLoss).to.eq(0n);
                        expect(lastZeroLossTime).to.eq(0);
                    });

                    it("should accumulate unrealized loss", async () => {
                        const {liquidityPositionUtil} = await loadFixture(deployFixture);
                        const timestamp = Math.ceil(Date.now() / 1000);
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            9999n,
                            timestamp,
                            1000n
                        );
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            9999n,
                            timestamp,
                            1000n
                        );

                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            -9999n,
                            timestamp,
                            1000n
                        );
                        await liquidityPositionUtil.updateUnrealizedLossMetrics(
                            1000n,
                            timestamp,
                            -9999n,
                            timestamp,
                            1000n
                        );
                        const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                            await liquidityPositionUtil.metrics();
                        expect(lastZeroLossTime).to.eq(0n);
                        expect(liquidity).to.eq(0n);
                        expect(liquidityTimesUnrealizedLoss).to.eq(0n);
                    });
                });
            });

            it("liquidity delta entry time is less than last zero time", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Date.now() / 1000);
                await liquidityPositionUtil.updateUnrealizedLossMetrics(0n, timestamp, 9999n, timestamp, 0n);

                await liquidityPositionUtil.updateUnrealizedLossMetrics(1000n, timestamp, 9999n, timestamp - 1, 0n);

                const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                    await liquidityPositionUtil.metrics();
                expect(lastZeroLossTime).to.eq(timestamp);
                expect(liquidity).to.eq(0n);
                expect(liquidityTimesUnrealizedLoss).to.eq(0n);
            });

            it("liquidity delta entry time equal to last zero time", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Date.now() / 1000);
                await liquidityPositionUtil.updateUnrealizedLossMetrics(0n, timestamp, 9999n, timestamp, 0n);

                await liquidityPositionUtil.updateUnrealizedLossMetrics(1000n, timestamp, 9999n, timestamp, 0n);

                const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                    await liquidityPositionUtil.metrics();
                expect(lastZeroLossTime).to.eq(timestamp);
                expect(liquidity).to.eq(0n);
                expect(liquidityTimesUnrealizedLoss).to.eq(0n);
            });
        });

        describe("current unrealized loss is zero", () => {
            it("should update metrics", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Date.now() / 1000);
                await liquidityPositionUtil.updateUnrealizedLossMetrics(1000n, timestamp, 9999n, timestamp, 1000n);
                await liquidityPositionUtil.updateUnrealizedLossMetrics(0n, timestamp, 9999n, timestamp, 1000n);
                const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                    await liquidityPositionUtil.metrics();
                expect(lastZeroLossTime).to.eq(timestamp);
                expect(liquidity).to.eq(0n);
                expect(liquidityTimesUnrealizedLoss).to.eq(0n);
            });
        });
    });

    describe("#calculateRealizedProfit", () => {
        it("position realized profit should be zero", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            const position = newLiquidityPosition();
            position.entryRealizedProfitGrowthX64 = Q64;
            position.liquidity = 1n;
            const globalPosition = newGlobalLiquidityPosition();
            globalPosition.realizedProfitGrowthX64 = Q64;
            expect(await liquidityPositionUtil.calculateRealizedProfit(position, globalPosition)).to.eq(0n);
        });

        it("position realized profit should be positive", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            const position = newLiquidityPosition();
            position.entryRealizedProfitGrowthX64 = Q64;
            position.liquidity = 1n;
            const globalPosition = newGlobalLiquidityPosition();
            globalPosition.realizedProfitGrowthX64 = Q64 * 2n;
            expect(await liquidityPositionUtil.calculateRealizedProfit(position, globalPosition)).to.eq(1n);
        });

        it("should round down", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            const position = newLiquidityPosition();
            position.entryRealizedProfitGrowthX64 = Q64;
            position.liquidity = 1n;
            const globalPosition = newGlobalLiquidityPosition();
            globalPosition.realizedProfitGrowthX64 = Q64 * 2n + 1n;
            expect(await liquidityPositionUtil.calculateRealizedProfit(position, globalPosition)).to.eq(1n);
        });
    });

    describe("#calculatePositionUnrealizedLoss", () => {
        describe("entry time is greater than last zero loss time", () => {
            it("should be zero if unrealized loss is not greater than adjusted entry unrealized loss", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Math.random() / 1000);
                const position = newLiquidityPosition();
                position.entryTime = timestamp;
                position.entryUnrealizedLoss = 1000n;
                position.liquidity = 333n;
                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = 1000n;
                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.lastZeroLossTime = timestamp - 1;
                metrics.liquidity = 777n;
                metrics.liquidityTimesUnrealizedLoss = 333n * 1000n + 444n * 2000n;
                expect(
                    await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                        position,
                        metrics,
                        globalPosition.liquidity,
                        1000n
                    )
                ).to.eq(0n);
            });

            it("should be positive if unrealized loss is greater than adjusted entry unrealized loss", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Math.random() / 1000);
                const position = newLiquidityPosition();
                position.entryTime = timestamp;
                position.entryUnrealizedLoss = 1000n;
                position.liquidity = 333n;
                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = 1000n;
                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.lastZeroLossTime = timestamp - 1;
                metrics.liquidity = 777n;
                metrics.liquidityTimesUnrealizedLoss = 333n * 1000n + 444n * 2000n;
                expect(
                    await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                        position,
                        metrics,
                        globalPosition.liquidity,
                        2000n
                    )
                ).to.eq(mulDiv(1000n, position.liquidity, globalPosition.liquidity, Rounding.Up));
            });
        });

        describe("entry time is not greater than last zero loss time", () => {
            it("unrealized loss is greater than WAM unrealized loss", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Math.random() / 1000);
                const position = newLiquidityPosition();
                position.entryTime = timestamp;
                position.entryUnrealizedLoss = 1000n;
                position.liquidity = 333n;
                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = 1000n;
                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.lastZeroLossTime = timestamp;
                metrics.liquidity = 777n;
                metrics.liquidityTimesUnrealizedLoss = 333n * 1000n + 444n * 2000n;
                expect(
                    await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                        position,
                        metrics,
                        globalPosition.liquidity,
                        10000n
                    )
                ).to.eq(
                    mulDiv(10000n - 1572n, position.liquidity, globalPosition.liquidity, Rounding.Up) +
                        mulDiv(1572n, position.liquidity, globalPosition.liquidity - metrics.liquidity, Rounding.Up)
                );
            });

            it("unrealized loss is not greater than WAM unrealized loss", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Math.random() / 1000);
                const position = newLiquidityPosition();
                position.entryTime = timestamp;
                position.entryUnrealizedLoss = 1000n;
                position.liquidity = 223n;
                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = 1000n;
                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.lastZeroLossTime = timestamp;
                metrics.liquidity = 777n;
                metrics.liquidityTimesUnrealizedLoss = 333n * 1000n + 444n * 2000n;
                expect(
                    await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                        position,
                        metrics,
                        globalPosition.liquidity,
                        1500n
                    )
                ).to.eq(mulDiv(1500n, position.liquidity, globalPosition.liquidity - metrics.liquidity, Rounding.Up));
            });
        });

        describe("unrealized loss should be fully allocated to positions", () => {
            it("all positions have entry times greater than lastZeroLossTime", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Math.random() / 1000);
                const position1 = newLiquidityPosition();
                position1.entryTime = timestamp;
                position1.liquidity = 9999n;
                position1.entryUnrealizedLoss = 1000n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position1.entryUnrealizedLoss,
                    position1.entryTime,
                    position1.liquidity,
                    position1.entryTime,
                    position1.entryUnrealizedLoss
                );
                const position2 = newLiquidityPosition();
                position2.entryTime = timestamp + 1;
                position2.liquidity = 8888n;
                position2.entryUnrealizedLoss = 2000n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position2.entryUnrealizedLoss,
                    position2.entryTime,
                    position2.liquidity,
                    position2.entryTime,
                    position2.entryUnrealizedLoss
                );
                const position3 = newLiquidityPosition();
                position3.entryTime = timestamp + 2;
                position3.liquidity = 7777n;
                position3.entryUnrealizedLoss = 1500n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position3.entryUnrealizedLoss,
                    position3.entryTime,
                    position3.liquidity,
                    position3.entryTime,
                    position3.entryUnrealizedLoss
                );

                const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                    await liquidityPositionUtil.metrics();

                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.lastZeroLossTime = lastZeroLossTime;
                metrics.liquidity = liquidity;
                metrics.liquidityTimesUnrealizedLoss = liquidityTimesUnrealizedLoss;

                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = position1.liquidity + position2.liquidity + position3.liquidity;

                const unrealizedLoss = 10000n;

                const position1UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position1,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position1.liquidity;

                const position2UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position2,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position2.liquidity;

                const position3UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position3,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position3.liquidity;

                expect(position1UnrealizedLoss.add(position2UnrealizedLoss).add(position3UnrealizedLoss)).to.gte(
                    unrealizedLoss
                );
                expect(globalPosition.liquidity).to.eq(0n);
            });

            it("all positions have entry times less than lastZeroLossTime", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Math.random() / 1000);
                const position1 = newLiquidityPosition();
                position1.entryTime = timestamp;
                position1.liquidity = 9999n;
                position1.entryUnrealizedLoss = 1000n;
                const position2 = newLiquidityPosition();
                position2.entryTime = timestamp;
                position2.liquidity = 8888n;
                position2.entryUnrealizedLoss = 2000n;
                const position3 = newLiquidityPosition();
                position3.entryTime = timestamp;
                position3.liquidity = 7777n;
                position3.entryUnrealizedLoss = 1500n;

                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.lastZeroLossTime = timestamp + 1;
                metrics.liquidity = 0n;

                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity = position1.liquidity + position2.liquidity + position3.liquidity;

                const unrealizedLoss = 10000n;

                const position1UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position1,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position1.liquidity;

                const position2UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position2,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position2.liquidity;

                const position3UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position3,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position3.liquidity;

                expect(position1UnrealizedLoss.add(position2UnrealizedLoss).add(position3UnrealizedLoss)).to.gte(
                    unrealizedLoss
                );
                expect(globalPosition.liquidity).to.eq(0n);
            });

            it("mixed positions", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);
                const timestamp = Math.ceil(Math.random() / 1000);

                const position1 = newLiquidityPosition();
                position1.entryTime = timestamp - 1;
                position1.liquidity = 9999n;
                position1.entryUnrealizedLoss = 0n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position1.entryUnrealizedLoss,
                    position1.entryTime,
                    position1.liquidity,
                    position1.entryTime,
                    position1.entryUnrealizedLoss
                );
                const position2 = newLiquidityPosition();
                position2.entryTime = timestamp + 1;
                position2.liquidity = 8888n;
                position2.entryUnrealizedLoss = 2000n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position2.entryUnrealizedLoss,
                    position2.entryTime,
                    position2.liquidity,
                    position2.entryTime,
                    position2.entryUnrealizedLoss
                );
                const position3 = newLiquidityPosition();
                position3.entryTime = timestamp + 2;
                position3.liquidity = 7777n;
                position3.entryUnrealizedLoss = 1500n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position3.entryUnrealizedLoss,
                    position3.entryTime,
                    position3.liquidity,
                    position3.entryTime,
                    position3.entryUnrealizedLoss
                );
                const position4 = newLiquidityPosition();
                position4.entryTime = timestamp + 3;
                position4.liquidity = 6666n;
                position4.entryUnrealizedLoss = 0n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position4.entryUnrealizedLoss,
                    position4.entryTime,
                    position4.liquidity,
                    position4.entryTime,
                    position4.entryUnrealizedLoss
                );
                const position5 = newLiquidityPosition();
                position5.entryTime = timestamp + 4;
                position5.liquidity = 5555n;
                position5.entryUnrealizedLoss = 10000n;
                await liquidityPositionUtil.updateUnrealizedLossMetrics(
                    position5.entryUnrealizedLoss,
                    position5.entryTime,
                    position5.liquidity,
                    position5.entryTime,
                    position5.entryUnrealizedLoss
                );

                const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                    await liquidityPositionUtil.metrics();

                const metrics = newGlobalUnrealizedLossMetrics();
                metrics.lastZeroLossTime = lastZeroLossTime;
                metrics.liquidity = liquidity;
                metrics.liquidityTimesUnrealizedLoss = liquidityTimesUnrealizedLoss;

                const globalPosition = newGlobalLiquidityPosition();
                globalPosition.liquidity =
                    position1.liquidity +
                    position2.liquidity +
                    position3.liquidity +
                    position4.liquidity +
                    position5.liquidity;

                const unrealizedLoss = 10000n;

                const position1UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position1,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position1.liquidity;

                const position2UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position2,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position2.liquidity;

                const position3UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position3,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position3.liquidity;

                const position4UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position4,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position4.liquidity;

                const position5UnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                    position5,
                    metrics,
                    globalPosition.liquidity,
                    unrealizedLoss
                );
                globalPosition.liquidity = globalPosition.liquidity - position5.liquidity;

                expect(
                    position1UnrealizedLoss
                        .add(position2UnrealizedLoss)
                        .add(position3UnrealizedLoss)
                        .add(position4UnrealizedLoss)
                        .add(position5UnrealizedLoss)
                ).to.gte(unrealizedLoss);
                expect(globalPosition.liquidity).to.eq(0n);
            });
        });
    });

    describe("#calculateWAMUnrealizedLoss", () => {
        it("shouldn't fail if liquidity is zero", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            expect(await liquidityPositionUtil.calculateWAMUnrealizedLoss(newGlobalUnrealizedLossMetrics())).to.eq(0n);
        });

        it("should round up", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            expect(
                await liquidityPositionUtil.calculateWAMUnrealizedLoss({
                    lastZeroLossTime: 0,
                    liquidity: 9999n,
                    liquidityTimesUnrealizedLoss: 10000n,
                })
            ).to.eq(2n);
        });
    });

    describe("#calculateRealizedPnLAndNextEntryPriceX96", () => {
        describe("calculateRealizedPnL", () => {
            it("should return zero if the sum of netSize and liquidationBufferNetSize is zero", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);

                const globalPosition = newGlobalLiquidityPosition();
                {
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1808.123", DECIMALS_18, DECIMALS_6),
                        1000n
                    );
                    expect(realizedPnL).to.eq(0n);
                }
                {
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1808.123", DECIMALS_18, DECIMALS_6),
                        1000n
                    );
                    expect(realizedPnL).to.eq(0n);
                }
            });

            it("should return zero if the side of the trader's position adjustment is different from the side of global liquidity position", async () => {
                const {liquidityPositionUtil} = await loadFixture(deployFixture);

                {
                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                    globalPosition.side = SIDE_LONG;
                    globalPosition.netSize = 10000n;
                    globalPosition.liquidationBufferNetSize = 10000n;
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_SHORT,
                        toPriceX96("1808.123", DECIMALS_18, DECIMALS_6),
                        1000n
                    );
                    expect(realizedPnL).to.eq(0n);
                }

                {
                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                    globalPosition.side = SIDE_SHORT;
                    globalPosition.netSize = 10000n;
                    globalPosition.liquidationBufferNetSize = 10000n;
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        SIDE_LONG,
                        toPriceX96("1808.123", DECIMALS_18, DECIMALS_6),
                        1000n
                    );
                    expect(realizedPnL).to.eq(0n);
                }
            });

            it("should pass if sizeDelta is greater than the sum of netSize and liquidationBufferNetSize", async () => {
                const {liquidityPositionUtil, positionUtil} = await loadFixture(deployFixture);

                {
                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.side = SIDE_SHORT;
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;

                    const side = SIDE_SHORT;
                    const tradePriceX96 = toPriceX96("1818", DECIMALS_18, DECIMALS_6);
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        side,
                        tradePriceX96,
                        Q96 * 2n + 1n
                    );
                    expect(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96 * 2n,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    ).to.not.eq(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96 * 2n + 1n,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    );
                    expect(realizedPnL).to.eq(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96 * 2n,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    );
                }

                {
                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.side = SIDE_LONG;
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;

                    const side = SIDE_LONG;
                    const tradePriceX96 = toPriceX96("1798", DECIMALS_18, DECIMALS_6);
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        side,
                        tradePriceX96,
                        Q96 * 2n + 1n
                    );
                    expect(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96 * 2n,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    ).to.not.eq(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96 * 2n + 1n,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    );
                    expect(realizedPnL).to.eq(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96 * 2n,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    );
                }
            });

            it("should pass if sizeDelta is not greater than the sum of netSize and liquidationBufferNetSize", async () => {
                const {liquidityPositionUtil, positionUtil} = await loadFixture(deployFixture);

                {
                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.side = SIDE_SHORT;
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;

                    const side = SIDE_SHORT;
                    const tradePriceX96 = toPriceX96("1818", DECIMALS_18, DECIMALS_6);
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        side,
                        tradePriceX96,
                        Q96
                    );
                    expect(realizedPnL).to.eq(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    );
                }

                {
                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.side = SIDE_LONG;
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;

                    const side = SIDE_LONG;
                    const tradePriceX96 = toPriceX96("1798", DECIMALS_18, DECIMALS_6);
                    const {realizedPnL} = await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                        globalPosition,
                        side,
                        tradePriceX96,
                        Q96
                    );
                    expect(realizedPnL).to.eq(
                        await positionUtil.calculateUnrealizedPnL(
                            side,
                            Q96,
                            globalPosition.entryPriceX96,
                            tradePriceX96
                        )
                    );
                }
            });
        });

        describe("calculateNextEntryPriceX96", () => {
            describe("size delta is zero", () => {
                it("should return the entryPriceX96 if the sum of netSize and liquidationBufferNetSize is zero", async () => {
                    const {liquidityPositionUtil} = await loadFixture(deployFixture);

                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    {
                        globalPosition.side = SIDE_SHORT;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_SHORT,
                                toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                                0n
                            );
                        expect(entryPriceAfterX96).to.eq(globalPosition.entryPriceX96);
                    }

                    {
                        globalPosition.side = SIDE_LONG;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_LONG,
                                toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                                0n
                            );
                        expect(entryPriceAfterX96).to.eq(globalPosition.entryPriceX96);
                    }
                });

                it("should return the entryPriceX96 if the side of the trader's position adjustment is different from the side of global liquidity position", async () => {
                    const {liquidityPositionUtil} = await loadFixture(deployFixture);

                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;
                    {
                        globalPosition.side = SIDE_LONG;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_SHORT,
                                toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                                0n
                            );
                        expect(entryPriceAfterX96).to.eq(globalPosition.entryPriceX96);
                    }

                    {
                        globalPosition.side = SIDE_SHORT;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_LONG,
                                toPriceX96("1810", DECIMALS_18, DECIMALS_6),
                                0n
                            );
                        expect(entryPriceAfterX96).to.eq(globalPosition.entryPriceX96);
                    }
                });
            });

            describe("size delta is positive", () => {
                it("should pass if the sum of netSize and liquidationBufferNetSize is zero", async () => {
                    const {liquidityPositionUtil, positionUtil} = await loadFixture(deployFixture);

                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    const tradePriceX96 = toPriceX96("1810", DECIMALS_18, DECIMALS_6);
                    const sizeDelta = Q96;
                    {
                        globalPosition.side = SIDE_SHORT;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_SHORT,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(
                                SIDE_LONG,
                                0n,
                                globalPosition.entryPriceX96,
                                sizeDelta,
                                tradePriceX96
                            )
                        );
                    }

                    {
                        globalPosition.side = SIDE_LONG;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_LONG,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(
                                SIDE_SHORT,
                                0n,
                                globalPosition.entryPriceX96,
                                sizeDelta,
                                tradePriceX96
                            )
                        );
                    }
                });

                it("should pass if the side of the trader's position adjustment is different from the side of global liquidity position", async () => {
                    const {liquidityPositionUtil, positionUtil} = await loadFixture(deployFixture);

                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;
                    const tradePriceX96 = toPriceX96("1810", DECIMALS_18, DECIMALS_6);
                    const sizeDelta = Q96;
                    {
                        globalPosition.side = SIDE_LONG;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_SHORT,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(
                                SIDE_LONG,
                                Q96 * 2n,
                                globalPosition.entryPriceX96,
                                sizeDelta,
                                tradePriceX96
                            )
                        );
                    }

                    {
                        globalPosition.side = SIDE_SHORT;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_LONG,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(
                                SIDE_SHORT,
                                Q96 * 2n,
                                globalPosition.entryPriceX96,
                                sizeDelta,
                                tradePriceX96
                            )
                        );
                    }
                });

                it("should pass if sizeDelta is greater than the sum of netSize and liquidationBufferNetSize", async () => {
                    const {liquidityPositionUtil, positionUtil} = await loadFixture(deployFixture);

                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;
                    const tradePriceX96 = toPriceX96("1810", DECIMALS_18, DECIMALS_6);
                    const sizeDelta = Q96 * 3n;
                    {
                        globalPosition.side = SIDE_SHORT;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_SHORT,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(SIDE_LONG, 0n, 0n, Q96, tradePriceX96)
                        );
                    }

                    {
                        globalPosition.side = SIDE_LONG;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_LONG,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(SIDE_SHORT, 0n, 0n, Q96, tradePriceX96)
                        );
                    }
                });

                it("should pass if sizeDelta is less than the sum of netSize and liquidationBufferNetSize", async () => {
                    const {liquidityPositionUtil, positionUtil} = await loadFixture(deployFixture);

                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;
                    const tradePriceX96 = toPriceX96("1810", DECIMALS_18, DECIMALS_6);
                    const sizeDelta = Q96;
                    {
                        globalPosition.side = SIDE_SHORT;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_SHORT,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(
                                SIDE_LONG,
                                Q96,
                                globalPosition.entryPriceX96,
                                0n,
                                tradePriceX96
                            )
                        );
                    }

                    {
                        globalPosition.side = SIDE_LONG;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_LONG,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(
                                SIDE_SHORT,
                                Q96,
                                globalPosition.entryPriceX96,
                                0n,
                                tradePriceX96
                            )
                        );
                    }
                });

                it("should pass if sizeDelta is equal to the sum of netSize and liquidationBufferNetSize", async () => {
                    const {liquidityPositionUtil, positionUtil} = await loadFixture(deployFixture);

                    const globalPosition = newGlobalLiquidityPosition();
                    globalPosition.entryPriceX96 = toPriceX96("1808", DECIMALS_18, DECIMALS_6);
                    globalPosition.netSize = Q96;
                    globalPosition.liquidationBufferNetSize = Q96;
                    const tradePriceX96 = toPriceX96("1810", DECIMALS_18, DECIMALS_6);
                    const sizeDelta = Q96 * 2n;
                    {
                        globalPosition.side = SIDE_SHORT;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_SHORT,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(SIDE_LONG, 0n, 0n, 0n, tradePriceX96)
                        );
                    }

                    {
                        globalPosition.side = SIDE_LONG;
                        const {entryPriceAfterX96} =
                            await liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
                                globalPosition,
                                SIDE_LONG,
                                tradePriceX96,
                                sizeDelta
                            );
                        expect(entryPriceAfterX96).to.eq(
                            await positionUtil.calculateNextEntryPriceX96(SIDE_SHORT, 0n, 0n, 0n, tradePriceX96)
                        );
                    }
                });
            });
        });
    });

    describe("#govUseRiskBufferFund", () => {
        it("should pass", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            const indexPriceX96 = toPriceX96("1808.123", DECIMALS_18, DECIMALS_6);
            const riskBufferFundDelta = 5n;
            const side = SIDE_LONG;
            const liquidity = 1_000_000n;
            const netSize = 1_000_000n;
            const entryPriceX96 = toPriceX96("1908.234", DECIMALS_18, DECIMALS_6);
            const riskBufferFund = 10n;
            await liquidityPositionUtil.setGlobalLiquidityPosition(liquidity, netSize, entryPriceX96, side, 0n);
            await liquidityPositionUtil.setGlobalRiskBufferFund(riskBufferFund, 0n);

            const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                side,
                netSize,
                entryPriceX96,
                indexPriceX96,
                0n
            );
            const riskBufferFundAfter = riskBufferFund - riskBufferFundDelta;
            await liquidityPositionUtil.govUseRiskBufferFund(indexPriceX96, riskBufferFundDelta);
            {
                const {riskBufferFund} = await liquidityPositionUtil.globalRiskBufferFund();
                expect(riskBufferFund).to.eq(riskBufferFundAfter);
            }
        });

        it("should revert if risk buffer fund is not enough", async () => {
            const {liquidityPositionUtil, _liquidityPositionUtil} = await loadFixture(deployFixture);
            const indexPriceX96 = toPriceX96("1808.123", DECIMALS_18, DECIMALS_6);
            const riskBufferFundDelta = 5n;
            const side = SIDE_LONG;
            const liquidity = 1_000_000n;
            const netSize = 1_000_000n;
            const entryPriceX96 = toPriceX96("1908.234", DECIMALS_18, DECIMALS_6);

            async function test(riskBufferFund: BigNumberish) {
                await liquidityPositionUtil.setGlobalLiquidityPosition(liquidity, netSize, entryPriceX96, side, 0n);
                await liquidityPositionUtil.setGlobalRiskBufferFund(riskBufferFund, 0n);
                const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                    side,
                    netSize,
                    entryPriceX96,
                    indexPriceX96,
                    0n
                );
                await expect(liquidityPositionUtil.govUseRiskBufferFund(indexPriceX96, riskBufferFundDelta))
                    .to.revertedWithCustomError(_liquidityPositionUtil, "InsufficientRiskBufferFund")
                    .withArgs(unrealizedLoss, riskBufferFundDelta);
            }

            await test(4n);
            await test(5n);
        });
    });

    describe("#increaseRiskBufferFundPosition", () => {
        it("should pass", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);

            const [owner, other] = await ethers.getSigners();
            let nextBlockTimestamp = (await time.latest()) + 60;
            await time.setNextBlockTimestamp(nextBlockTimestamp);
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, Q96);
            {
                expect(await liquidityPositionUtil.positionLiquidityAfter()).to.eq(Q96);
                expect(await liquidityPositionUtil.riskBufferFundAfter()).to.eq(Q96);
                const globalRiskBufferFund = await liquidityPositionUtil.globalRiskBufferFund();
                expect(globalRiskBufferFund.liquidity).to.eq(Q96);
                expect(globalRiskBufferFund.riskBufferFund).to.eq(Q96);

                const {liquidity, unlockTime} = await liquidityPositionUtil.riskBufferFundPositions(owner.address);
                expect(liquidity).to.eq(Q96);
                expect(unlockTime).to.eq(nextBlockTimestamp + 90 * 24 * 60 * 60);
            }

            // should reset unlockTime
            nextBlockTimestamp = (await time.latest()) + 120;
            await time.setNextBlockTimestamp(nextBlockTimestamp);
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, 1n);
            {
                expect(await liquidityPositionUtil.positionLiquidityAfter()).to.eq(Q96 + 1n);
                expect(await liquidityPositionUtil.riskBufferFundAfter()).to.eq(Q96 + 1n);
                const globalRiskBufferFund = await liquidityPositionUtil.globalRiskBufferFund();
                expect(globalRiskBufferFund.liquidity).to.eq(Q96 + 1n);
                expect(globalRiskBufferFund.riskBufferFund).to.eq(Q96 + 1n);

                const {liquidity, unlockTime} = await liquidityPositionUtil.riskBufferFundPositions(owner.address);
                expect(liquidity).to.eq(Q96 + 1n);
                expect(unlockTime).to.eq(nextBlockTimestamp + 90 * 24 * 60 * 60);
            }

            nextBlockTimestamp = (await time.latest()) + 180;
            await time.setNextBlockTimestamp(nextBlockTimestamp);
            await liquidityPositionUtil.increaseRiskBufferFundPosition(other.address, 1n);
            {
                expect(await liquidityPositionUtil.positionLiquidityAfter()).to.eq(1n);
                expect(await liquidityPositionUtil.riskBufferFundAfter()).to.eq(Q96 + 2n);
                const globalRiskBufferFund = await liquidityPositionUtil.globalRiskBufferFund();
                expect(globalRiskBufferFund.liquidity).to.eq(Q96 + 2n);
                expect(globalRiskBufferFund.riskBufferFund).to.eq(Q96 + 2n);

                const {liquidity} = await liquidityPositionUtil.riskBufferFundPositions(owner.address);
                expect(liquidity).to.eq(Q96 + 1n);
                const {liquidity: otherLiquidity, unlockTime} = await liquidityPositionUtil.riskBufferFundPositions(
                    other.address
                );
                expect(otherLiquidity).to.eq(1n);
                expect(unlockTime).to.eq(nextBlockTimestamp + 90 * 24 * 60 * 60);
            }
        });
    });

    describe("#decreaseRiskBufferFundPosition", () => {
        it("should revert if unlock time is not reached", async () => {
            const {liquidityPositionUtil, _liquidityPositionUtil} = await loadFixture(deployFixture);
            const [owner] = await ethers.getSigners();
            let nextBlockTimestamp = (await time.latest()) + 60;
            await time.setNextBlockTimestamp(nextBlockTimestamp);
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, Q96);
            await expect(liquidityPositionUtil.decreaseRiskBufferFundPosition(0n, owner.address, 1n))
                .to.revertedWithCustomError(_liquidityPositionUtil, "UnlockTimeNotReached")
                .withArgs(nextBlockTimestamp + 90 * 24 * 60 * 60);
        });
        it("should revert if unlock time is equal to the current block timestamp", async () => {
            const {liquidityPositionUtil, _liquidityPositionUtil} = await loadFixture(deployFixture);
            const [owner] = await ethers.getSigners();
            let nextBlockTimestamp = (await time.latest()) + 60;
            await time.setNextBlockTimestamp(nextBlockTimestamp);
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, Q96);

            await time.setNextBlockTimestamp(nextBlockTimestamp + 90 * 24 * 60 * 60);
            await expect(liquidityPositionUtil.decreaseRiskBufferFundPosition(0n, owner.address, 1n))
                .to.revertedWithCustomError(_liquidityPositionUtil, "UnlockTimeNotReached")
                .withArgs(nextBlockTimestamp + 90 * 24 * 60 * 60);
        });
        it("should revert if position liquidity is less than liquidityDelta", async () => {
            const {liquidityPositionUtil, _liquidityPositionUtil} = await loadFixture(deployFixture);

            const [owner, other] = await ethers.getSigners();
            let nextBlockTimestamp = (await time.latest()) + 60;
            await time.setNextBlockTimestamp(nextBlockTimestamp);
            await liquidityPositionUtil.increaseRiskBufferFundPosition(other.address, 1000n);
            await time.setNextBlockTimestamp(nextBlockTimestamp + 90 * 24 * 60 * 60 + 1);
            await expect(liquidityPositionUtil.decreaseRiskBufferFundPosition(0n, owner.address, 1n))
                .to.revertedWithCustomError(_liquidityPositionUtil, "InsufficientLiquidity")
                .withArgs(0n, 1n);
        });

        it("should revert if the risk buffer fund is loss", async () => {
            const {liquidityPositionUtil, _liquidityPositionUtil} = await loadFixture(deployFixture);

            await liquidityPositionUtil.setGlobalLiquidityPosition(
                1_000_000n,
                10n,
                toPriceX96("1808.123", DECIMALS_18, DECIMALS_6),
                SIDE_SHORT,
                0n
            );
            await liquidityPositionUtil.setGlobalRiskBufferFund(0n, 1000n);
            const [owner] = await ethers.getSigners();
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, 1000n);
            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await expect(
                liquidityPositionUtil.decreaseRiskBufferFundPosition(
                    toPriceX96("1909.234", DECIMALS_18, DECIMALS_6),
                    owner.address,
                    1n
                )
            ).to.revertedWithCustomError(_liquidityPositionUtil, "RiskBufferFundLoss");
        });

        it("should decrease liquidity", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);
            const [owner] = await ethers.getSigners();
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, 1000n);
            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await liquidityPositionUtil.decreaseRiskBufferFundPosition(0n, owner.address, 500n);
            const {liquidity, unlockTime} = await liquidityPositionUtil.riskBufferFundPositions(owner.address);
            expect(liquidity).to.eq(500n);
            expect(unlockTime).to.gt(0);
        });

        it("should delete position if liquidity is zero", async () => {
            const {liquidityPositionUtil, _liquidityPositionUtil} = await loadFixture(deployFixture);
            const [owner] = await ethers.getSigners();
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, 1000n);
            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await liquidityPositionUtil.decreaseRiskBufferFundPosition(0n, owner.address, 1000n);
            const {liquidity, unlockTime} = await liquidityPositionUtil.riskBufferFundPositions(owner.address);
            expect(liquidity).to.eq(0n);
            expect(unlockTime).to.eq(0);
        });

        it("should pass", async () => {
            const {liquidityPositionUtil} = await loadFixture(deployFixture);

            await liquidityPositionUtil.setGlobalRiskBufferFund(0n, 0n);
            const [owner, other] = await ethers.getSigners();
            await liquidityPositionUtil.increaseRiskBufferFundPosition(owner.address, 1000n);
            await liquidityPositionUtil.increaseRiskBufferFundPosition(other.address, 100n);
            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await liquidityPositionUtil.decreaseRiskBufferFundPosition(
                toPriceX96("1808.123", DECIMALS_18, DECIMALS_6),
                owner.address,
                1n
            );
            {
                expect(await liquidityPositionUtil.positionLiquidityAfter()).to.eq(999n);
                expect(await liquidityPositionUtil.riskBufferFundAfter()).to.eq(1099n);
                const globalRiskBufferFund = await liquidityPositionUtil.globalRiskBufferFund();
                expect(globalRiskBufferFund.liquidity).to.eq(1099n);
                expect(globalRiskBufferFund.riskBufferFund).to.eq(1099n);

                const {liquidity: ownerPositionLiquidity} = await liquidityPositionUtil.riskBufferFundPositions(
                    owner.address
                );
                expect(ownerPositionLiquidity).to.eq(999n);
                const {liquidity: otherPositionLiquidity} = await liquidityPositionUtil.riskBufferFundPositions(
                    other.address
                );
                expect(otherPositionLiquidity).to.eq(100n);
            }
        });
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
