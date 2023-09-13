import {ethers} from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {
    BASIS_POINTS_DIVISOR,
    DECIMALS_18,
    DECIMALS_6,
    isLongSide,
    isShortSide,
    mulDiv,
    Q96,
    Rounding,
    Side,
    SIDE_LONG,
    SIDE_SHORT,
    toPriceX96,
} from "../shared/Constants";
import Decimal from "decimal.js";
import {BigNumber, BigNumberish} from "ethers";

describe("PositionUtil", () => {
    async function deployFixture() {
        const PositionUtil = await ethers.getContractFactory("PositionUtil");
        const _positionUtil = await PositionUtil.deploy();
        await _positionUtil.deployed();

        const PositionUtilTest = await ethers.getContractFactory("PositionUtilTest", {
            libraries: {
                PositionUtil: _positionUtil.address,
            },
        });
        const positionUtil = await PositionUtilTest.deploy();
        await positionUtil.setGlobalPosition(1, 2, 3, 4);
        return {positionUtil};
    }

    describe("#calculateNextEntryPriceX96", () => {
        const entryPriceX96 = toPriceX96("1", DECIMALS_18, DECIMALS_6);
        const tradePriceX96 = toPriceX96("1.1", DECIMALS_18, DECIMALS_6);
        it("should return zero if size before is zero and size delta is zero", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            expect(await positionUtil.calculateNextEntryPriceX96(SIDE_LONG, 0, entryPriceX96, 0, tradePriceX96)).to.eq(
                0
            );
            expect(await positionUtil.calculateNextEntryPriceX96(SIDE_SHORT, 0, entryPriceX96, 0, tradePriceX96)).to.eq(
                0
            );
        });

        it("should return trade price x96 if size before is zero and size delta is not zero", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            expect(await positionUtil.calculateNextEntryPriceX96(SIDE_LONG, 0, entryPriceX96, 1, tradePriceX96)).to.eq(
                tradePriceX96
            );
            expect(await positionUtil.calculateNextEntryPriceX96(SIDE_SHORT, 0, entryPriceX96, 1, tradePriceX96)).to.eq(
                tradePriceX96
            );
        });

        it("should return entry price before x96 if size before is not zero and size delta is zero", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            expect(await positionUtil.calculateNextEntryPriceX96(SIDE_LONG, 1, entryPriceX96, 0, tradePriceX96)).to.eq(
                entryPriceX96
            );
            expect(await positionUtil.calculateNextEntryPriceX96(SIDE_SHORT, 1, entryPriceX96, 0, tradePriceX96)).to.eq(
                entryPriceX96
            );
        });

        describe("size before is not zero and size delta is not zero", () => {
            const sizeDelta = 10n;
            const sizeBefore = 10n;
            it("should round up if side is long", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const nextEntryPriceX96 = mulDiv(
                    sizeBefore * entryPriceX96 + sizeDelta * tradePriceX96,
                    1,
                    sizeBefore + sizeDelta,
                    Rounding.Up
                );
                expect(nextEntryPriceX96).to.not.eq(
                    (sizeBefore * entryPriceX96 + sizeDelta * tradePriceX96) / (sizeBefore + sizeDelta)
                );
                expect(
                    await positionUtil.calculateNextEntryPriceX96(
                        SIDE_LONG,
                        sizeBefore,
                        entryPriceX96,
                        sizeDelta,
                        tradePriceX96
                    )
                ).to.eq(nextEntryPriceX96);
            });

            it("should round down if side is short", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const nextEntryPriceX96 =
                    (sizeBefore * entryPriceX96 + sizeDelta * tradePriceX96) / (sizeBefore + sizeDelta);
                expect(nextEntryPriceX96).to.not.eq(
                    mulDiv(
                        sizeBefore * entryPriceX96 + sizeDelta * tradePriceX96,
                        1,
                        sizeBefore + sizeDelta,
                        Rounding.Up
                    )
                );
                expect(
                    await positionUtil.calculateNextEntryPriceX96(
                        SIDE_SHORT,
                        sizeBefore,
                        entryPriceX96,
                        sizeDelta,
                        tradePriceX96
                    )
                ).to.eq(nextEntryPriceX96);
            });
        });
    });

    describe("#calculateLiquidity", () => {
        it("should round up", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidity = await positionUtil.calculateLiquidity(3, priceX96);
            expect(liquidity).to.eq(mulDiv(3n, priceX96, Q96, Rounding.Up));
        });
    });

    describe("#calculteUnrealizedPnL", () => {
        describe("side is long", () => {
            const side = SIDE_LONG;
            it("should round up if entryPriceX96 is greater than priceX96", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const size = 10000n;
                const entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const priceX96 = toPriceX96("1808.123", DECIMALS_18, DECIMALS_6);
                expect(mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Up)).to.not.eq(
                    mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Down)
                );
                expect(await positionUtil.calculateUnrealizedPnL(side, size, entryPriceX96, priceX96)).to.eq(
                    -mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Up)
                );
            });

            it("should round down if entryPriceX96 is not greater than priceX96", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const size = 10000n;
                const entryPriceX96 = toPriceX96("1808.123", DECIMALS_18, DECIMALS_6);
                let priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                expect(mulDiv(size, priceX96 - entryPriceX96, Q96, Rounding.Down)).to.not.eq(
                    mulDiv(size, priceX96 - entryPriceX96, Q96, Rounding.Up)
                );
                expect(await positionUtil.calculateUnrealizedPnL(side, size, entryPriceX96, priceX96)).to.eq(
                    mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Down)
                );

                priceX96 = entryPriceX96;
                expect(await positionUtil.calculateUnrealizedPnL(side, size, entryPriceX96, priceX96)).to.eq(0n);
            });
        });

        describe("side is short", () => {
            const side = SIDE_SHORT;
            it("should round up if entryPriceX96 is less than priceX96", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const size = 10000n;
                const entryPriceX96 = toPriceX96("1808.123", DECIMALS_18, DECIMALS_6);
                let priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                expect(mulDiv(size, priceX96 - entryPriceX96, Q96, Rounding.Up)).to.not.eq(
                    mulDiv(size, priceX96 - entryPriceX96, Q96, Rounding.Down)
                );
                expect(await positionUtil.calculateUnrealizedPnL(side, size, entryPriceX96, priceX96)).to.eq(
                    -mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Up)
                );
            });

            it("should round down if entryPriceX96 is not less than priceX96", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const size = 10000n;
                const entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
                const priceX96 = toPriceX96("1808.123", DECIMALS_18, DECIMALS_6);
                expect(mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Down)).to.not.eq(
                    mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Up)
                );
                expect(await positionUtil.calculateUnrealizedPnL(side, size, entryPriceX96, priceX96)).to.eq(
                    mulDiv(size, entryPriceX96 - priceX96, Q96, Rounding.Down)
                );
            });
        });
    });

    describe("#chooseFundingRateGrowthX96", () => {
        describe("side is long", () => {
            it("should pass", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const longFundingRateGrowthX96 = await positionUtil.chooseFundingRateGrowthX96(SIDE_LONG);
                expect(longFundingRateGrowthX96).to.eq(3n);
            });
        });
        describe("side is short", () => {
            it("should pass", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const longFundingRateGrowthX96 = await positionUtil.chooseFundingRateGrowthX96(SIDE_SHORT);
                expect(longFundingRateGrowthX96).to.eq(4n);
            });
        });
    });

    describe("#calculateTradingFee", () => {
        it("should round up", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            const size = 1n;
            const tradePriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const tradingFeeRate = 30000n;
            const tradingFee = await positionUtil.calculateTradingFee(size, tradePriceX96, tradingFeeRate);
            expect(mulDiv(size * tradingFeeRate, tradePriceX96, BASIS_POINTS_DIVISOR * Q96, Rounding.Up)).to.not.eq(
                mulDiv(size * tradingFeeRate, tradePriceX96, BASIS_POINTS_DIVISOR * Q96, Rounding.Down)
            );
            expect(tradingFee).to.eq(
                mulDiv(size * tradingFeeRate, tradePriceX96, BASIS_POINTS_DIVISOR * Q96, Rounding.Up)
            );
        });
    });

    describe("#calculateLiquidationFee", () => {
        it("should round up", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            const size = 1n;
            const entryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
            const liquidationFeeRate = 30000n;
            const liquidationFee = await positionUtil.calculateLiquidationFee(size, entryPriceX96, liquidationFeeRate);
            expect(mulDiv(size * liquidationFeeRate, entryPriceX96, BASIS_POINTS_DIVISOR * Q96, Rounding.Up)).to.not.eq(
                mulDiv(size * liquidationFeeRate, entryPriceX96, BASIS_POINTS_DIVISOR * Q96, Rounding.Down)
            );
            expect(liquidationFee).to.eq(
                mulDiv(size * liquidationFeeRate, entryPriceX96, BASIS_POINTS_DIVISOR * Q96, Rounding.Up)
            );
        });
    });

    describe("#calculateFundingFee", () => {
        describe("globalFundingRateGrowthX96 is greater than or equal to positionFundingRateGrowthX96", () => {
            it("should be equal to zero", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const globalFundingRateGrowthX96 = BigInt(
                    new Decimal("1808.234").mul(new Decimal(2).pow(96)).toFixed(0)
                );
                const positionFundingRateGrowthX96 = BigInt(
                    new Decimal("1808.234").mul(new Decimal(2).pow(96)).toFixed(0)
                );
                const fundingFee = await positionUtil.calculateFundingFee(
                    globalFundingRateGrowthX96,
                    positionFundingRateGrowthX96,
                    100000000000
                );
                expect(fundingFee).to.eq(0n);
            });

            it("should round down and be greater than zero", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const globalFundingRateGrowthX96 = BigInt(
                    new Decimal("1809.456").mul(new Decimal(2).pow(96)).toFixed(0)
                );
                const positionFundingRateGrowthX96 = BigInt(
                    new Decimal("1808.234").mul(new Decimal(2).pow(96)).toFixed(0)
                );
                const fundingFee = await positionUtil.calculateFundingFee(
                    globalFundingRateGrowthX96,
                    positionFundingRateGrowthX96,
                    100000000000
                );
                expect(fundingFee).to.eq(
                    mulDiv(globalFundingRateGrowthX96 - positionFundingRateGrowthX96, 100000000000n, Q96, Rounding.Down)
                );
                expect(fundingFee).gt(0n);
            });
        });
        describe("globalFundingRateGrowthX96 is less than positionFundingRateGrowthX96", () => {
            const globalFundingRateGrowthX96 = BigInt(new Decimal("1807.123").mul(new Decimal(2).pow(96)).toFixed(0));
            const positionFundingRateGrowthX96 = BigInt(new Decimal("1808.234").mul(new Decimal(2).pow(96)).toFixed(0));
            it("should round up and be less than zero", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                const fundingFee = await positionUtil.calculateFundingFee(
                    globalFundingRateGrowthX96,
                    positionFundingRateGrowthX96,
                    100000000000
                );
                expect(fundingFee).to.eq(
                    -mulDiv(positionFundingRateGrowthX96 - globalFundingRateGrowthX96, 100000000000n, Q96, Rounding.Up)
                );
                expect(fundingFee).lt(0n);
            });
        });
    });

    describe("#calculateMaintenanceMargin", () => {
        it("should round up", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            const priceX96 = toPriceX96("1807.123", DECIMALS_18, DECIMALS_6);
            const maintenanceMargin = await positionUtil.calculateMaintenanceMargin(
                1000,
                priceX96,
                priceX96,
                200,
                300,
                10000000000
            );
            expect(mulDiv(1000n, priceX96 * 200n + priceX96 * 300n, BASIS_POINTS_DIVISOR * Q96, Rounding.Up)).to.not.eq(
                mulDiv(1000n, priceX96 * 200n + priceX96 * 300n, BASIS_POINTS_DIVISOR * Q96, Rounding.Down)
            );
            expect(maintenanceMargin).to.eq(
                mulDiv(1000n, priceX96 * 200n + priceX96 * 300n, BASIS_POINTS_DIVISOR * Q96, Rounding.Up) + 10000000000n
            );
        });
    });

    describe("#calculateLiquidationPriceX96", () => {
        describe("funding fee would not be adjusted", () => {
            async function testShouldPass(side: Side) {
                const {positionUtil} = await loadFixture(deployFixture);
                const margin = 610_000n;
                const positionSize = 10_000n;
                const positionEntryPriceX96 = Q96;
                const fundingFee = 0n;
                const liquidationFeeRate = 400000n;
                const tradingFeeRate = 50000n;
                const liquidationExecutionFee = 600_000n;

                // (EP*S*(BPD+LFR) - (M-LEF)*BPD*Q96) / (S*(BPD-TFR))
                const _liquidationPriceX96 = _calculateLiquidationPriceX96(
                    side,
                    margin,
                    positionSize,
                    positionEntryPriceX96,
                    fundingFee,
                    liquidationFeeRate,
                    tradingFeeRate,
                    liquidationExecutionFee
                );
                expect(_isAcceptableLiquidationPriceX96(side, _liquidationPriceX96, positionEntryPriceX96)).to.true;

                let position = _newPosition();
                position.margin = margin;
                position.size = positionSize;
                position.entryPriceX96 = positionEntryPriceX96;

                const {liquidationPriceX96, adjustedFundingFee} = await positionUtil.calculateLiquidationPriceX96(
                    position,
                    side,
                    fundingFee,
                    liquidationFeeRate,
                    tradingFeeRate,
                    liquidationExecutionFee
                );
                expect(liquidationPriceX96).to.eq(_liquidationPriceX96);
                expect(adjustedFundingFee).to.eq(fundingFee);
            }

            describe("side is long", () => {
                const side = SIDE_LONG;
                it("should pass if margin after is not less than liquidation execution fee", async () => {
                    await testShouldPass(side);
                });

                it("should revert if the numerator of the formula is negative", async () => {
                    const {positionUtil} = await loadFixture(deployFixture);
                    const margin = 620_000n;
                    const positionSize = 10_000n;
                    const positionEntryPriceX96 = Q96;
                    const fundingFee = 0n;
                    const liquidationFeeRate = 400000n;
                    const tradingFeeRate = 50000n;
                    const liquidationExecutionFee = 600_000n;

                    let position = _newPosition();
                    position.margin = margin;
                    position.size = positionSize;
                    position.entryPriceX96 = positionEntryPriceX96;

                    await expect(
                        positionUtil.calculateLiquidationPriceX96(
                            position,
                            side,
                            fundingFee,
                            liquidationFeeRate,
                            tradingFeeRate,
                            liquidationExecutionFee
                        )
                    ).to.revertedWithPanic("0x11");
                });
            });

            describe("side is short", () => {
                const side = SIDE_SHORT;
                it("should pass if margin after is not less than liquidation execution fee", async () => {
                    await testShouldPass(side);
                });
            });
        });

        describe("funding fee is adjusted based on the previous global funding rate growth", () => {
            describe("margin is enough to pay funding fee", () => {
                const positionSize = 10_000n;
                const positionEntryPriceX96 = Q96;
                const fundingFee = 0n;
                const liquidationFeeRate = 400000n;
                const tradingFeeRate = 50000n;
                const liquidationExecutionFee = 600_000n;

                async function test(margin: bigint, side: Side) {
                    const {positionUtil} = await loadFixture(deployFixture);

                    {
                        const _liquidationPriceX96 = _calculateLiquidationPriceX96(
                            side,
                            margin,
                            positionSize,
                            positionEntryPriceX96,
                            fundingFee,
                            liquidationFeeRate,
                            tradingFeeRate,
                            liquidationExecutionFee
                        );
                        expect(_isAcceptableLiquidationPriceX96(side, _liquidationPriceX96, positionEntryPriceX96)).to
                            .false;
                    }

                    let position = _newPosition();
                    position.margin = margin;
                    position.size = positionSize;
                    position.entryPriceX96 = positionEntryPriceX96;
                    position.entryFundingRateGrowthX96 = 0n;

                    const _adjustedFundingFee = 99n;
                    {
                        // adjust funding fee to 99
                        await positionUtil.setPreviousGlobalFundingRate(Q96 / 100n, Q96 / 100n);
                        expect(await positionUtil.calculateFundingFee(Q96 / 100n, 0n, positionSize)).to.eq(
                            _adjustedFundingFee
                        );
                    }

                    const _liquidationPriceX96 = _calculateLiquidationPriceX96(
                        side,
                        margin,
                        positionSize,
                        positionEntryPriceX96,
                        _adjustedFundingFee,
                        liquidationFeeRate,
                        tradingFeeRate,
                        liquidationExecutionFee
                    );
                    expect(_isAcceptableLiquidationPriceX96(side, _liquidationPriceX96, positionEntryPriceX96)).to.true;

                    const {liquidationPriceX96, adjustedFundingFee} = await positionUtil.calculateLiquidationPriceX96(
                        position,
                        side,
                        fundingFee,
                        liquidationFeeRate,
                        tradingFeeRate,
                        liquidationExecutionFee
                    );
                    expect(liquidationPriceX96).to.eq(_liquidationPriceX96);
                    expect(adjustedFundingFee).to.eq(_adjustedFundingFee);
                }

                describe("margin after is not less than liquidation execution fee", () => {
                    const margin = 600_030n;

                    it("should pass when side is long", async () => {
                        await test(margin, SIDE_LONG);
                    });

                    it("should pass when side is short", async () => {
                        await test(margin, SIDE_SHORT);
                    });
                });

                describe("margin after is less than liquidation execution fee", () => {
                    const margin = 600_000n - 1n;
                    it("should pass when side is long", async () => {
                        await test(margin, SIDE_LONG);
                    });

                    it("should pass when side is short", async () => {
                        await test(margin, SIDE_SHORT);
                    });
                });
            });

            describe("margin is not enough to pay funding fee", () => {
                const positionSize = 10_000n;
                const positionEntryPriceX96 = Q96;
                const liquidationFeeRate = 400000n;
                const tradingFeeRate = 50000n;
                const liquidationExecutionFee = 600_000n;

                const margin = 600_100n;
                const fundingFee = -600_101n;

                async function test(side: Side) {
                    const {positionUtil} = await loadFixture(deployFixture);

                    let position = _newPosition();
                    position.margin = margin;
                    position.size = positionSize;
                    position.entryPriceX96 = positionEntryPriceX96;
                    position.entryFundingRateGrowthX96 = 0n;

                    const _adjustedFundingFee = 99n;
                    {
                        // adjust funding fee to 99
                        await positionUtil.setPreviousGlobalFundingRate(Q96 / 100n, Q96 / 100n);
                        expect(await positionUtil.calculateFundingFee(Q96 / 100n, 0n, positionSize)).to.eq(
                            _adjustedFundingFee
                        );
                    }

                    const _liquidationPriceX96 = _calculateLiquidationPriceX96(
                        side,
                        margin,
                        positionSize,
                        positionEntryPriceX96,
                        _adjustedFundingFee,
                        liquidationFeeRate,
                        tradingFeeRate,
                        liquidationExecutionFee
                    );
                    expect(_isAcceptableLiquidationPriceX96(side, _liquidationPriceX96, positionEntryPriceX96)).to.true;

                    const {liquidationPriceX96, adjustedFundingFee} = await positionUtil.calculateLiquidationPriceX96(
                        position,
                        side,
                        fundingFee,
                        liquidationFeeRate,
                        tradingFeeRate,
                        liquidationExecutionFee
                    );
                    expect(liquidationPriceX96).to.eq(_liquidationPriceX96);
                    expect(adjustedFundingFee).to.eq(_adjustedFundingFee);
                }

                describe("side is long", () => {
                    const side = SIDE_LONG;
                    it("should pass", async () => {
                        await test(side);
                    });
                });

                describe("side is short", () => {
                    const side = SIDE_SHORT;
                    it("should pass", async () => {
                        await test(side);
                    });
                });
            });
        });

        describe("funding fee is adjusted to zero", () => {
            const positionSize = 10_000n;
            const positionEntryPriceX96 = Q96;
            const liquidationFeeRate = 400000n;
            const tradingFeeRate = 50000n;
            const liquidationExecutionFee = 600_000n;

            const margin = 600_100n;
            const fundingFee = -600_102n;

            async function test(side: Side) {
                const {positionUtil} = await loadFixture(deployFixture);

                let position = _newPosition();
                position.margin = margin;
                position.size = positionSize;
                position.entryPriceX96 = positionEntryPriceX96;
                position.entryFundingRateGrowthX96 = (Q96 * 600101n) / 10000n;

                let _adjustedFundingFee = -600_101n;
                {
                    // adjust funding fee to -600_101
                    expect(
                        await positionUtil.calculateFundingFee(0n, position.entryFundingRateGrowthX96, positionSize)
                    ).to.eq(_adjustedFundingFee);
                }
                _adjustedFundingFee = 0n;

                const _liquidationPriceX96 = _calculateLiquidationPriceX96(
                    side,
                    margin,
                    positionSize,
                    positionEntryPriceX96,
                    _adjustedFundingFee,
                    liquidationFeeRate,
                    tradingFeeRate,
                    liquidationExecutionFee
                );
                expect(_isAcceptableLiquidationPriceX96(side, _liquidationPriceX96, positionEntryPriceX96)).to.true;

                const {liquidationPriceX96, adjustedFundingFee} = await positionUtil.calculateLiquidationPriceX96(
                    position,
                    side,
                    fundingFee,
                    liquidationFeeRate,
                    tradingFeeRate,
                    liquidationExecutionFee
                );
                expect(liquidationPriceX96).to.eq(_liquidationPriceX96);
                expect(adjustedFundingFee).to.eq(_adjustedFundingFee);
            }

            describe("side is long", () => {
                const side = SIDE_LONG;
                it("should pass", async () => {
                    await test(side);
                });
            });

            describe("side is short", () => {
                const side = SIDE_SHORT;
                it("should pass", async () => {
                    await test(side);
                });
            });
        });
    });
});

