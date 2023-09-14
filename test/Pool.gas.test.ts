import {ethers} from "hardhat";
import {computePoolAddress, initializePoolByteCode} from "./shared/address";
import {ERC20Test} from "../typechain-types";
import {BigNumber, BigNumberish} from "ethers";
import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {
    BASIS_POINTS_DIVISOR,
    DECIMALS_18,
    DECIMALS_6,
    mulDiv,
    SIDE_LONG,
    SIDE_SHORT,
    toPriceX96,
} from "./shared/Constants";
import {concatPoolCreationCode} from "./shared/creationCode";
import {expectSnapshotGasCost} from "./shared/snapshotGasCost";
import {expect} from "chai";
import {newTokenConfig, newTokenFeeRateConfig, newTokenPriceConfig} from "./shared/tokenConfig";

describe("Pool gas tests", () => {
    async function deployFixture() {
        const [owner, other, other2] = await ethers.getSigners();
        const gov = owner;
        const router = owner.address;
        const liquidityPositionLiquidator = owner.address;
        const positionLiquidator = owner.address;

        const PoolUtil = await ethers.getContractFactory("PoolUtil");
        const _poolUtil = await PoolUtil.deploy();
        await _poolUtil.deployed();

        const FundingRateUtil = await ethers.getContractFactory("FundingRateUtil");
        const _fundingRateUtil = await FundingRateUtil.deploy();
        await _fundingRateUtil.deployed();

        const PriceUtil = await ethers.getContractFactory("PriceUtil");
        const _priceUtil = await PriceUtil.deploy();
        await _priceUtil.deployed();

        const PositionUtil = await ethers.getContractFactory("PositionUtil");
        const _positionUtil = await PositionUtil.deploy();
        await _positionUtil.deployed();

        const LiquidityPositionUtil = await ethers.getContractFactory("LiquidityPositionUtil");
        const _liquidityPositionUtil = await LiquidityPositionUtil.deploy();
        await _liquidityPositionUtil.deployed();

        await initializePoolByteCode(
            _poolUtil.address,
            _fundingRateUtil.address,
            _priceUtil.address,
            _positionUtil.address,
            _liquidityPositionUtil.address
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

        const EFC = await ethers.getContractFactory("MockEFC");
        const efc = await EFC.deploy();
        await efc.deployed();
        await efc.initialize(100n, mockRewardFarmCallback.address);

        const PoolFactory = await ethers.getContractFactory("PoolFactory");
        const poolFactory = await PoolFactory.deploy(
            USDC.address,
            efc.address,
            router,
            mockPriceFeed.address,
            feeDistributor.address,
            mockRewardFarmCallback.address
        );
        await poolFactory.deployed();
        await concatPoolCreationCode(poolFactory);

        const tokenCfg = newTokenConfig();
        const tokenFeeRateCfg = newTokenFeeRateConfig();
        const tokenPriceCfg = newTokenPriceConfig();
        await poolFactory.enableToken(ETH.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
        await poolFactory.createPool(ETH.address);
        await poolFactory.grantRole(
            ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_POSITION_LIQUIDATOR")),
            positionLiquidator
        );
        await poolFactory.grantRole(
            ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_LIQUIDITY_POSITION_LIQUIDATOR")),
            liquidityPositionLiquidator
        );

        const poolAddress = computePoolAddress(poolFactory.address, ETH.address, USDC.address);
        const Pool = await ethers.getContractFactory("Pool", {
            libraries: {
                PoolUtil: _poolUtil.address,
                FundingRateUtil: _fundingRateUtil.address,
                PriceUtil: _priceUtil.address,
                PositionUtil: _positionUtil.address,
                LiquidityPositionUtil: _liquidityPositionUtil.address,
            },
        });
        const pool = Pool.attach(poolAddress);

        const LiquidityPositionUtilTest = await ethers.getContractFactory("LiquidityPositionUtilTest", {
            libraries: {
                LiquidityPositionUtil: _liquidityPositionUtil.address,
            },
        });
        const liquidityPositionUtil = await LiquidityPositionUtilTest.deploy();
        await liquidityPositionUtil.deployed();

        const lastTimestamp = await time.latest();

        return {
            owner,
            gov,
            other,
            other2,
            mockPriceFeed,
            poolFactory,
            tokenCfg,
            pool,
            USDC,
            ETH,
            liquidityPositionUtil,
            lastTimestamp,
        };
    }

    describe("#openLiquidityPosition", () => {
        describe("opening the liquidity position for the first time", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await expectSnapshotGasCost(
                    pool.estimateGas.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await time.increase(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n)
                );
            });
        });

        describe("opening the liquidity position with realized PnL", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 40);
                await expectSnapshotGasCost(
                    pool.estimateGas.openLiquidityPosition(owner.address, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.openLiquidityPosition(owner.address, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );
            });
        });

        describe("opening the liquidity position with realized PnL and unrealized loss", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, ETH, mockPriceFeed, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("190", DECIMALS_18, DECIMALS_6));

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 40);
                await expectSnapshotGasCost(
                    pool.estimateGas.openLiquidityPosition(owner.address, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, ETH, mockPriceFeed, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("190", DECIMALS_18, DECIMALS_6));

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.openLiquidityPosition(owner.address, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );
            });
        });
    });

    describe("#closeLiquidityPosition", () => {
        describe("closing the liquidity position", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 40);
                await expectSnapshotGasCost(pool.estimateGas.closeLiquidityPosition(1, owner.address));
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(pool.estimateGas.closeLiquidityPosition(1, owner.address));
            });
        });
    });

    describe("#adjustLiquidityPositionMargin", () => {
        describe("increasing the margin", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 30);
                await expectSnapshotGasCost(
                    pool.estimateGas.adjustLiquidityPositionMargin(1, 100n * 10n ** 6n, owner.address)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.adjustLiquidityPositionMargin(1, 100n * 10n ** 6n, owner.address)
                );
            });
        });

        describe("decreasing the margin", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 30);
                await expectSnapshotGasCost(
                    pool.estimateGas.adjustLiquidityPositionMargin(1, -(100n * 10n ** 6n), owner.address)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.adjustLiquidityPositionMargin(1, -(100n * 10n ** 6n), owner.address)
                );
            });
        });
    });

    describe("#increaseRiskBufferFundPosition", () => {
        it("increase risk buffer fund position", async () => {
            const {pool, USDC, owner, other, lastTimestamp} = await loadFixture(deployFixture);
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expectSnapshotGasCost(
                pool.estimateGas.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n)
            );
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await expectSnapshotGasCost(
                pool.estimateGas.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n)
            );

            await USDC.mint(other.address, 100n * 10n ** 6n);
            await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
            await time.setNextBlockTimestamp(nextHourBegin + 20);
            await expectSnapshotGasCost(
                pool.estimateGas.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n)
            );

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expectSnapshotGasCost(
                pool.estimateGas.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n)
            );
        });
    });

    describe("#decreaseRiskBufferFundPosition", () => {
        describe("decrease risk buffer fund position", () => {
            it("do not adjust funding rate", async () => {
                const {pool, USDC, owner, other, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await USDC.mint(other.address, 100n * 10n ** 6n);
                await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
                await pool.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 30 + 90 * 24 * 60 * 60);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreaseRiskBufferFundPosition(owner.address, 50n * 10n ** 6n, other.address)
                );

                await time.setNextBlockTimestamp(nextHourBegin + 40 + 90 * 24 * 60 * 60);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreaseRiskBufferFundPosition(other.address, 50n * 10n ** 6n, other.address)
                );
            });

            it("with adjusting funding rate", async () => {
                const {pool, USDC, owner, other, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await USDC.mint(other.address, 100n * 10n ** 6n);
                await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
                await pool.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600 + 90 * 24 * 60 * 60);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreaseRiskBufferFundPosition(owner.address, 50n * 10n ** 6n, other.address)
                );

                await time.setNextBlockTimestamp(nextHourBegin + 7200 + 90 * 24 * 60 * 60);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreaseRiskBufferFundPosition(other.address, 50n * 10n ** 6n, other.address)
                );
            });
        });
    });

    describe("#increasePosition", () => {
        describe("opening the position", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 7200);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n)
                );
            });
        });

        describe("increasing the margin", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 0n)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 0n)
                );
            });
        });

        describe("increasing the size", async () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 0n, 10n * 10n ** 6n)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 0n, 10n * 10n ** 6n)
                );
            });
        });

        describe("increasing the size and the margin", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 200);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 10n * 10n ** 6n)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 10n * 10n ** 6n)
                );
            });
        });
    });

    describe("#decreasePosition", () => {
        describe("decreasing the margin", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(owner.address, SIDE_LONG, 10n * 10n ** 6n, 0n, owner.address)
                );
            });

            it("with adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(owner.address, SIDE_LONG, 10n * 10n ** 6n, 0n, owner.address)
                );
            });
        });

        describe("decreasing the size", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(owner.address, SIDE_LONG, 0n, 10n * 10n ** 6n, owner.address)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(owner.address, SIDE_LONG, 0n, 10n * 10n ** 6n, owner.address)
                );
            });
        });

        describe("decreasing the size and the margin", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(
                        owner.address,
                        SIDE_LONG,
                        10n * 10n ** 6n,
                        10n * 10n ** 6n,
                        owner.address
                    )
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(
                        owner.address,
                        SIDE_LONG,
                        10n * 10n ** 6n,
                        10n * 10n ** 6n,
                        owner.address
                    )
                );
            });
        });

        describe("closing the position", () => {
            it("do not adjust funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 20);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(owner.address, SIDE_LONG, 0n, 100n * 10n ** 6n, owner.address)
                );
            });

            it("with adjusting funding rate", async () => {
                const {owner, pool, USDC, lastTimestamp} = await loadFixture(deployFixture);
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, 1000n * 10n ** 6n);
                await pool.openLiquidityPosition(owner.address, 1000n * 10n ** 6n, 1000n * 10n ** 6n);
                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, 100n * 10n ** 6n);
                await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 6n, 100n * 10n ** 6n);

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expectSnapshotGasCost(
                    pool.estimateGas.decreasePosition(owner.address, SIDE_LONG, 0n, 100n * 10n ** 6n, owner.address)
                );
            });
        });
    });

    describe("#liquidatePosition", () => {
        describe("funding fee is adjusted", () => {
            it("opposite size is positive", async () => {
                const {owner, other, pool, poolFactory, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(
                    deployFixture
                );
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                const lastTimestamp = await time.latest();
                let nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await time.setNextBlockTimestamp(nextHourBegin + 5);
                await USDC.mint(other.address, tokenCfg.minMarginPerPosition);
                await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    other.address,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    tokenCfg.minMarginPerLiquidityPosition * 18000000000000n
                );

                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    owner.address,
                    SIDE_LONG,
                    tokenCfg.minMarginPerPosition,
                    tokenCfg.minMarginPerLiquidityPosition
                );

                await time.setNextBlockTimestamp(nextHourBegin + 15);
                await pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition - 1n,
                    owner.address
                );

                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("2", DECIMALS_18, DECIMALS_6));
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expect(pool.collectReferralFee(0, owner.address)).to.emit(pool, "FundingRateGrowthAdjusted");

                let newTokenCfg = newTokenConfig();
                let newTokenFeeRateCfg = newTokenFeeRateConfig();
                let newTokenPriceCfg = newTokenPriceConfig();
                newTokenCfg.liquidationExecutionFee = 9000000n;
                newTokenCfg.liquidationFeeRatePerPosition = 99_000_000n;
                await poolFactory.updateTokenConfig(ETH.address, newTokenCfg, newTokenFeeRateCfg, newTokenPriceCfg);

                await time.setNextBlockTimestamp(nextHourBegin + 3620);
                await expectSnapshotGasCost(
                    pool.estimateGas.liquidatePosition(other.address, SIDE_SHORT, other.address)
                );
            });

            it("opposite size is zero", async () => {
                const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg, poolFactory} = await loadFixture(
                    deployFixture
                );
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                // make riskBufferFund to have some value
                {
                    await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 50n);
                    await pool.openLiquidityPosition(
                        owner.address,
                        tokenCfg.minMarginPerLiquidityPosition * 50n,
                        tokenCfg.minMarginPerLiquidityPosition * 50n
                    );
                    await USDC.mint(other.address, tokenCfg.minMarginPerPosition * 4950n);
                    await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition * 4950n);
                    await pool.openLiquidityPosition(
                        other.address,
                        tokenCfg.minMarginPerLiquidityPosition * 4950n,
                        tokenCfg.minMarginPerLiquidityPosition * 4950n
                    );
                    await USDC.mint(other2.address, tokenCfg.minMarginPerPosition * 1000n);
                    await USDC.connect(other2).transfer(pool.address, tokenCfg.minMarginPerPosition * 1000n);
                    await pool.increasePosition(
                        other2.address,
                        SIDE_LONG,
                        tokenCfg.minMarginPerPosition * 1000n,
                        toPriceX96("1", DECIMALS_18, DECIMALS_6) * 1000n
                    );
                    let priceX96 = BigNumber.from(toPriceX96("1", DECIMALS_18, DECIMALS_6)).mul(2000);
                    await mockPriceFeed.setMinPriceX96(ETH.address, priceX96);
                    await pool.liquidateLiquidityPosition(1n, other.address);
                    await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                    await pool.decreasePosition(
                        other2.address,
                        SIDE_LONG,
                        0n,
                        toPriceX96("1", DECIMALS_18, DECIMALS_6) * 1000n,
                        other2.address
                    );
                    await pool.closeLiquidityPosition(2n, other.address);
                    {
                        const {liquidity} = await pool.globalLiquidityPosition();
                        expect(liquidity).to.eq(0);
                        const {riskBufferFund} = await pool.globalRiskBufferFund();
                        expect(riskBufferFund).to.gt(0n);
                    }
                }

                // do test
                const lastTimestamp = await time.latest();
                let nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await time.setNextBlockTimestamp(nextHourBegin + 5);
                await USDC.mint(other.address, tokenCfg.minMarginPerPosition);
                await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    other.address,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    tokenCfg.minMarginPerLiquidityPosition * 18000000000000n
                );

                await time.setNextBlockTimestamp(nextHourBegin + 10);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    owner.address,
                    SIDE_LONG,
                    tokenCfg.minMarginPerPosition,
                    tokenCfg.minMarginPerLiquidityPosition
                );

                await time.setNextBlockTimestamp(nextHourBegin + 15);
                await pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition,
                    owner.address
                );

                {
                    const globalPosition = await pool.globalPosition();
                    expect(globalPosition.longSize).to.eq(0n);
                }

                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("2", DECIMALS_18, DECIMALS_6));
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                await expect(pool.collectReferralFee(0, owner.address)).to.emit(pool, "FundingRateGrowthAdjusted");

                let newTokenCfg = newTokenConfig();
                let newTokenFeeRateCfg = newTokenFeeRateConfig();
                let newTokenPriceCfg = newTokenPriceConfig();
                newTokenCfg.liquidationExecutionFee = 6000000n;
                newTokenCfg.liquidationFeeRatePerPosition = 90_000_000n;
                await poolFactory.updateTokenConfig(ETH.address, newTokenCfg, newTokenFeeRateCfg, newTokenPriceCfg);

                await time.setNextBlockTimestamp(nextHourBegin + 3620);
                await expectSnapshotGasCost(
                    pool.estimateGas.liquidatePosition(other.address, SIDE_SHORT, other.address)
                );
            });
        });

        it("funding fee is not adjusted", async () => {
            const {owner, other, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            const _sizeDelta = toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n;
            const _marginDelta = tokenCfg.minMarginPerPosition;

            await USDC.transfer(pool.address, _marginDelta);
            await pool.increasePosition(owner.address, SIDE_LONG, _marginDelta, _sizeDelta);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.mint(other.address, _marginDelta);
            await USDC.connect(other).transfer(pool.address, _marginDelta);
            await pool.increasePosition(other.address, SIDE_SHORT, _marginDelta, _sizeDelta);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(pool.decreasePosition(owner.address, SIDE_LONG, 0n, _sizeDelta, owner.address)).to.emit(
                pool,
                "FundingRateGrowthAdjusted"
            );

            await time.setNextBlockTimestamp(nextHourBegin + 3605);
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("2", DECIMALS_18, DECIMALS_6) + 2n);

            await time.setNextBlockTimestamp(nextHourBegin + 3620);
            await expectSnapshotGasCost(pool.estimateGas.liquidatePosition(other.address, SIDE_SHORT, other.address));
        });
    });

    describe("#liquidateLiquidityPosition", () => {
        it("remaining margin is not less than liquidation execution fee", async () => {
            const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg, liquidityPositionUtil} =
                await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 300n
            );
            await USDC.mint(other.address, tokenCfg.minMarginPerPosition * 100n);
            await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition * 100n);
            await pool.openLiquidityPosition(
                other.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            expect(await USDC.balanceOf(other.address)).to.eq(0n);

            await USDC.mint(other2.address, tokenCfg.minMarginPerPosition * 100n);
            await USDC.connect(other2).transfer(pool.address, tokenCfg.minMarginPerPosition * 100n);
            await pool.increasePosition(
                other2.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 100n,
                toPriceX96("1", DECIMALS_18, DECIMALS_6) * 1600n
            );
            const priceX96 = toPriceX96("1", DECIMALS_18, DECIMALS_6) * 12n;
            await mockPriceFeed.setMinPriceX96(ETH.address, priceX96);

            const globalLiquidityPosition = await pool.globalLiquidityPosition();
            const globalRiskBufferFund = await pool.globalRiskBufferFund();
            const globalMetric = await pool.globalUnrealizedLossMetrics();
            const liquidityPosition = await pool.liquidityPositions(1n);
            const positionRealizedProfit = await liquidityPositionUtil.calculateRealizedProfit(
                liquidityPosition,
                globalLiquidityPosition
            );
            let marginAfter = liquidityPosition.margin.add(positionRealizedProfit);
            const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                globalLiquidityPosition.side,
                globalLiquidityPosition.netSize,
                globalLiquidityPosition.entryPriceX96,
                priceX96,
                globalRiskBufferFund.riskBufferFund
            );
            const positionUnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                liquidityPosition,
                globalMetric,
                globalLiquidityPosition.liquidity,
                unrealizedLoss
            );
            let liquidationExecutionFee = BigNumber.from(tokenCfg.liquidationExecutionFee);
            expect(
                _validateLiquidityPositionRiskRate(
                    tokenCfg.maxRiskRatePerLiquidityPosition,
                    marginAfter,
                    liquidationExecutionFee,
                    positionUnrealizedLoss,
                    true
                )
            ).to.true;
            expect(marginAfter).to.gt(liquidationExecutionFee);

            await time.setNextBlockTimestamp(nextHourBegin + 30);
            await expectSnapshotGasCost(pool.estimateGas.liquidateLiquidityPosition(1n, other.address));
        });
    });
});

function _validateLiquidityPositionRiskRate(
    _maxRiskRate: BigNumberish,
    _margin: BigNumberish,
    _liquidationExecutionFee: BigNumberish,
    _positionUnrealizedLoss: BigNumberish,
    _liquidatablePosition: boolean
) {
    const maxRiskRate = BigNumber.from(_maxRiskRate);
    const margin = BigNumber.from(_margin);
    const liquidationExecutionFee = BigNumber.from(_liquidationExecutionFee);
    const positionUnrealizedLoss = BigNumber.from(_positionUnrealizedLoss);
    if (_liquidatablePosition) {
        if (
            margin.gt(liquidationExecutionFee.add(positionUnrealizedLoss)) &&
            mulDiv(margin.sub(liquidationExecutionFee), maxRiskRate, BASIS_POINTS_DIVISOR) >
                positionUnrealizedLoss.toBigInt()
        ) {
            return false;
        }
    } else {
        if (
            margin.lt(liquidationExecutionFee.add(positionUnrealizedLoss)) ||
            mulDiv(margin.sub(liquidationExecutionFee), maxRiskRate, BASIS_POINTS_DIVISOR) <=
                positionUnrealizedLoss.toBigInt()
        ) {
            return false;
        }
    }
    return true;
}
