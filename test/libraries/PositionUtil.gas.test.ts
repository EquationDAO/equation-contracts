import {ethers} from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expectSnapshotGasCost} from "../shared/snapshotGasCost";
import {DECIMALS_18, DECIMALS_6, SIDE_LONG, SIDE_SHORT, toPriceX96} from "../shared/Constants";

describe("PositionUtil gas tests", () => {
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

    describe("#calculateUnrealizedPnL", () => {
        describe("side is long", () => {
            it("entry price greater than current price", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                await expectSnapshotGasCost(
                    positionUtil.getGasCostCalculateUnrealizedPnL(
                        SIDE_LONG,
                        10n ** 18n,
                        toPriceX96("1808.234", DECIMALS_18, DECIMALS_6),
                        toPriceX96("1805.234", DECIMALS_18, DECIMALS_6)
                    )
                );
            });

            it("entry price less than current price", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                await expectSnapshotGasCost(
                    positionUtil.getGasCostCalculateUnrealizedPnL(
                        SIDE_LONG,
                        10n ** 18n,
                        toPriceX96("1805.234", DECIMALS_18, DECIMALS_6),
                        toPriceX96("1808.234", DECIMALS_18, DECIMALS_6)
                    )
                );
            });
        });

        describe("side is short", () => {
            it("entry price greater than current price", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                await expectSnapshotGasCost(
                    positionUtil.getGasCostCalculateUnrealizedPnL(
                        SIDE_SHORT,
                        10n ** 18n,
                        toPriceX96("1808.234", DECIMALS_18, DECIMALS_6),
                        toPriceX96("1805.234", DECIMALS_18, DECIMALS_6)
                    )
                );
            });

            it("entry price less than current price", async () => {
                const {positionUtil} = await loadFixture(deployFixture);
                await expectSnapshotGasCost(
                    positionUtil.getGasCostCalculateUnrealizedPnL(
                        SIDE_SHORT,
                        10n ** 18n,
                        toPriceX96("1805.234", DECIMALS_18, DECIMALS_6),
                        toPriceX96("1808.234", DECIMALS_18, DECIMALS_6)
                    )
                );
            });
        });
    });

    it("#calculateMaintenanceMargin", async () => {
        const {positionUtil} = await loadFixture(deployFixture);
        const priceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
        await expectSnapshotGasCost(positionUtil.getGasCostCalculateMaintenanceMargin(100, 1, priceX96, 40, 2, 60000));
    });

    describe("#calculateLiquidationPriceX96", () => {
        const margin = 100000000000n;
        const positionSize = 10n ** 20n;
        const positionEntryPriceX96 = toPriceX96("1808.234", DECIMALS_18, DECIMALS_6);
        const liquidationFeeRate = 400000n;
        const tradingFeeRate = 50000n;

        it("side is long", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            let position = _newPosition();
            position.margin = margin;
            position.size = positionSize;
            position.entryPriceX96 = positionEntryPriceX96;
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_LONG,
                    0,
                    liquidationFeeRate,
                    tradingFeeRate,
                    1000000000n
                )
            );
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_LONG,
                    -10,
                    liquidationFeeRate,
                    tradingFeeRate,
                    1000000000n
                )
            );
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_LONG,
                    0,
                    liquidationFeeRate,
                    tradingFeeRate,
                    100000000001n
                )
            );
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_LONG,
                    -10,
                    liquidationFeeRate,
                    tradingFeeRate,
                    100000000001n
                )
            );
        });

        it("side is short", async () => {
            const {positionUtil} = await loadFixture(deployFixture);
            let position = _newPosition();
            position.margin = margin;
            position.size = positionSize;
            position.entryPriceX96 = positionEntryPriceX96;
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_SHORT,
                    0,
                    liquidationFeeRate,
                    tradingFeeRate,
                    1000000000n
                )
            );
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_SHORT,
                    -10,
                    liquidationFeeRate,
                    tradingFeeRate,
                    1000000000n
                )
            );
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_SHORT,
                    0,
                    liquidationFeeRate,
                    tradingFeeRate,
                    100000000001n
                )
            );
            await expectSnapshotGasCost(
                positionUtil.getGasCostCalculateLiquidationPriceX96(
                    position,
                    SIDE_SHORT,
                    -10,
                    liquidationFeeRate,
                    tradingFeeRate,
                    100000000001n
                )
            );
        });
    });
});

function _newPosition() {
    return {
        margin: 0n,
        size: 0n,
        entryPriceX96: 0n,
        entryFundingRateGrowthX96: 0n,
    };
}