function _isAcceptableLiquidationPriceX96(
    _side: Side,
    _liquidationPriceX96: BigNumberish,
    _entryPriceX96: BigNumberish
): boolean {
    return (
        (isLongSide(_side) && BigNumber.from(_liquidationPriceX96).lt(_entryPriceX96)) ||
        (isShortSide(_side) && BigNumber.from(_liquidationPriceX96).gt(_entryPriceX96))
    );
}

function _calculateLiquidationPriceX96(
    _side: Side,
    _positionMargin: BigNumberish,
    _positionSize: BigNumberish,
    _positionEntryPriceX96: BigNumberish,
    _fundingFee: BigNumberish,
    _liquidationFeeRate: BigNumberish,
    _tradingFeeRate: BigNumberish,
    _liquidationExecutionFee: BigNumberish
): BigNumber {
    let marginAfter = BigNumber.from(_positionMargin);
    let fundingFee = BigNumber.from(_fundingFee);
    marginAfter = marginAfter.add(fundingFee);
    expect(marginAfter).to.gte(0n);
    if (isLongSide(_side)) {
        let numeratorX96 = BigNumber.from(_positionEntryPriceX96)
            .mul(_positionSize)
            .mul(BigNumber.from(BASIS_POINTS_DIVISOR).add(_liquidationFeeRate));
        if (marginAfter.gte(_liquidationExecutionFee)) {
            const numeratorPart2X96 = marginAfter.sub(_liquidationExecutionFee).mul(BASIS_POINTS_DIVISOR).mul(Q96);
            numeratorX96 = numeratorX96.sub(numeratorPart2X96);
            expect(numeratorX96).to.gt(0n);
        } else {
            const numeratorPart2X96 = BigNumber.from(_liquidationExecutionFee)
                .sub(marginAfter)
                .mul(BASIS_POINTS_DIVISOR)
                .mul(Q96);
            numeratorX96 = numeratorX96.add(numeratorPart2X96);
        }
        return numeratorX96.div(
            BigNumber.from(_positionSize).mul(BigNumber.from(BASIS_POINTS_DIVISOR).sub(_tradingFeeRate))
        );
    } else {
        let numeratorX96 = BigNumber.from(_positionEntryPriceX96)
            .mul(_positionSize)
            .mul(BigNumber.from(BASIS_POINTS_DIVISOR).sub(_liquidationFeeRate));
        if (marginAfter.gte(_liquidationExecutionFee)) {
            const numeratorPart2X96 = marginAfter.sub(_liquidationExecutionFee).mul(BASIS_POINTS_DIVISOR).mul(Q96);
            numeratorX96 = numeratorX96.add(numeratorPart2X96);
        } else {
            const numeratorPart2X96 = BigNumber.from(_liquidationExecutionFee)
                .sub(marginAfter)
                .mul(BASIS_POINTS_DIVISOR)
                .mul(Q96);
            numeratorX96 = numeratorX96.sub(numeratorPart2X96);
            expect(numeratorX96).to.gt(0n);
        }
        return BigNumber.from(
            mulDiv(
                numeratorX96,
                1n,
                BigNumber.from(_positionSize).mul(BigNumber.from(BASIS_POINTS_DIVISOR).add(_tradingFeeRate)),
                Rounding.Up
            )
        );
    }
}

function _newPosition() {
    return {
        margin: 0n,
        size: 0n,
        entryPriceX96: 0n,
        entryFundingRateGrowthX96: 0n,
    };
}
