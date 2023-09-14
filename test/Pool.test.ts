import {ethers} from "hardhat";
import {computePoolAddress, initializePoolByteCode} from "./shared/address";
import {expect} from "chai";
import {
    ERC20Test,
    IPool,
    LiquidityPositionUtilTest,
    MockEFC,
    MockPriceFeed,
    Pool,
    PoolFactory,
    PositionUtilTest,
    PriceUtilTest,
} from "../typechain-types";
import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {BigNumber, BigNumberish} from "ethers";
import {
    BASIS_POINTS_DIVISOR,
    DECIMALS_18,
    DECIMALS_6,
    flipSide,
    isLongSide,
    LATEST_VERTEX,
    mulDiv,
    PREMIUM_RATE_AVG_DENOMINATOR,
    PREMIUM_RATE_CLAMP_BOUNDARY_X96,
    Q64,
    Q96,
    Rounding,
    Side,
    SIDE_LONG,
    SIDE_SHORT,
    toPriceX96,
} from "./shared/Constants";
import {concatPoolCreationCode} from "./shared/creationCode";
import {newTokenConfig, newTokenFeeRateConfig, newTokenPriceConfig} from "./shared/tokenConfig";

describe("Pool", () => {
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

        const PositionUtilTest = await ethers.getContractFactory("PositionUtilTest", {
            libraries: {
                PositionUtil: _positionUtil.address,
            },
        });
        const positionUtil = await PositionUtilTest.deploy();
        await positionUtil.deployed();

        const LiquidityPositionUtilTest = await ethers.getContractFactory("LiquidityPositionUtilTest", {
            libraries: {
                LiquidityPositionUtil: _liquidityPositionUtil.address,
            },
        });
        const liquidityPositionUtil = await LiquidityPositionUtilTest.deploy();
        await liquidityPositionUtil.deployed();

        const FundingRateUtilTest = await ethers.getContractFactory("FundingRateUtilTest", {
            libraries: {
                FundingRateUtil: _fundingRateUtil.address,
            },
        });
        const fundingRateUtil = await FundingRateUtilTest.deploy();
        await fundingRateUtil.deployed();

        const PriceUtilTest = await ethers.getContractFactory("PriceUtilTest", {
            libraries: {
                PriceUtil: _priceUtil.address,
            },
        });
        const priceUtil = await PriceUtilTest.deploy();
        await priceUtil.deployed();

        return {
            owner,
            gov,
            other,
            other2,
            router,
            positionLiquidator,
            liquidityPositionLiquidator,
            mockPriceFeed,
            feeDistributor,
            efc,
            mockRewardFarmCallback,
            mockFeeDistributorCallback,
            poolFactory,
            tokenCfg,
            tokenFeeRateCfg,
            tokenPriceCfg,
            _fundingRateUtil,
            _priceUtil,
            _liquidityPositionUtil,
            pool,
            USDC,
            ETH,
            positionUtil,
            liquidityPositionUtil,
            fundingRateUtil,
            priceUtil,
        };
    }

    describe("#constructor", () => {
        it("should pass", async () => {
            const [owner] = await ethers.getSigners();
            const router = owner;

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

            const EQU = await ethers.getContractFactory("EQU");
            const equ = await EQU.deploy();
            await equ.deployed();

            const veEQU = await ethers.getContractFactory("veEQU");
            const veequ = await veEQU.deploy();
            await veequ.deployed();

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
                router.address,
                mockPriceFeed.address,
                feeDistributor.address,
                mockRewardFarmCallback.address
            );
            await poolFactory.deployed();
            await concatPoolCreationCode(poolFactory);

            await poolFactory.enableToken(
                mockPriceFeed.address,
                newTokenConfig(),
                newTokenFeeRateConfig(),
                newTokenPriceConfig()
            );

            const poolAddress = computePoolAddress(poolFactory.address, mockPriceFeed.address, USDC.address);
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

            await poolFactory.createPool(mockPriceFeed.address);

            expect(await pool.token()).to.eq(mockPriceFeed.address);

            const lastTimestamp = await time.latest();
            expect((await pool.globalFundingRateSample()).lastAdjustFundingRateTime).to.eq(
                lastTimestamp - (lastTimestamp % 3600)
            );
        });
    });

    describe("#openLiquidityPosition", () => {
        it("should revert if caller is not router", async () => {
            const {pool, other, owner} = await loadFixture(deployFixture);
            await expect(pool.connect(other).openLiquidityPosition(ethers.constants.AddressZero, 0n, 0n))
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(owner.address);
        });

        it("should revert if liquidity is zero", async () => {
            const {pool} = await loadFixture(deployFixture);
            await expect(pool.openLiquidityPosition(ethers.constants.AddressZero, 0n, 0n)).to.revertedWithCustomError(
                pool,
                "InvalidLiquidityToOpen"
            );
        });

        it("should revert if margin too low", async () => {
            const {pool, tokenCfg} = await loadFixture(deployFixture);
            const minMargin = tokenCfg.minMarginPerLiquidityPosition;
            await expect(
                pool.openLiquidityPosition(ethers.constants.AddressZero, minMargin - 1n, 1n)
            ).to.revertedWithCustomError(pool, "InsufficientMargin");
        });

        it("should revert if leverage too high", async () => {
            const {pool, tokenCfg} = await loadFixture(deployFixture);
            const leverage = tokenCfg.maxLeveragePerLiquidityPosition;
            await expect(
                pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition,
                    BigNumber.from(tokenCfg.minMarginPerLiquidityPosition).mul(leverage).add(1)
                )
            )
                .to.revertedWithCustomError(pool, "LeverageTooHigh")
                .withArgs(
                    tokenCfg.minMarginPerLiquidityPosition,
                    BigNumber.from(tokenCfg.minMarginPerLiquidityPosition).mul(leverage).add(1),
                    tokenCfg.maxLeveragePerLiquidityPosition
                );
        });

        it("should revert if balance not enough", async () => {
            const {pool, USDC, tokenCfg} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition - 1n);
            await expect(
                pool.openLiquidityPosition(ethers.constants.AddressZero, tokenCfg.minMarginPerLiquidityPosition, 10n)
            )
                .to.revertedWithCustomError(pool, "InsufficientBalance")
                .withArgs(0, tokenCfg.minMarginPerLiquidityPosition);
        });

        it("should sample and adjust funding fee", async () => {
            const {owner, pool, _fundingRateUtil, USDC, tokenCfg} = await loadFixture(deployFixture);

            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(owner.address, tokenCfg.minMarginPerPosition, 1n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            const assertion = expect(pool.openLiquidityPosition(owner.address, tokenCfg.minMarginPerPosition, 1n));
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
            const {owner, pool, USDC, tokenCfg} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition);
            await expect(
                pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition,
                    tokenCfg.minMarginPerLiquidityPosition
                )
            )
                .to.emit(pool, "GlobalUnrealizedLossMetricsChanged")
                .withArgs(() => true, 0, 0);

            {
                const {lastZeroLossTime, liquidity} = await pool.globalUnrealizedLossMetrics();
                expect(lastZeroLossTime).to.gt(0n);
                expect(liquidity).to.eq(0n);
            }
        });

        it("should emit LiquidityPositionOpened event", async () => {
            const {owner, pool, USDC, tokenCfg} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition);
            await expect(
                pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition,
                    tokenCfg.minMarginPerLiquidityPosition + 1n
                )
            )
                .to.emit(pool, "LiquidityPositionOpened")
                .withArgs(
                    owner.address,
                    1,
                    tokenCfg.minMarginPerLiquidityPosition,
                    tokenCfg.minMarginPerLiquidityPosition + 1n,
                    0n,
                    0n
                );

            {
                const {liquidity, netSize, entryPriceX96, side, realizedProfitGrowthX64} =
                    await pool.globalLiquidityPosition();
                expect(liquidity).to.eq(tokenCfg.minMarginPerLiquidityPosition + 1n);
                expect(netSize).to.eq(0);
                expect(entryPriceX96).to.eq(0);
                expect(side).to.eq(0);
                expect(realizedProfitGrowthX64).to.eq(0n);
            }

            {
                const {margin, liquidity, entryUnrealizedLoss, entryRealizedProfitGrowthX64, entryTime, account} =
                    await pool.liquidityPositions(1n);
                expect(margin).to.eq(tokenCfg.minMarginPerLiquidityPosition);
                expect(liquidity).to.eq(tokenCfg.minMarginPerLiquidityPosition + 1n);
                expect(entryUnrealizedLoss).to.eq(0n);
                expect(entryRealizedProfitGrowthX64).to.eq(0n);
                expect(entryTime).to.gt(0n);
                expect(account).to.eq(owner.address);
            }
        });

        it("should emit PriceVertexChanged event", async () => {
            const {owner, pool, USDC, ETH, tokenCfg, mockPriceFeed, poolFactory} = await loadFixture(deployFixture);
            const priceState = await pool.priceState();
            const changePriceVerticesResult = await _changePriceVertices(
                priceState,
                mockPriceFeed,
                poolFactory,
                ETH,
                tokenCfg.minMarginPerLiquidityPosition + 1n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition);
            const assertion = expect(
                pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition,
                    tokenCfg.minMarginPerLiquidityPosition + 1n
                )
            );
            for (const value of changePriceVerticesResult) {
                await assertion.to
                    .emit(pool, "PriceVertexChanged")
                    .withArgs(value.vertexIndex, value.sizeAfter, value.premiumRateAfterX96);
            }
        });

        it("should pass", async () => {
            const {owner, pool, USDC, tokenCfg} = await loadFixture(deployFixture);
            for (let i = 0; i < 10; i++) {
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition);
                await expect(
                    pool.openLiquidityPosition(
                        owner.address,
                        tokenCfg.minMarginPerLiquidityPosition,
                        tokenCfg.minMarginPerLiquidityPosition + 1n
                    )
                )
                    .to.emit(pool, "LiquidityPositionOpened")
                    .withArgs(
                        owner.address,
                        i + 1,
                        tokenCfg.minMarginPerLiquidityPosition,
                        tokenCfg.minMarginPerLiquidityPosition + 1n,
                        0n,
                        0n
                    );

                {
                    const {liquidity, netSize, entryPriceX96, side, realizedProfitGrowthX64} =
                        await pool.globalLiquidityPosition();
                    expect(liquidity).to.eq(
                        BigNumber.from(tokenCfg.minMarginPerLiquidityPosition)
                            .add(1n)
                            .mul(i + 1)
                    );
                    expect(netSize).to.eq(0);
                    expect(entryPriceX96).to.eq(0);
                    expect(side).to.eq(0);
                    expect(realizedProfitGrowthX64).to.eq(0n);
                }

                {
                    const {margin, liquidity, entryUnrealizedLoss, entryRealizedProfitGrowthX64, entryTime, account} =
                        await pool.liquidityPositions(i + 1);
                    expect(margin).to.eq(tokenCfg.minMarginPerLiquidityPosition);
                    expect(liquidity).to.eq(tokenCfg.minMarginPerLiquidityPosition + 1n);
                    expect(entryUnrealizedLoss).to.eq(0n);
                    expect(entryRealizedProfitGrowthX64).to.eq(0n);
                    expect(entryTime).to.gt(0n);
                    expect(account).to.eq(owner.address);
                }
            }
        });

        it("should callback for reward farm", async () => {
            const {owner, pool, USDC, tokenCfg, mockRewardFarmCallback} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition,
                tokenCfg.minMarginPerLiquidityPosition + 1n
            );
            expect(await mockRewardFarmCallback.account()).to.eq(owner.address);
            expect(await mockRewardFarmCallback.liquidityDelta()).to.eq(tokenCfg.minMarginPerLiquidityPosition + 1n);
        });
    });

    describe("#liquidityPositionAccount", () => {
        it("should return right account if the liquidity position exist", async () => {
            const {owner, other, pool, USDC, tokenCfg} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition,
                tokenCfg.minMarginPerLiquidityPosition + 1n
            );
            await USDC.mint(other.address, tokenCfg.minMarginPerLiquidityPosition);
            await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition);
            await pool.openLiquidityPosition(
                other.address,
                tokenCfg.minMarginPerLiquidityPosition,
                tokenCfg.minMarginPerLiquidityPosition + 1n
            );

            expect(await pool.liquidityPositionAccount(1n)).to.eq(owner.address);
            expect(await pool.liquidityPositionAccount(2n)).to.eq(other.address);
        });

        it("should return zero address if the liquidity position not exist", async () => {
            const {pool} = await loadFixture(deployFixture);
            expect(await pool.liquidityPositionAccount(1n)).to.eq(ethers.constants.AddressZero);
        });
    });

    describe("#closeLiquidityPosition", () => {
        it("should revert if caller is not router", async () => {
            const {pool, other, owner} = await loadFixture(deployFixture);
            await expect(pool.connect(other).closeLiquidityPosition(1n, other.address))
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(owner.address);
        });

        it("should revert if liquidity position does not exist", async () => {
            const {pool, owner} = await loadFixture(deployFixture);
            await expect(pool.closeLiquidityPosition(1n, owner.address))
                .to.revertedWithCustomError(pool, "LiquidityPositionNotFound")
                .withArgs(1n);
        });

        it("should revert if liquidity equal to global liquidity", async () => {
            const {pool, USDC, other, owner, tokenCfg} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(other.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.increasePosition(
                other.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition
            );

            await expect(pool.closeLiquidityPosition(1n, owner.address)).to.revertedWithCustomError(
                pool,
                "LastLiquidityPositionCannotBeClosed"
            );
        });

        it("should revert if risk rate is too high", async () => {
            const {pool, ETH, USDC, other, owner, mockPriceFeed, tokenCfg, liquidityPositionUtil} = await loadFixture(
                deployFixture
            );
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                other.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(other.address, tokenCfg.minMarginPerPosition, 1n);

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                other.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("6000000000", DECIMALS_18, DECIMALS_6));

            const globalLiquidityPosition = await pool.globalLiquidityPosition();
            const globalRiskBufferFund = await pool.globalRiskBufferFund();
            const liquidityPosition = await pool.liquidityPositions(1n);
            const globalMetrics = await pool.globalUnrealizedLossMetrics();
            const indexPriceX96 = await mockPriceFeed.getMinPriceX96(ETH.address);
            const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                globalLiquidityPosition.side,
                globalLiquidityPosition.netSize,
                globalLiquidityPosition.entryPriceX96,
                indexPriceX96,
                globalRiskBufferFund.riskBufferFund
            );
            const positionRealizedProfit = await liquidityPositionUtil.calculateRealizedProfit(
                liquidityPosition,
                globalLiquidityPosition
            );
            let marginAfter = liquidityPosition.margin.add(positionRealizedProfit);
            const positionUnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                liquidityPosition,
                globalMetrics,
                globalLiquidityPosition.liquidity,
                unrealizedLoss
            );
            expect(globalLiquidityPosition.liquidity).to.gt(liquidityPosition.liquidity);
            expect(
                _validateLiquidityPositionRiskRate(
                    tokenCfg.maxRiskRatePerLiquidityPosition,
                    marginAfter,
                    tokenCfg.liquidationExecutionFee,
                    positionUnrealizedLoss,
                    false
                )
            ).to.false;

            await expect(pool.closeLiquidityPosition(1n, owner.address)).to.revertedWithCustomError(
                pool,
                "RiskRateTooHigh"
            );
        });

        it("should sample and adjust funding rate", async () => {
            const {owner, tokenCfg, pool, _fundingRateUtil, USDC} = await loadFixture(deployFixture);

            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(owner.address, tokenCfg.minMarginPerPosition, 1n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                owner.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const assertion = expect(pool.closeLiquidityPosition(1n, owner.address));
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should update riskBufferFund", async () => {
            const {owner, tokenCfg, pool, USDC, ETH, mockPriceFeed} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(owner.address, tokenCfg.minMarginPerPosition, 1n);

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                owner.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1820", DECIMALS_18, DECIMALS_6));

            const {riskBufferFund: riskBufferFundBefore} = await pool.globalRiskBufferFund();

            let positionUnrealizedLoss: BigNumber;
            const assertion = expect(pool.closeLiquidityPosition(1n, owner.address));
            await assertion.to.emit(pool, "LiquidityPositionClosed").withArgs(
                1n,
                () => true,
                (n: BigNumber) => {
                    positionUnrealizedLoss = n;
                    return true;
                },
                () => true,
                owner.address
            );

            const {liquidity: liquidityAfter} = await pool.globalLiquidityPosition();
            const {riskBufferFund: riskBufferFundAfter} = await pool.globalRiskBufferFund();
            expect(liquidityAfter).to.eq(1n);
            expect(riskBufferFundAfter).to.eq(riskBufferFundBefore.add(positionUnrealizedLoss!));
            await assertion.to.emit(pool, "GlobalRiskBufferFundChanged").withArgs(riskBufferFundAfter);
        });

        it("should emit GlobalRiskBufferFundChanged with unchanged riskBufferFund if unrealized loss is zero", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 5000n * 10n ** 18n);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 5000n * 10n ** 18n);

            const {riskBufferFund} = await pool.globalRiskBufferFund();

            await expect(pool.closeLiquidityPosition(1n, owner.address))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(riskBufferFund);
        });

        it("should pass", async () => {
            const {
                owner,
                pool,
                poolFactory,
                ETH,
                USDC,
                liquidityPositionUtil,
                mockPriceFeed,
                tokenCfg,
                mockRewardFarmCallback,
            } = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                owner.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            const globalLiquidityPosition = await pool.globalLiquidityPosition();
            const globalRiskBufferFund = await pool.globalRiskBufferFund();
            const liquidityPosition = await pool.liquidityPositions(1n);
            const globalMetrics = await pool.globalUnrealizedLossMetrics();
            const indexPriceX96 = await mockPriceFeed.getMinPriceX96(ETH.address);
            const unrealizedLoss = await liquidityPositionUtil.calculateUnrealizedLoss(
                globalLiquidityPosition.side,
                globalLiquidityPosition.netSize,
                globalLiquidityPosition.entryPriceX96,
                indexPriceX96,
                globalRiskBufferFund.riskBufferFund
            );
            const positionRealizedProfit = await liquidityPositionUtil.calculateRealizedProfit(
                liquidityPosition,
                globalLiquidityPosition
            );
            let marginAfter = liquidityPosition.margin.add(positionRealizedProfit);
            let globalLiquidityAfter = globalLiquidityPosition.liquidity.sub(liquidityPosition.liquidity);
            const positionUnrealizedLoss = await liquidityPositionUtil.calculatePositionUnrealizedLoss(
                liquidityPosition,
                globalMetrics,
                globalLiquidityPosition.liquidity,
                unrealizedLoss
            );
            expect(globalLiquidityPosition.liquidity).to.gt(liquidityPosition.liquidity);
            expect(
                _validateLiquidityPositionRiskRate(
                    tokenCfg.maxRiskRatePerLiquidityPosition,
                    marginAfter,
                    tokenCfg.liquidationExecutionFee,
                    positionUnrealizedLoss,
                    false
                )
            ).to.true;

            marginAfter = marginAfter.sub(positionUnrealizedLoss);
            const riskBufferFundAfter = globalRiskBufferFund.riskBufferFund.add(positionUnrealizedLoss);
            const changePriceVerticesResult = await _changePriceVertices(
                await pool.priceState(),
                mockPriceFeed,
                poolFactory,
                ETH,
                globalLiquidityAfter
            );

            const assertion = expect(pool.closeLiquidityPosition(1n, owner.address));
            await assertion.changeTokenBalances(USDC, [pool, owner], [-marginAfter.toBigInt(), marginAfter]);
            await assertion.to.emit(pool, "GlobalRiskBufferFundChanged").withArgs(riskBufferFundAfter);
            await assertion.to
                .emit(pool, "LiquidityPositionClosed")
                .withArgs(1n, marginAfter, positionUnrealizedLoss, positionRealizedProfit, owner.address);
            for (const value of changePriceVerticesResult) {
                await assertion.to
                    .emit(pool, "PriceVertexChanged")
                    .withArgs(value.vertexIndex, value.sizeAfter, value.premiumRateAfterX96);
            }

            expect(await mockRewardFarmCallback.account()).to.eq(owner.address);
            expect(await mockRewardFarmCallback.liquidityDelta()).to.eq(-liquidityPosition.liquidity.toBigInt());
        });
    });

    describe("#adjustLiquidityPositionMargin", () => {
        it("should revert if caller is not router", async () => {
            const {pool, other, owner} = await loadFixture(deployFixture);
            await expect(pool.connect(other).adjustLiquidityPositionMargin(1n, 1n, other.address))
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(owner.address);
        });

        it("should revert if position does not exist", async () => {
            const {pool, owner} = await loadFixture(deployFixture);
            await expect(pool.adjustLiquidityPositionMargin(1n, 1n, owner.address))
                .to.revertedWithCustomError(pool, "LiquidityPositionNotFound")
                .withArgs(1n);
        });

        it("should revert if balance not enough", async () => {
            const {pool, USDC, other, owner} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.openLiquidityPosition(other.address, 100n * 10n ** 6n, 100n * 10n ** 6n);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.adjustLiquidityPositionMargin(1n, 1000n * 10n ** 6n, owner.address))
                .to.revertedWithCustomError(pool, "InsufficientBalance")
                .withArgs(100n * 10n ** 6n, 1000n * 10n ** 6n);
        });

        it("should revert if leverage too high", async () => {
            const {pool, USDC, other, owner} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.openLiquidityPosition(other.address, 100n * 10n ** 6n, 20_000n * 10n ** 6n);

            await expect(
                pool.adjustLiquidityPositionMargin(1n, -(10n ** 6n), owner.address)
            ).to.revertedWithCustomError(pool, "LeverageTooHigh");
        });

        it("should revert if risk rate too high", async () => {
            const {pool, ETH, USDC, owner, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);

            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(owner.address, tokenCfg.minMarginPerPosition, 1n);

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                owner.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("6000000000", DECIMALS_18, DECIMALS_6));

            await expect(
                pool.adjustLiquidityPositionMargin(1n, 1n - tokenCfg.minMarginPerPosition, owner.address)
            ).to.revertedWithCustomError(pool, "RiskRateTooHigh");
        });

        it("should sample and adjust funding rate", async () => {
            const {pool, USDC, owner, _fundingRateUtil} = await loadFixture(deployFixture);

            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await USDC.transfer(pool.address, 50n * 10n ** 18n);
            const assertion = expect(pool.adjustLiquidityPositionMargin(1, 50n * 10n ** 18n, owner.address));
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should pass if margin delta is positive", async () => {
            const {pool, USDC, owner} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 100n * 10n ** 18n, 100n * 10n ** 18n);

            const {realizedProfitGrowthX64} = await pool.globalLiquidityPosition();

            await USDC.transfer(pool.address, 50n * 10n ** 18n);
            await expect(pool.adjustLiquidityPositionMargin(1, 50n * 10n ** 18n, owner.address))
                .to.emit(pool, "LiquidityPositionMarginAdjusted")
                .withArgs(1n, 50n * 10n ** 18n, 150000000000045206893n, realizedProfitGrowthX64, owner.address);

            const {margin, liquidity, entryRealizedProfitGrowthX64} = await pool.liquidityPositions(1);
            expect(margin).to.eq(150000000000045206893n);
            expect(liquidity).to.eq(20_000n * 10n ** 18n);
            expect(entryRealizedProfitGrowthX64).to.eq(realizedProfitGrowthX64);
        });

        it("should pass if margin delta is negative", async () => {
            const {pool, USDC, other} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(other.address, 100n * 10n ** 18n, 10_000n * 10n ** 18n);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.increasePosition(other.address, SIDE_LONG, 100n * 10n ** 18n, 100n * 10n ** 18n);

            const {realizedProfitGrowthX64} = await pool.globalLiquidityPosition();

            const assertion = expect(pool.adjustLiquidityPositionMargin(1, -(50n * 10n ** 18n), other.address));
            await assertion.to
                .emit(pool, "LiquidityPositionMarginAdjusted")
                .withArgs(1n, -(50n * 10n ** 18n), 50000000000045206893n, realizedProfitGrowthX64, other.address);
            await assertion.changeTokenBalances(USDC, [pool, other], [-(50n * 10n ** 18n), 50n * 10n ** 18n]);

            const {margin, liquidity, entryRealizedProfitGrowthX64} = await pool.liquidityPositions(1);
            expect(margin).to.eq(50000000000045206893n);
            expect(liquidity).to.eq(10_000n * 10n ** 18n);
            expect(entryRealizedProfitGrowthX64).to.eq(realizedProfitGrowthX64);
        });
    });

    describe("#govUseRiskBufferFund", () => {
        it("should revert if caller is not the gov of pool factory", async () => {
            const {pool, gov, other} = await loadFixture(deployFixture);
            await expect(pool.connect(other).govUseRiskBufferFund(other.address, 1000000n))
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(gov.address);
        });

        it("should revert if global risk buffer fund is not enough to pay", async () => {
            const {pool, _liquidityPositionUtil, USDC, ETH, owner, other, tokenCfg, mockPriceFeed} = await loadFixture(
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

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(
                pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition - 1n,
                    owner.address
                )
            )
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs((v: BigNumber) => {
                    expect(v).to.gt(10000n);
                    expect(v).to.lt(20000n);
                    return true;
                });

            await expect(pool.govUseRiskBufferFund(other.address, 20000n))
                .to.revertedWithCustomError(_liquidityPositionUtil.attach(pool.address), "InsufficientRiskBufferFund")
                .withArgs(() => true, 20000n);
        });

        it("should pass if riskBufferFundDelta is zero", async () => {
            const {pool, USDC, ETH, owner, other, tokenCfg, mockPriceFeed} = await loadFixture(deployFixture);
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

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(
                pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition - 1n,
                    owner.address
                )
            )
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs((v: BigNumber) => {
                    expect(v).to.gt(10000n);
                    return true;
                });

            await pool.govUseRiskBufferFund(other.address, 0n);
        });

        it("should sample and adjust funding rate", async () => {
            const {pool, USDC, ETH, owner, other, tokenCfg, mockPriceFeed, _fundingRateUtil} = await loadFixture(
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

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(
                pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition - 1n,
                    owner.address
                )
            )
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs((v: BigNumber) => {
                    expect(v).to.gt(10000n);
                    return true;
                });

            await time.setNextBlockTimestamp(nextHourBegin + 3600 * 2);
            const assertion = expect(pool.govUseRiskBufferFund(other.address, 10000n));
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should transfer out risk buffer fund delta to receiver", async () => {
            const {pool, USDC, ETH, owner, other, tokenCfg, mockPriceFeed} = await loadFixture(deployFixture);
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

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(
                pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition - 1n,
                    owner.address
                )
            )
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs((v: BigNumber) => {
                    expect(v).to.gt(10000n);
                    return true;
                });

            await expect(pool.govUseRiskBufferFund(other.address, 10000n)).changeTokenBalances(
                USDC,
                [pool.address, other.address],
                [-10000n, 10000n]
            );
            expect(await USDC.balanceOf(other.address)).to.eq(10000n);
        });

        it("should emit GlobalRiskBufferFundChanged event", async () => {
            const {pool, USDC, ETH, owner, other, tokenCfg, mockPriceFeed} = await loadFixture(deployFixture);
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

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(
                pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition - 1n,
                    owner.address
                )
            )
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs((v: BigNumber) => {
                    expect(v).to.gt(10000n);
                    return true;
                });

            const {riskBufferFund} = await pool.globalRiskBufferFund();
            await expect(pool.govUseRiskBufferFund(other.address, 10000n))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(riskBufferFund.sub(10000n));
        });

        it("should emit GlobalRiskBufferFundGovUsed event", async () => {
            const {pool, USDC, ETH, owner, other, tokenCfg, mockPriceFeed} = await loadFixture(deployFixture);
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

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(
                pool.decreasePosition(
                    owner.address,
                    SIDE_LONG,
                    0,
                    tokenCfg.minMarginPerLiquidityPosition - 1n,
                    owner.address
                )
            )
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs((v: BigNumber) => {
                    expect(v).to.gt(10000n);
                    return true;
                });

            await expect(pool.govUseRiskBufferFund(other.address, 10000n))
                .to.emit(pool, "GlobalRiskBufferFundGovUsed")
                .withArgs(other.address, 10000n);
        });
    });

    describe("#increaseRiskBufferFundPosition", () => {
        it("should revert if caller is not router", async () => {
            const {pool, USDC, owner, other} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.connect(other).increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n))
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(owner.address);
        });

        it("should revert if balance not enough", async () => {
            const {pool, USDC, owner} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.increaseRiskBufferFundPosition(owner.address, 101n * 10n ** 6n))
                .to.revertedWithCustomError(pool, "InsufficientBalance")
                .withArgs(0n, 101n * 10n ** 6n);
        });

        it("should sample and adjust funding rate", async () => {
            const {owner, tokenCfg, pool, _fundingRateUtil, USDC} = await loadFixture(deployFixture);

            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(owner.address, tokenCfg.minMarginPerPosition, 1n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                owner.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            const assertion = expect(pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n));
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
            const {pool, USDC, owner} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n))
                .to.emit(pool, "GlobalUnrealizedLossMetricsChanged")
                .withArgs(() => true, 0, 0);

            {
                const {lastZeroLossTime, liquidity} = await pool.globalUnrealizedLossMetrics();
                expect(lastZeroLossTime).to.gt(0n);
                expect(liquidity).to.eq(0n);
            }
        });

        it("should emit RiskBufferFundPositionIncreased event", async () => {
            const {pool, USDC, owner, other} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            const lastTimestamp = await time.latest();
            await expect(pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n))
                .to.emit(pool, "RiskBufferFundPositionIncreased")
                .withArgs(owner.address, 100n * 10n ** 6n, (t: number) => t > lastTimestamp);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n))
                .to.emit(pool, "RiskBufferFundPositionIncreased")
                .withArgs(owner.address, 200n * 10n ** 6n, (t: number) => t > lastTimestamp);

            await USDC.mint(other.address, 100n * 10n ** 6n);
            await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n))
                .to.emit(pool, "RiskBufferFundPositionIncreased")
                .withArgs(other.address, 100n * 10n ** 6n, (t: number) => t > lastTimestamp);
        });

        it("should emit GlobalRiskBufferFundChanged event", async () => {
            const {pool, USDC, owner, other} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(100n * 10n ** 6n);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(200n * 10n ** 6n);

            await USDC.mint(other.address, 100n * 10n ** 6n);
            await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
            await expect(pool.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(300n * 10n ** 6n);
        });

        it("should callback for reward farm", async () => {
            const {pool, USDC, owner, other, mockRewardFarmCallback} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
            expect(await mockRewardFarmCallback.account()).to.eq(owner.address);
            expect(await mockRewardFarmCallback.liquidityAfter()).to.eq(100n * 10n ** 6n);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
            expect(await mockRewardFarmCallback.account()).to.eq(owner.address);
            expect(await mockRewardFarmCallback.liquidityAfter()).to.eq(200n * 10n ** 6n);

            await USDC.mint(other.address, 100n * 10n ** 6n);
            await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n);
            expect(await mockRewardFarmCallback.account()).to.eq(other.address);
            expect(await mockRewardFarmCallback.liquidityAfter()).to.eq(100n * 10n ** 6n);
        });
    });

    describe("#decreaseRiskBufferFundPosition", () => {
        it("should revert if caller is not router", async () => {
            const {pool, USDC, owner, other} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
            await expect(
                pool.connect(other).decreaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n, owner.address)
            )
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(owner.address);
        });

        it("should sample and adjust funding rate", async () => {
            const {owner, tokenCfg, pool, _fundingRateUtil, USDC} = await loadFixture(deployFixture);

            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(owner.address, tokenCfg.minMarginPerPosition, 1n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                owner.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
            await time.setNextBlockTimestamp(nextHourBegin + 3600 + 90 * 24 * 60 * 60);
            const assertion = expect(
                pool.decreaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n, owner.address)
            );
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
            const {pool, USDC, owner} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await expect(pool.decreaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n, owner.address))
                .to.emit(pool, "GlobalUnrealizedLossMetricsChanged")
                .withArgs(() => true, 0, 0);

            {
                const {lastZeroLossTime, liquidity} = await pool.globalUnrealizedLossMetrics();
                expect(lastZeroLossTime).to.gt(0n);
                expect(liquidity).to.eq(0n);
            }
        });

        it("should emit RiskBufferFundPositionDecreased event", async () => {
            const {pool, USDC, owner, other} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);
            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await expect(pool.decreaseRiskBufferFundPosition(owner.address, 30n * 10n ** 6n, other.address))
                .to.emit(pool, "RiskBufferFundPositionDecreased")
                .withArgs(owner.address, 70n * 10n ** 6n, other.address);
        });

        it("should emit GlobalRiskBufferFundChanged event", async () => {
            const {pool, USDC, owner, other} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);

            await USDC.mint(other.address, 100n * 10n ** 6n);
            await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n);

            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await expect(pool.decreaseRiskBufferFundPosition(owner.address, 200n * 10n ** 6n, other.address))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(100n * 10n ** 6n);
            await expect(pool.decreaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n, other.address))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(0n);
        });

        it("should callback for reward farm", async () => {
            const {pool, USDC, owner, other, mockRewardFarmCallback} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);

            await USDC.transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(owner.address, 100n * 10n ** 6n);

            await USDC.mint(other.address, 100n * 10n ** 6n);
            await USDC.connect(other).transfer(pool.address, 100n * 10n ** 6n);
            await pool.increaseRiskBufferFundPosition(other.address, 100n * 10n ** 6n);

            await time.setNextBlockTimestamp((await time.latest()) + 90 * 24 * 60 * 60 + 1);
            await pool.decreaseRiskBufferFundPosition(owner.address, 50n * 10n ** 6n, other.address);
            expect(await mockRewardFarmCallback.account()).to.eq(owner.address);
            expect(await mockRewardFarmCallback.liquidityAfter()).to.eq(150n * 10n ** 6n);

            await pool.decreaseRiskBufferFundPosition(other.address, 50n * 10n ** 6n, other.address);
            expect(await mockRewardFarmCallback.account()).to.eq(other.address);
            expect(await mockRewardFarmCallback.liquidityAfter()).to.eq(50n * 10n ** 6n);
        });
    });

    describe("#increasePosition", () => {
        it("should revert if caller is not router", async () => {
            const {pool, other, owner} = await loadFixture(deployFixture);
            await expect(pool.connect(other).increasePosition(ethers.constants.AddressZero, SIDE_SHORT, 1n, 10n))
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(owner.address);
        });

        it("should revert if position is the first creation and size delta is zero", async () => {
            const {pool} = await loadFixture(deployFixture);
            await expect(pool.increasePosition(ethers.constants.AddressZero, SIDE_SHORT, 1n, 0n))
                .to.revertedWithCustomError(pool, "PositionNotFound")
                .withArgs(ethers.constants.AddressZero, SIDE_SHORT);
        });

        it("should revert if position is the first creation and margin delta too low", async () => {
            const {pool, tokenCfg} = await loadFixture(deployFixture);
            await expect(
                pool.increasePosition(
                    ethers.constants.AddressZero,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition - 1n,
                    100n * 10n ** 6n
                )
            ).to.revertedWithCustomError(pool, "InsufficientMargin");
        });

        it("should revert if balance not enough", async () => {
            const {pool, USDC, tokenCfg} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition - 1n);
            await expect(
                pool.increasePosition(
                    ethers.constants.AddressZero,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    100n * 10n ** 6n
                )
            )
                .to.revertedWithCustomError(pool, "InsufficientBalance")
                .withArgs(0, tokenCfg.minMarginPerLiquidityPosition);
        });

        it("should revert if global liquidity is zero", async () => {
            const {pool, USDC, tokenCfg} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await expect(
                pool.increasePosition(
                    ethers.constants.AddressZero,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    100n * 10n ** 6n
                )
            ).to.revertedWithCustomError(pool, "InsufficientGlobalLiquidity");
        });

        it("should revert if position margin rate is too high", async () => {
            const {owner, pool, ETH, USDC, tokenCfg, tokenFeeRateCfg, mockPriceFeed, positionUtil, priceUtil, efc} =
                await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, Q96 + 1n);
            await mockPriceFeed.setMaxPriceX96(ETH.address, Q96 + 2n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                ethers.constants.AddressZero,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 900000000n;
            const marginDelta = tokenCfg.minMarginPerPosition;
            const side = SIDE_SHORT;
            const account = owner.address;

            const position = await pool.positions(account, side);
            const globalLiquidityPosition = await pool.globalLiquidityPosition();
            await positionUtil.setGlobalLiquidityPosition(
                globalLiquidityPosition.liquidity,
                globalLiquidityPosition.netSize,
                globalLiquidityPosition.entryPriceX96,
                globalLiquidityPosition.side,
                globalLiquidityPosition.realizedProfitGrowthX64
            );

            // _buildTradingFeeState
            const tradingFeeState = await _buildTradingFeeState(efc, tokenFeeRateCfg, account);

            const priceState = await pool.priceState();
            await priceUtil.setPriceState(priceState);
            await priceUtil.setGlobalLiquidityPosition(globalLiquidityPosition);
            const indexPriceX96 = isLongSide(side)
                ? await mockPriceFeed.getMaxPriceX96(ETH.address)
                : await mockPriceFeed.getMinPriceX96(ETH.address);
            await priceUtil.updatePriceState(side, sizeDelta, indexPriceX96, false);
            const tradePriceX96 = await priceUtil.tradePriceX96();
            // _calculateFee
            const tradingFee = await positionUtil.calculateTradingFee(
                sizeDelta,
                tradePriceX96,
                tradingFeeState.tradingFeeRate
            );

            const globalPosition = await pool.globalPosition();
            const globalFundingRateGrowthX96 = isLongSide(side)
                ? globalPosition.longFundingRateGrowthX96
                : globalPosition.shortFundingRateGrowthX96;

            const fundingFee = await positionUtil.calculateFundingFee(
                globalFundingRateGrowthX96,
                position.entryFundingRateGrowthX96,
                position.size
            );
            const marginAfter =
                position.margin.toBigInt() + marginDelta + fundingFee.toBigInt() - tradingFee.toBigInt();
            const decreaseIndexPriceX96 = !isLongSide(side)
                ? await mockPriceFeed.getMaxPriceX96(ETH.address)
                : await mockPriceFeed.getMinPriceX96(ETH.address);
            const entryPriceAfterX96 = await positionUtil.calculateNextEntryPriceX96(
                side,
                position.size,
                position.entryPriceX96,
                sizeDelta,
                tradePriceX96
            );
            const sizeAfter = position.size.add(sizeDelta);
            const unrealizedPnL = await positionUtil.calculateUnrealizedPnL(
                side,
                sizeAfter,
                entryPriceAfterX96,
                decreaseIndexPriceX96
            );
            const maintenanceMargin = await positionUtil.calculateMaintenanceMargin(
                sizeAfter,
                entryPriceAfterX96,
                decreaseIndexPriceX96,
                tokenCfg.liquidationFeeRatePerPosition,
                tokenFeeRateCfg.tradingFeeRate,
                tokenCfg.liquidationExecutionFee
            );
            {
                expect(
                    marginAfter <= 0n ||
                        marginAfter + unrealizedPnL.toBigInt() <= 0 ||
                        maintenanceMargin.toBigInt() >= marginAfter + unrealizedPnL.toBigInt()
                ).to.true;
            }

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(owner.address, SIDE_SHORT, marginDelta, sizeDelta))
                .to.revertedWithCustomError(pool, "MarginRateTooHigh")
                .withArgs(marginAfter, unrealizedPnL, maintenanceMargin);
        });

        async function _simulateIncreasePosition(
            contracts: {
                pool: Pool;
                ETH: ERC20Test;
                mockPriceFeed: MockPriceFeed;
                positionUtil: PositionUtilTest;
                liquidityPositionUtil: LiquidityPositionUtilTest;
                priceUtil: PriceUtilTest;
                efc: MockEFC;
            },
            cfg: {
                tokenCfg: {
                    minMarginPerLiquidityPosition: bigint;
                    maxRiskRatePerLiquidityPosition: bigint;
                    maxLeveragePerLiquidityPosition: bigint;
                    minMarginPerPosition: bigint;
                    maxLeveragePerPosition: bigint;
                    liquidationFeeRatePerPosition: bigint;
                    liquidationExecutionFee: bigint;
                    interestRate: bigint;
                    maxFundingRate: bigint;
                };
                tokenFeeRateCfg: {
                    tradingFeeRate: bigint;
                    liquidityFeeRate: bigint;
                    protocolFeeRate: bigint;
                    referralReturnFeeRate: bigint;
                    referralParentReturnFeeRate: bigint;
                    referralDiscountRate: bigint;
                };
            },
            account: string,
            side: Side,
            marginDelta: bigint,
            sizeDelta: bigint
        ) {
            const position = await contracts.pool.positions(account, side);
            let globalLiquidityPosition = await contracts.pool.globalLiquidityPosition();

            // _buildTradingFeeState
            const tradingFeeState = await _buildTradingFeeState(contracts.efc, cfg.tokenFeeRateCfg, account);

            const globalRiskBufferFund = await contracts.pool.globalRiskBufferFund();
            let marginDeltaAfter = marginDelta;
            let tradePriceX96 = BigNumber.from(0);
            let riskBufferFundAfter = globalRiskBufferFund.riskBufferFund;
            let tradingFee = BigNumber.from(0);
            let protocolFee = BigNumber.from(0);
            let referralFee = BigNumber.from(0);
            let referralParentFee = BigNumber.from(0);
            let realizedProfitGrowthAfterX64 = BigNumber.from(0);
            let globalLiquidityPositionEntryPriceAfterX96 = globalLiquidityPosition.entryPriceX96;
            let globalLiquidityPositionSideAfter = globalLiquidityPosition.side;
            let globalLiquidityPositionNetSizeAfter = globalLiquidityPosition.netSize;
            let globalLiquidityPositionRealizedProfitGrowthAfterX64 = globalLiquidityPosition.realizedProfitGrowthX64;
            let globalLiquidityPositionLiquidationBufferNetSizeAfter = globalLiquidityPosition.liquidationBufferNetSize;
            let priceState = await contracts.pool.priceState();
            let premiumRateAfterX96 = priceState.premiumRateX96;
            await contracts.priceUtil.setPriceState(priceState);
            await contracts.priceUtil.setGlobalLiquidityPosition(globalLiquidityPosition);
            if (sizeDelta > 0n) {
                const indexPriceX96 = isLongSide(side)
                    ? await contracts.mockPriceFeed.getMaxPriceX96(contracts.ETH.address)
                    : await contracts.mockPriceFeed.getMinPriceX96(contracts.ETH.address);
                await contracts.priceUtil.updatePriceState(side, sizeDelta, indexPriceX96, false);
                tradePriceX96 = await contracts.priceUtil.tradePriceX96();
                const riskBufferFundDelta = 0n;
                const adjustGlobalLiquidityPositionRes = await _adjustGlobalLiquidityPosition(
                    contracts,
                    cfg.tokenFeeRateCfg,
                    globalRiskBufferFund,
                    globalLiquidityPosition,
                    tradingFeeState,
                    side,
                    tradePriceX96,
                    sizeDelta,
                    riskBufferFundDelta
                );
                globalLiquidityPositionEntryPriceAfterX96 = adjustGlobalLiquidityPositionRes.entryPriceAfterX96;
                tradingFee = adjustGlobalLiquidityPositionRes.tradingFee;
                protocolFee = adjustGlobalLiquidityPositionRes.protocolFee;
                referralFee = adjustGlobalLiquidityPositionRes.referralFee;
                referralParentFee = adjustGlobalLiquidityPositionRes.referralParentFee;
                riskBufferFundAfter = adjustGlobalLiquidityPositionRes.riskBufferFundAfter;
                realizedProfitGrowthAfterX64 = adjustGlobalLiquidityPositionRes.realizedProfitGrowthAfterX64;

                const globalLiquidityPositionAfter = await contracts.priceUtil.globalLiquidityPosition();
                globalLiquidityPositionSideAfter = globalLiquidityPositionAfter.side;
                globalLiquidityPositionRealizedProfitGrowthAfterX64 =
                    globalLiquidityPositionAfter.realizedProfitGrowthX64;
                globalLiquidityPositionLiquidationBufferNetSizeAfter =
                    globalLiquidityPositionAfter.liquidationBufferNetSize;
                globalLiquidityPositionNetSizeAfter = globalLiquidityPositionAfter.netSize;
                premiumRateAfterX96 = (await contracts.priceUtil.priceState()).premiumRateX96;
            }

            const globalPosition = await contracts.pool.globalPosition();
            const globalFundingRateGrowthX96 = isLongSide(side)
                ? globalPosition.longFundingRateGrowthX96
                : globalPosition.shortFundingRateGrowthX96;

            const fundingFee = await contracts.positionUtil.calculateFundingFee(
                globalFundingRateGrowthX96,
                position.entryFundingRateGrowthX96,
                position.size
            );
            let marginAfter = position.margin.toBigInt() + marginDelta + fundingFee.toBigInt() - tradingFee.toBigInt();
            const decreaseIndexPriceX96 = !isLongSide(side)
                ? await contracts.mockPriceFeed.getMaxPriceX96(contracts.ETH.address)
                : await contracts.mockPriceFeed.getMinPriceX96(contracts.ETH.address);
            const entryPriceAfterX96 = await contracts.positionUtil.calculateNextEntryPriceX96(
                side,
                position.size,
                position.entryPriceX96,
                sizeDelta,
                tradePriceX96
            );
            let sizeAfter = position.size.add(sizeDelta);
            const unrealizedPnL = await contracts.positionUtil.calculateUnrealizedPnL(
                side,
                sizeAfter,
                entryPriceAfterX96,
                decreaseIndexPriceX96
            );
            const maintenanceMargin = await contracts.positionUtil.calculateMaintenanceMargin(
                sizeAfter,
                entryPriceAfterX96,
                decreaseIndexPriceX96,
                cfg.tokenCfg.liquidationFeeRatePerPosition,
                tradingFeeState.tradingFeeRate,
                cfg.tokenCfg.liquidationExecutionFee
            );
            if (sizeDelta > 0n) {
                {
                    expect(marginAfter).to.gt(0n);
                    expect(marginAfter + unrealizedPnL.toBigInt()).to.gt(0n);
                    expect(maintenanceMargin).to.lt(marginAfter + unrealizedPnL.toBigInt());
                }
                expect(marginAfter * BigInt(cfg.tokenCfg.maxLeveragePerPosition)).to.gte(
                    await contracts.positionUtil.calculateLiquidity(sizeAfter, entryPriceAfterX96)
                );
            }

            return {
                marginDeltaAfter,
                marginAfter,
                sizeAfter,
                tradePriceX96,
                entryPriceAfterX96,
                fundingFee,
                tradingFee,
                protocolFee,
                referralFee,
                referralParentFee,
                referralToken: tradingFeeState.referralToken,
                referralParentToken: tradingFeeState.referralParentToken,
                globalLiquidityPositionEntryPriceAfterX96,
                globalLiquidityPositionSideAfter,
                globalLiquidityPositionNetSizeAfter,
                globalLiquidityPositionRealizedProfitGrowthAfterX64,
                globalLiquidityPositionLiquidationBufferNetSizeAfter,
                riskBufferFundAfter,
                realizedProfitGrowthAfterX64,
                premiumRateAfterX96,
            };
        }

        it("should sample and adjust funding rate", async () => {
            const {pool, USDC, tokenCfg, ETH, mockPriceFeed, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                ethers.constants.AddressZero,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600n;
            const marginDelta = tokenCfg.minMarginPerPosition;
            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await USDC.transfer(pool.address, marginDelta);
            const assertion = expect(
                pool.increasePosition(ethers.constants.AddressZero, SIDE_SHORT, marginDelta, sizeDelta)
            );
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
            const {pool, USDC, tokenCfg, ETH, mockPriceFeed} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                ethers.constants.AddressZero,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600n;
            const marginDelta = tokenCfg.minMarginPerPosition;

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(ethers.constants.AddressZero, SIDE_SHORT, marginDelta, sizeDelta))
                .to.emit(pool, "GlobalUnrealizedLossMetricsChanged")
                .withArgs(() => true, 0n, 0n);

            {
                const {lastZeroLossTime, liquidity, liquidityTimesUnrealizedLoss} =
                    await pool.globalUnrealizedLossMetrics();
                expect(lastZeroLossTime).to.gt(0n);
                expect(liquidity).to.eq(0n);
                expect(liquidityTimesUnrealizedLoss).to.eq(0n);
            }
        });

        it("should emit PremiumRateChanged event", async () => {
            const {
                owner,
                pool,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                ETH,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                _priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1808", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1809", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition;
            const side = SIDE_SHORT;
            const account = owner.address;
            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(account, SIDE_SHORT, marginDelta, sizeDelta))
                .to.emit(_priceUtil.attach(pool.address), "PremiumRateChanged")
                .withArgs(res.premiumRateAfterX96);
        });

        it("should emit GlobalLiquidityPositionNetPositionAdjusted event", async () => {
            const {
                owner,
                pool,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                ETH,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1808", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1809", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition;
            const side = SIDE_SHORT;
            const account = owner.address;
            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(account, SIDE_SHORT, marginDelta, sizeDelta))
                .to.emit(pool, "GlobalLiquidityPositionNetPositionAdjusted")
                .withArgs(
                    res.globalLiquidityPositionNetSizeAfter,
                    res.globalLiquidityPositionLiquidationBufferNetSizeAfter,
                    res.globalLiquidityPositionEntryPriceAfterX96,
                    res.globalLiquidityPositionSideAfter
                );
        });

        it("should emit GlobalRiskBufferFundChanged event", async () => {
            const {
                owner,
                pool,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                ETH,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1808", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1809", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition;
            const side = SIDE_SHORT;
            const account = owner.address;
            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(account, SIDE_SHORT, marginDelta, sizeDelta))
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs(res.riskBufferFundAfter);
        });

        it("should emit GlobalLiquidityPositionRealizedProfitGrowthChanged event", async () => {
            const {
                owner,
                pool,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                ETH,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1808", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1809", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition;
            const side = SIDE_SHORT;
            const account = owner.address;
            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(account, SIDE_SHORT, marginDelta, sizeDelta))
                .to.emit(pool, "GlobalLiquidityPositionRealizedProfitGrowthChanged")
                .withArgs(res.realizedProfitGrowthAfterX64);
        });

        it("should emit ProtocolFeeIncreased event", async () => {
            const {
                owner,
                pool,
                ETH,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600000n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition * 1000n;
            const side = SIDE_SHORT;
            const account = owner.address;

            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );
            expect(res.protocolFee).to.gt(1n);

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(account, side, marginDelta, sizeDelta))
                .to.emit(pool, "ProtocolFeeIncreased")
                .withArgs(res.protocolFee);
        });

        it("should emit ReferralFeeIncreased event if user has a referral token", async () => {
            const {
                owner,
                pool,
                ETH,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600000n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition * 1000n;
            const side = SIDE_SHORT;
            const account = owner.address;

            await efc.setRefereeTokens(account, 10000);

            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );
            expect(res.protocolFee).to.gt(1n);
            expect(res.referralFee).to.gt(0n);
            expect(res.referralParentFee).to.gt(0n);

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(account, side, marginDelta, sizeDelta))
                .to.emit(pool, "ReferralFeeIncreased")
                .withArgs(account, res.referralToken, res.referralFee, res.referralParentToken, res.referralParentFee);
            expect(await pool.referralFees(res.referralToken)).to.eq(res.referralFee);
            expect(await pool.referralFees(res.referralParentToken)).to.eq(res.referralParentFee);
        });

        it("should emit PositionIncreased event", async () => {
            const {
                owner,
                pool,
                ETH,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600000n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition * 1000n;
            const side = SIDE_SHORT;
            const account = owner.address;

            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );
            expect(res.tradingFee).to.gt(1n);

            await USDC.transfer(pool.address, marginDelta);
            await expect(pool.increasePosition(account, side, marginDelta, sizeDelta))
                .to.emit(pool, "PositionIncreased")
                .withArgs(
                    account,
                    SIDE_SHORT,
                    res.marginDeltaAfter,
                    res.marginAfter,
                    res.sizeAfter,
                    res.tradePriceX96,
                    res.entryPriceAfterX96,
                    res.fundingFee,
                    res.tradingFee
                );

            {
                const {margin, size, entryPriceX96, entryFundingRateGrowthX96} = await pool.positions(
                    owner.address,
                    SIDE_SHORT
                );
                expect(margin).to.eq(res.marginAfter);
                expect(size).to.eq(res.sizeAfter);
                expect(entryPriceX96).to.eq(res.entryPriceAfterX96);
                expect(entryFundingRateGrowthX96).to.eq(0n);
            }

            {
                const {side, netSize, entryPriceX96, realizedProfitGrowthX64, liquidationBufferNetSize} =
                    await pool.globalLiquidityPosition();
                expect(side).eq(res.globalLiquidityPositionSideAfter);
                expect(netSize).eq(res.globalLiquidityPositionNetSizeAfter);
                expect(entryPriceX96).eq(res.globalLiquidityPositionEntryPriceAfterX96);
                expect(realizedProfitGrowthX64).to.eq(res.realizedProfitGrowthAfterX64);
                expect(liquidationBufferNetSize).eq(res.globalLiquidityPositionLiquidationBufferNetSizeAfter);
            }

            {
                const {riskBufferFund} = await pool.globalRiskBufferFund();
                expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
            }

            {
                const {longSize, shortSize, longFundingRateGrowthX96, shortFundingRateGrowthX96} =
                    await pool.globalPosition();
                expect(longSize).to.eq(0);
                expect(shortSize).to.eq(sizeDelta);
                expect(longFundingRateGrowthX96).to.eq(0);
                expect(shortFundingRateGrowthX96).to.eq(0);
            }

            {
                const {premiumRateX96} = await pool.priceState();
                expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
            }
        });

        it("should callback for reward farm", async () => {
            const {
                owner,
                pool,
                USDC,
                tokenCfg,
                tokenFeeRateCfg,
                ETH,
                mockPriceFeed,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
                mockRewardFarmCallback,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1808", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1809", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = 600n * 10n ** 12n;
            const marginDelta = tokenCfg.minMarginPerPosition;
            const side = SIDE_SHORT;
            const account = owner.address;
            const res = await _simulateIncreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );

            await USDC.transfer(pool.address, marginDelta);
            await pool.increasePosition(account, SIDE_SHORT, marginDelta, sizeDelta);

            expect(await mockRewardFarmCallback.account()).to.eq(account);
            expect(await mockRewardFarmCallback.side()).to.eq(side);
            expect(await mockRewardFarmCallback.sizeAfter()).to.eq(res.sizeAfter);
            expect(await mockRewardFarmCallback.entryPriceAfterX96()).to.eq(res.entryPriceAfterX96);
        });

        describe("not the first creation", () => {
            it("should pass if only increase margin", async () => {
                const {
                    owner,
                    pool,
                    ETH,
                    USDC,
                    tokenCfg,
                    tokenFeeRateCfg,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    owner.address,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    600n * 10n ** 12n
                );

                const sizeDelta = 0n;
                const marginDelta = tokenCfg.minMarginPerPosition;
                const side = SIDE_SHORT;
                const account = owner.address;

                const res = await _simulateIncreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                await USDC.transfer(pool.address, marginDelta);
                await expect(pool.increasePosition(account, side, marginDelta, sizeDelta))
                    .to.emit(pool, "PositionIncreased")
                    .withArgs(
                        account,
                        SIDE_SHORT,
                        res.marginDeltaAfter,
                        res.marginAfter,
                        res.sizeAfter,
                        res.tradePriceX96,
                        res.entryPriceAfterX96,
                        res.fundingFee,
                        res.tradingFee
                    );

                {
                    const {margin, size, entryPriceX96, entryFundingRateGrowthX96} = await pool.positions(
                        owner.address,
                        SIDE_SHORT
                    );
                    expect(margin).to.eq(res.marginAfter);
                    expect(size).to.eq(res.sizeAfter);
                    expect(entryPriceX96).to.eq(res.entryPriceAfterX96);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    const {side, netSize, entryPriceX96, realizedProfitGrowthX64, liquidationBufferNetSize} =
                        await pool.globalLiquidityPosition();
                    expect(side).eq(res.globalLiquidityPositionSideAfter);
                    expect(netSize).eq(res.globalLiquidityPositionNetSizeAfter);
                    expect(entryPriceX96).eq(res.globalLiquidityPositionEntryPriceAfterX96);
                    expect(realizedProfitGrowthX64).to.eq(res.realizedProfitGrowthAfterX64);
                    expect(liquidationBufferNetSize).eq(res.globalLiquidityPositionLiquidationBufferNetSizeAfter);
                }

                {
                    const {riskBufferFund} = await pool.globalRiskBufferFund();
                    expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
                }

                {
                    const {longSize, shortSize, longFundingRateGrowthX96, shortFundingRateGrowthX96} =
                        await pool.globalPosition();
                    expect(longSize).to.eq(0);
                    expect(shortSize).to.eq(600n * 10n ** 12n);
                    expect(longFundingRateGrowthX96).to.eq(0);
                    expect(shortFundingRateGrowthX96).to.eq(0);
                }

                {
                    const {premiumRateX96} = await pool.priceState();
                    expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
                }
            });

            it("should pass if only increase size", async () => {
                const {
                    owner,
                    pool,
                    ETH,
                    USDC,
                    tokenCfg,
                    tokenFeeRateCfg,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    owner.address,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    600n * 10n ** 12n
                );

                const sizeDelta = 100n * 10n ** 12n;
                const marginDelta = 0n;
                const side = SIDE_SHORT;
                const account = owner.address;

                const res = await _simulateIncreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                await USDC.transfer(pool.address, marginDelta);
                await expect(pool.increasePosition(account, side, marginDelta, sizeDelta))
                    .to.emit(pool, "PositionIncreased")
                    .withArgs(
                        account,
                        SIDE_SHORT,
                        res.marginDeltaAfter,
                        res.marginAfter,
                        res.sizeAfter,
                        res.tradePriceX96,
                        res.entryPriceAfterX96,
                        res.fundingFee,
                        res.tradingFee
                    );

                {
                    const {margin, size, entryPriceX96, entryFundingRateGrowthX96} = await pool.positions(
                        owner.address,
                        SIDE_SHORT
                    );
                    expect(margin).to.eq(res.marginAfter);
                    expect(size).to.eq(res.sizeAfter);
                    expect(entryPriceX96).to.eq(res.entryPriceAfterX96);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    const {side, netSize, entryPriceX96, realizedProfitGrowthX64, liquidationBufferNetSize} =
                        await pool.globalLiquidityPosition();
                    expect(side).eq(res.globalLiquidityPositionSideAfter);
                    expect(netSize).eq(res.globalLiquidityPositionNetSizeAfter);
                    expect(entryPriceX96).eq(res.globalLiquidityPositionEntryPriceAfterX96);
                    expect(realizedProfitGrowthX64).to.eq(res.realizedProfitGrowthAfterX64);
                    expect(liquidationBufferNetSize).eq(res.globalLiquidityPositionLiquidationBufferNetSizeAfter);
                }

                {
                    const {riskBufferFund} = await pool.globalRiskBufferFund();
                    expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
                }

                {
                    const {longSize, shortSize, longFundingRateGrowthX96, shortFundingRateGrowthX96} =
                        await pool.globalPosition();
                    expect(longSize).to.eq(0);
                    expect(shortSize).to.eq(600n * 10n ** 12n + sizeDelta);
                    expect(longFundingRateGrowthX96).to.eq(0);
                    expect(shortFundingRateGrowthX96).to.eq(0);
                }

                {
                    const {premiumRateX96} = await pool.priceState();
                    expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
                }
            });

            it("should pass if increase margin and size", async () => {
                const {
                    owner,
                    pool,
                    ETH,
                    USDC,
                    tokenCfg,
                    tokenFeeRateCfg,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    owner.address,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    600n * 10n ** 12n
                );

                const sizeDelta = 100n * 10n ** 12n;
                const marginDelta = tokenCfg.minMarginPerPosition;
                const side = SIDE_SHORT;
                const account = owner.address;

                const res = await _simulateIncreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                await USDC.transfer(pool.address, marginDelta);
                await expect(pool.increasePosition(account, side, marginDelta, sizeDelta))
                    .to.emit(pool, "PositionIncreased")
                    .withArgs(
                        account,
                        SIDE_SHORT,
                        res.marginDeltaAfter,
                        res.marginAfter,
                        res.sizeAfter,
                        res.tradePriceX96,
                        res.entryPriceAfterX96,
                        res.fundingFee,
                        res.tradingFee
                    );

                {
                    const {margin, size, entryPriceX96, entryFundingRateGrowthX96} = await pool.positions(
                        owner.address,
                        SIDE_SHORT
                    );
                    expect(margin).to.eq(res.marginAfter);
                    expect(size).to.eq(res.sizeAfter);
                    expect(entryPriceX96).to.eq(res.entryPriceAfterX96);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    const {side, netSize, entryPriceX96, realizedProfitGrowthX64, liquidationBufferNetSize} =
                        await pool.globalLiquidityPosition();
                    expect(side).eq(res.globalLiquidityPositionSideAfter);
                    expect(netSize).eq(res.globalLiquidityPositionNetSizeAfter);
                    expect(entryPriceX96).eq(res.globalLiquidityPositionEntryPriceAfterX96);
                    expect(realizedProfitGrowthX64).to.eq(res.realizedProfitGrowthAfterX64);
                    expect(liquidationBufferNetSize).eq(res.globalLiquidityPositionLiquidationBufferNetSizeAfter);
                }

                {
                    const {riskBufferFund} = await pool.globalRiskBufferFund();
                    expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
                }

                {
                    const {longSize, shortSize, longFundingRateGrowthX96, shortFundingRateGrowthX96} =
                        await pool.globalPosition();
                    expect(longSize).to.eq(0);
                    expect(shortSize).to.eq(600n * 10n ** 12n + sizeDelta);
                    expect(longFundingRateGrowthX96).to.eq(0);
                    expect(shortFundingRateGrowthX96).to.eq(0);
                }

                {
                    const {premiumRateX96} = await pool.priceState();
                    expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
                }
            });
        });
    });

    describe("#decreasePosition", function () {
        it("should revert if caller is not router", async () => {
            const {pool, other, owner} = await loadFixture(deployFixture);
            await expect(
                pool
                    .connect(other)
                    .decreasePosition(ethers.constants.AddressZero, SIDE_SHORT, 0n, 100n, ethers.constants.AddressZero)
            )
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(owner.address);
        });

        it("should revert if position is not opened", async () => {
            const {pool} = await loadFixture(deployFixture);
            await expect(
                pool.decreasePosition(ethers.constants.AddressZero, SIDE_SHORT, 0n, 100n, ethers.constants.AddressZero)
            )
                .to.revertedWithCustomError(pool, "PositionNotFound")
                .withArgs(ethers.constants.AddressZero, SIDE_SHORT);
        });

        it("should revert if size delta is too large", async () => {
            const {owner, pool, USDC, ETH, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1.1", DECIMALS_18, DECIMALS_6));
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                ethers.constants.AddressZero,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const sizeDelta = toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n;
            const marginDelta = tokenCfg.minMarginPerPosition;

            await USDC.transfer(pool.address, marginDelta);
            await pool.increasePosition(owner.address, SIDE_SHORT, marginDelta, sizeDelta);

            await expect(pool.decreasePosition(owner.address, SIDE_SHORT, 1n, sizeDelta + 1n, owner.address))
                .to.revertedWithCustomError(pool, "InsufficientSizeToDecrease")
                .withArgs(sizeDelta, sizeDelta + 1n);
        });

        async function _simulateDecreasePosition(
            contracts: {
                pool: Pool;
                ETH: ERC20Test;
                mockPriceFeed: MockPriceFeed;
                positionUtil: PositionUtilTest;
                liquidityPositionUtil: LiquidityPositionUtilTest;
                priceUtil: PriceUtilTest;
                efc: MockEFC;
            },
            cfg: {
                tokenCfg: {
                    minMarginPerLiquidityPosition: bigint;
                    maxRiskRatePerLiquidityPosition: bigint;
                    maxLeveragePerLiquidityPosition: bigint;
                    minMarginPerPosition: bigint;
                    maxLeveragePerPosition: bigint;
                    liquidationFeeRatePerPosition: bigint;
                    liquidationExecutionFee: bigint;
                    interestRate: bigint;
                    maxFundingRate: bigint;
                };
                tokenFeeRateCfg: {
                    tradingFeeRate: bigint;
                    liquidityFeeRate: bigint;
                    protocolFeeRate: bigint;
                    referralReturnFeeRate: bigint;
                    referralParentReturnFeeRate: bigint;
                    referralDiscountRate: bigint;
                };
            },
            account: string,
            side: Side,
            marginDelta: bigint,
            sizeDelta: bigint
        ) {
            const position = await contracts.pool.positions(account, side);
            const globalPosition = await contracts.pool.globalPosition();
            const globalLiquidityPosition = await contracts.pool.globalLiquidityPosition();
            await contracts.positionUtil.setGlobalLiquidityPosition(
                globalLiquidityPosition.liquidity,
                globalLiquidityPosition.netSize,
                globalLiquidityPosition.entryPriceX96,
                globalLiquidityPosition.side,
                globalLiquidityPosition.realizedProfitGrowthX64
            );
            const decreaseIndexPriceX96 = !isLongSide(side)
                ? await contracts.mockPriceFeed.getMaxPriceX96(contracts.ETH.address)
                : await contracts.mockPriceFeed.getMinPriceX96(contracts.ETH.address);

            // _buildTradingFeeState
            const tradingFeeState = await _buildTradingFeeState(contracts.efc, cfg.tokenFeeRateCfg, account);

            const globalRiskBufferFund = await contracts.pool.globalRiskBufferFund();
            let marginDeltaAfter = marginDelta;
            let tradePriceX96 = BigNumber.from(0);
            let sizeAfter = position.size;
            let riskBufferFundAfter = globalRiskBufferFund.riskBufferFund;
            let tradingFee = BigNumber.from(0);
            let protocolFee = BigNumber.from(0);
            let referralFee = BigNumber.from(0);
            let referralParentFee = BigNumber.from(0);
            let realizedPnLDelta = BigNumber.from(0);
            let entryPriceX96 = position.entryPriceX96;
            let realizedProfitGrowthAfterX64 = BigNumber.from(0);
            let sideAfter = globalLiquidityPosition.side;
            let netSizeAfter = globalLiquidityPosition.netSize;
            let entryPriceAfterX96 = globalLiquidityPosition.entryPriceX96;
            let liquidationBufferNetSizeAfter = globalLiquidityPosition.liquidationBufferNetSize;
            const priceState = await contracts.pool.priceState();
            let premiumRateAfterX96 = priceState.premiumRateX96;
            await contracts.priceUtil.setPriceState(priceState);
            await contracts.priceUtil.setGlobalLiquidityPosition(globalLiquidityPosition);
            if (sizeDelta > 0) {
                sizeAfter = position.size.sub(sizeDelta);
                await contracts.priceUtil.updatePriceState(flipSide(side), sizeDelta, decreaseIndexPriceX96, false);
                tradePriceX96 = await contracts.priceUtil.tradePriceX96();

                // _adjustGlobalLiquidityPosition
                const riskBufferFundDelta = 0n;
                const adjustGlobalLiquidityPositionRes = await _adjustGlobalLiquidityPosition(
                    contracts,
                    cfg.tokenFeeRateCfg,
                    globalRiskBufferFund,
                    globalLiquidityPosition,
                    tradingFeeState,
                    flipSide(side),
                    tradePriceX96,
                    sizeDelta,
                    riskBufferFundDelta
                );
                entryPriceAfterX96 = adjustGlobalLiquidityPositionRes.entryPriceAfterX96;
                tradingFee = adjustGlobalLiquidityPositionRes.tradingFee;
                protocolFee = adjustGlobalLiquidityPositionRes.protocolFee;
                referralFee = adjustGlobalLiquidityPositionRes.referralFee;
                referralParentFee = adjustGlobalLiquidityPositionRes.referralParentFee;
                riskBufferFundAfter = adjustGlobalLiquidityPositionRes.riskBufferFundAfter;
                realizedProfitGrowthAfterX64 = adjustGlobalLiquidityPositionRes.realizedProfitGrowthAfterX64;
                premiumRateAfterX96 = (await contracts.priceUtil.priceState()).premiumRateX96;
                const globalLiquidityPositionAfter = await contracts.priceUtil.globalLiquidityPosition();
                sideAfter = globalLiquidityPositionAfter.side;
                netSizeAfter = globalLiquidityPositionAfter.netSize;
                liquidationBufferNetSizeAfter = globalLiquidityPosition.liquidationBufferNetSize;

                realizedPnLDelta = await contracts.positionUtil.calculateUnrealizedPnL(
                    side,
                    sizeDelta,
                    entryPriceX96,
                    tradePriceX96
                );
            }

            const globalFundingRateGrowthX96 = isLongSide(side)
                ? globalPosition.longFundingRateGrowthX96
                : globalPosition.shortFundingRateGrowthX96;
            const fundingFee = await contracts.positionUtil.calculateFundingFee(
                globalFundingRateGrowthX96,
                position.entryFundingRateGrowthX96,
                position.size
            );
            let marginAfter = position.margin.add(realizedPnLDelta).add(fundingFee).sub(tradingFee.add(marginDelta));
            expect(marginAfter).to.gte(0n);
            if (sizeAfter.gt(0n)) {
                const unrealizedPnL = await contracts.positionUtil.calculateUnrealizedPnL(
                    side,
                    sizeDelta,
                    entryPriceX96,
                    decreaseIndexPriceX96
                );
                const maintenanceMargin = await contracts.positionUtil.calculateMaintenanceMargin(
                    sizeAfter,
                    entryPriceX96,
                    decreaseIndexPriceX96,
                    cfg.tokenCfg.liquidationFeeRatePerPosition,
                    tradingFeeState.tradingFeeRate,
                    cfg.tokenCfg.liquidationExecutionFee
                );
                {
                    expect(marginAfter).to.gt(0n);
                    expect(marginAfter.add(unrealizedPnL)).to.gt(0n);
                    expect(maintenanceMargin).to.lt(marginAfter.add(unrealizedPnL));
                }
                if (marginDelta > 0n) {
                    expect(marginAfter.mul(cfg.tokenCfg.maxLeveragePerPosition)).to.gte(
                        await contracts.positionUtil.calculateLiquidity(sizeAfter, entryPriceX96)
                    );
                }
            } else {
                marginDeltaAfter += marginAfter.toBigInt();
                marginAfter = BigNumber.from(0);
            }

            return {
                marginDeltaAfter,
                marginAfter,
                sizeAfter,
                tradePriceX96,
                realizedPnLDelta,
                fundingFee,
                tradingFee,
                protocolFee,
                referralFee,
                referralParentFee,
                referralToken: tradingFeeState.referralToken,
                referralParentToken: tradingFeeState.referralParentToken,
                sideAfter,
                netSizeAfter,
                entryPriceAfterX96,
                liquidationBufferNetSizeAfter,
                riskBufferFundAfter,
                realizedProfitGrowthAfterX64,
                premiumRateAfterX96,
            };
        }

        describe("only decrease margin", () => {
            it("should revert if margin after is negative", async () => {
                const {owner, pool, USDC, ETH, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1.1", DECIMALS_18, DECIMALS_6));
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                const _sizeDelta = toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n;
                const _marginDelta = tokenCfg.minMarginPerPosition;

                await USDC.transfer(pool.address, _marginDelta);
                await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

                await expect(
                    pool.decreasePosition(owner.address, SIDE_SHORT, _marginDelta, 0n, owner.address)
                ).to.revertedWithCustomError(pool, "InsufficientMargin");
            });

            it("should pass", async () => {
                const {
                    owner,
                    pool,
                    USDC,
                    ETH,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                const _sizeDelta = 600n * 10n ** 12n;
                const _marginDelta = tokenCfg.minMarginPerPosition * 2n;

                await USDC.transfer(pool.address, _marginDelta);
                await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

                const account = owner.address;
                const sizeDelta = 0n;
                let marginDelta = _marginDelta / 2n;
                const side = SIDE_SHORT;
                const res = await _simulateDecreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                const assertion = expect(pool.decreasePosition(account, side, marginDelta, sizeDelta, account));
                await assertion.to
                    .emit(pool, "PositionDecreased")
                    .withArgs(
                        account,
                        side,
                        res.marginDeltaAfter,
                        res.marginAfter,
                        res.sizeAfter,
                        res.tradePriceX96,
                        res.realizedPnLDelta,
                        res.fundingFee,
                        res.tradingFee,
                        account
                    );
                await assertion.changeTokenBalances(
                    USDC,
                    [pool.address, account],
                    [-res.marginDeltaAfter, res.marginDeltaAfter]
                );

                {
                    const {longSize, shortSize} = await pool.globalPosition();
                    if (isLongSide(side)) {
                        expect(longSize).to.eq(res.sizeAfter);
                        expect(shortSize).to.eq(0n);
                    } else {
                        expect(longSize).to.eq(0n);
                        expect(shortSize).to.eq(res.sizeAfter);
                    }
                }

                {
                    const {
                        margin: _marginAfter,
                        size: _sizeAfter,
                        entryPriceX96: _entryPriceAfterX96,
                        entryFundingRateGrowthX96,
                    } = await pool.positions(account, side);
                    expect(_marginAfter).to.eq(res.marginAfter);
                    expect(_sizeAfter).to.eq(res.sizeAfter);
                    expect(_entryPriceAfterX96).to.eq(res.entryPriceAfterX96);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    const {premiumRateX96} = await pool.priceState();
                    expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
                }
            });
        });

        describe("only decrease size", () => {
            it("should delete position if size delta is same as position size", async () => {
                const {
                    owner,
                    pool,
                    USDC,
                    ETH,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    _priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                const _sizeDelta = 100n * 10n ** 12n;
                const _marginDelta = tokenCfg.minMarginPerPosition;

                await USDC.transfer(pool.address, _marginDelta);
                await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

                const account = owner.address;
                const sizeDelta = _sizeDelta;
                let marginDelta = 0n;
                const side = SIDE_SHORT;
                const res = await _simulateDecreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                {
                    const assertion = expect(pool.decreasePosition(account, side, marginDelta, sizeDelta, account));
                    await assertion.to
                        .emit(_priceUtil.attach(pool.address), "PremiumRateChanged")
                        .withArgs(res.premiumRateAfterX96);
                    await assertion.to
                        .emit(pool, "GlobalLiquidityPositionNetPositionAdjusted")
                        .withArgs(
                            res.netSizeAfter,
                            res.liquidationBufferNetSizeAfter,
                            res.entryPriceAfterX96,
                            res.sideAfter
                        );
                    await assertion.to.emit(pool, "ProtocolFeeIncreased").withArgs(res.protocolFee);
                    await assertion.to.emit(pool, "GlobalRiskBufferFundChanged").withArgs(res.riskBufferFundAfter);
                    await assertion.to
                        .emit(pool, "GlobalLiquidityPositionRealizedProfitGrowthChanged")
                        .withArgs(res.realizedProfitGrowthAfterX64);
                    await assertion.to
                        .emit(pool, "PositionDecreased")
                        .withArgs(
                            account,
                            side,
                            res.marginDeltaAfter,
                            res.marginAfter,
                            res.sizeAfter,
                            res.tradePriceX96,
                            res.realizedPnLDelta,
                            res.fundingFee,
                            res.tradingFee,
                            account
                        );
                    await assertion.changeTokenBalances(
                        USDC,
                        [pool.address, account],
                        [-res.marginDeltaAfter, res.marginDeltaAfter]
                    );
                }

                {
                    const {longSize, shortSize} = await pool.globalPosition();
                    if (isLongSide(side)) {
                        expect(longSize).to.eq(res.sizeAfter);
                        expect(shortSize).to.eq(0n);
                    } else {
                        expect(longSize).to.eq(0n);
                        expect(shortSize).to.eq(res.sizeAfter);
                    }
                }

                {
                    const {
                        margin: _marginAfter,
                        size: _sizeAfter,
                        entryPriceX96: _entryPriceAfterX96,
                        entryFundingRateGrowthX96,
                    } = await pool.positions(account, side);
                    expect(_marginAfter).to.eq(0n);
                    expect(_sizeAfter).to.eq(0n);
                    expect(_entryPriceAfterX96).to.eq(0n);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    const {premiumRateX96} = await pool.priceState();
                    expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
                }
            });

            it("should pass if size delta is less than position size", async () => {
                const {
                    owner,
                    pool,
                    USDC,
                    ETH,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    _priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                const _sizeDelta = 100n * 10n ** 12n;
                const _marginDelta = tokenCfg.minMarginPerPosition;

                await USDC.transfer(pool.address, _marginDelta);
                await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

                const account = owner.address;
                const sizeDelta = _sizeDelta / 2n;
                let marginDelta = 0n;
                const side = SIDE_SHORT;
                const res = await _simulateDecreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                {
                    const assertion = expect(pool.decreasePosition(account, side, marginDelta, sizeDelta, account));
                    if (sizeDelta > 0n) {
                        await assertion.to
                            .emit(_priceUtil.attach(pool.address), "PremiumRateChanged")
                            .withArgs(res.premiumRateAfterX96);
                        await assertion.to
                            .emit(pool, "GlobalLiquidityPositionNetPositionAdjusted")
                            .withArgs(
                                res.netSizeAfter,
                                res.liquidationBufferNetSizeAfter,
                                res.entryPriceAfterX96,
                                res.sideAfter
                            );
                        await assertion.to.emit(pool, "GlobalRiskBufferFundChanged").withArgs(res.riskBufferFundAfter);
                        await assertion.to
                            .emit(pool, "GlobalLiquidityPositionRealizedProfitGrowthChanged")
                            .withArgs(res.realizedProfitGrowthAfterX64);
                    }
                    await assertion.to
                        .emit(pool, "PositionDecreased")
                        .withArgs(
                            account,
                            side,
                            res.marginDeltaAfter,
                            res.marginAfter,
                            res.sizeAfter,
                            res.tradePriceX96,
                            res.realizedPnLDelta,
                            res.fundingFee,
                            res.tradingFee,
                            account
                        );
                    await assertion.changeTokenBalances(
                        USDC,
                        [pool.address, account],
                        [-res.marginDeltaAfter, res.marginDeltaAfter]
                    );
                }

                {
                    const {longSize, shortSize} = await pool.globalPosition();
                    if (isLongSide(side)) {
                        expect(longSize).to.eq(res.sizeAfter);
                        expect(shortSize).to.eq(0n);
                    } else {
                        expect(longSize).to.eq(0n);
                        expect(shortSize).to.eq(res.sizeAfter);
                    }
                }

                {
                    const {
                        margin: _marginAfter,
                        size: _sizeAfter,
                        entryPriceX96: _entryPriceAfterX96,
                        entryFundingRateGrowthX96,
                    } = await pool.positions(account, side);
                    expect(_marginAfter).to.eq(res.marginAfter);
                    expect(_sizeAfter).to.eq(res.sizeAfter);
                    expect(_entryPriceAfterX96).to.eq(res.entryPriceAfterX96);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    const {premiumRateX96} = await pool.priceState();
                    expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
                }
            });
        });

        describe("decrease margin and size", () => {
            it("should pass when decreasing partial margin and size", async () => {
                const {
                    owner,
                    pool,
                    USDC,
                    ETH,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    _priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                const _sizeDelta = 200n * 10n ** 12n;
                const _marginDelta = tokenCfg.minMarginPerPosition * 2n;

                await USDC.transfer(pool.address, _marginDelta);
                await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

                const account = owner.address;
                const sizeDelta = _sizeDelta / 2n;
                let marginDelta = _marginDelta / 2n;
                const side = SIDE_SHORT;
                const res = await _simulateDecreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                const assertion = expect(pool.decreasePosition(account, side, marginDelta, sizeDelta, account));
                if (sizeDelta > 0n) {
                    await assertion.to
                        .emit(_priceUtil.attach(pool.address), "PremiumRateChanged")
                        .withArgs(res.premiumRateAfterX96);
                    await assertion.to
                        .emit(pool, "GlobalLiquidityPositionNetPositionAdjusted")
                        .withArgs(
                            res.netSizeAfter,
                            res.liquidationBufferNetSizeAfter,
                            res.entryPriceAfterX96,
                            res.sideAfter
                        );
                    await assertion.to.emit(pool, "ProtocolFeeIncreased").withArgs(res.protocolFee);
                    await assertion.to.emit(pool, "GlobalRiskBufferFundChanged").withArgs(res.riskBufferFundAfter);
                    await assertion.to
                        .emit(pool, "GlobalLiquidityPositionRealizedProfitGrowthChanged")
                        .withArgs(res.realizedProfitGrowthAfterX64);
                }
                await assertion.to
                    .emit(pool, "PositionDecreased")
                    .withArgs(
                        account,
                        side,
                        res.marginDeltaAfter,
                        res.marginAfter,
                        res.sizeAfter,
                        res.tradePriceX96,
                        res.realizedPnLDelta,
                        res.fundingFee,
                        res.tradingFee,
                        account
                    );
                await assertion.changeTokenBalances(
                    USDC,
                    [pool.address, account],
                    [-res.marginDeltaAfter, res.marginDeltaAfter]
                );

                {
                    const {longSize, shortSize} = await pool.globalPosition();
                    if (isLongSide(side)) {
                        expect(longSize).to.eq(res.sizeAfter);
                        expect(shortSize).to.eq(0n);
                    } else {
                        expect(longSize).to.eq(0n);
                        expect(shortSize).to.eq(res.sizeAfter);
                    }
                }

                {
                    const {
                        margin: _marginAfter,
                        size: _sizeAfter,
                        entryPriceX96: _entryPriceAfterX96,
                        entryFundingRateGrowthX96,
                    } = await pool.positions(account, side);
                    expect(_marginAfter).to.eq(res.marginAfter);
                    expect(_sizeAfter).to.eq(res.sizeAfter);
                    expect(_entryPriceAfterX96).to.eq(res.entryPriceAfterX96);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }
            });

            it("should pass when decreasing zero margin and zero size", async () => {
                const {
                    owner,
                    pool,
                    USDC,
                    ETH,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                const _sizeDelta = 200n * 10n ** 12n;
                const _marginDelta = tokenCfg.minMarginPerPosition * 2n;

                await USDC.transfer(pool.address, _marginDelta);
                await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

                const account = owner.address;
                const sizeDelta = 0n;
                let marginDelta = 0n;
                const side = SIDE_SHORT;
                const res = await _simulateDecreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );
                expect(res.marginDeltaAfter).to.eq(0n);
                expect(res.tradePriceX96).to.eq(0n);
                expect(res.fundingFee).to.eq(0n);
                expect(res.tradingFee).to.eq(0n);
                expect(res.sizeAfter).to.eq(_sizeDelta);
                const assertion = expect(pool.decreasePosition(account, side, marginDelta, sizeDelta, account));
                await assertion.to
                    .emit(pool, "PositionDecreased")
                    .withArgs(
                        account,
                        side,
                        res.marginDeltaAfter,
                        res.marginAfter,
                        res.sizeAfter,
                        res.tradePriceX96,
                        res.realizedPnLDelta,
                        res.fundingFee,
                        res.tradingFee,
                        account
                    );
                await assertion.changeTokenBalances(
                    USDC,
                    [pool.address, account],
                    [-res.marginDeltaAfter, res.marginDeltaAfter]
                );

                {
                    const {longSize, shortSize} = await pool.globalPosition();
                    if (isLongSide(side)) {
                        expect(longSize).to.eq(res.sizeAfter);
                        expect(shortSize).to.eq(0n);
                    } else {
                        expect(longSize).to.eq(0n);
                        expect(shortSize).to.eq(res.sizeAfter);
                    }
                }

                {
                    const {
                        margin: _marginAfter,
                        size: _sizeAfter,
                        entryPriceX96: _entryPriceAfterX96,
                        entryFundingRateGrowthX96,
                    } = await pool.positions(account, side);
                    expect(_marginAfter).to.eq(res.marginAfter);
                    expect(_sizeAfter).to.eq(res.sizeAfter);
                    expect(_entryPriceAfterX96).to.eq(res.entryPriceAfterX96);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }
            });

            it("should delete position", async () => {
                const {
                    owner,
                    pool,
                    USDC,
                    ETH,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    _priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    ethers.constants.AddressZero,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                const _sizeDelta = 2000000n * 10n ** 12n;
                const _marginDelta = tokenCfg.minMarginPerPosition * 2n;

                await USDC.transfer(pool.address, _marginDelta);
                await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

                const account = owner.address;
                const sizeDelta = _sizeDelta;
                let marginDelta = 19997999n;
                const side = SIDE_SHORT;
                const res = await _simulateDecreasePosition(
                    {
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side,
                    marginDelta,
                    sizeDelta
                );

                const assertion = expect(pool.decreasePosition(account, side, marginDelta, sizeDelta, account));
                if (sizeDelta > 0n) {
                    await assertion.to
                        .emit(_priceUtil.attach(pool.address), "PremiumRateChanged")
                        .withArgs(res.premiumRateAfterX96);
                    await assertion.to
                        .emit(pool, "GlobalLiquidityPositionNetPositionAdjusted")
                        .withArgs(
                            res.netSizeAfter,
                            res.liquidationBufferNetSizeAfter,
                            res.entryPriceAfterX96,
                            res.sideAfter
                        );
                    await assertion.to.emit(pool, "ProtocolFeeIncreased").withArgs(res.protocolFee);
                    await assertion.to.emit(pool, "GlobalRiskBufferFundChanged").withArgs(res.riskBufferFundAfter);
                    await assertion.to
                        .emit(pool, "GlobalLiquidityPositionRealizedProfitGrowthChanged")
                        .withArgs(res.realizedProfitGrowthAfterX64);
                }
                await assertion.to
                    .emit(pool, "PositionDecreased")
                    .withArgs(
                        account,
                        side,
                        res.marginDeltaAfter,
                        res.marginAfter,
                        res.sizeAfter,
                        res.tradePriceX96,
                        res.realizedPnLDelta,
                        res.fundingFee,
                        res.tradingFee,
                        account
                    );
                await assertion.changeTokenBalances(
                    USDC,
                    [pool.address, account],
                    [-res.marginDeltaAfter, res.marginDeltaAfter]
                );

                expect(await pool.positions(account, side)).to.deep.eq([0n, 0n, 0n, 0n]);

                expect(await pool.globalPosition()).to.deep.eq([0n, 0n, 0n, 0n]);

                const {netSize, entryPriceX96: _entryPriceX96} = await pool.globalLiquidityPosition();
                expect(netSize).to.eq(0n);
                expect(_entryPriceX96).to.eq(0n);

                {
                    const {premiumRateX96} = await pool.priceState();
                    expect(premiumRateX96).to.eq(res.premiumRateAfterX96);
                }
            });
        });

        it("should sample and adjust funding rate", async () => {
            const {owner, pool, USDC, ETH, mockPriceFeed, tokenCfg, _fundingRateUtil} = await loadFixture(
                deployFixture
            );
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                ethers.constants.AddressZero,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const _sizeDelta = 200n * 10n ** 12n;
            const _marginDelta = tokenCfg.minMarginPerPosition * 2n;

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, _marginDelta);
            await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

            const account = owner.address;
            const sizeDelta = _sizeDelta / 2n;
            let marginDelta = _marginDelta / 2n;
            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const assertion = expect(pool.decreasePosition(account, SIDE_SHORT, marginDelta, sizeDelta, account));
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should emit ReferralFeeIncreased event if user has a referral token", async () => {
            const {
                owner,
                pool,
                USDC,
                ETH,
                mockPriceFeed,
                tokenCfg,
                tokenFeeRateCfg,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                _priceUtil,
                efc,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                ethers.constants.AddressZero,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const _sizeDelta = 2000000n * 10n ** 12n;
            const _marginDelta = tokenCfg.minMarginPerPosition * 2n;

            await USDC.transfer(pool.address, _marginDelta);
            await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

            const account = owner.address;
            const sizeDelta = _sizeDelta;
            let marginDelta = 19997999n;
            const side = SIDE_SHORT;
            await efc.setRefereeTokens(account, 10000);
            const res = await _simulateDecreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );
            expect(res.tradingFee).to.gt(1n);
            expect(res.referralFee).to.gt(0n);
            expect(res.referralParentFee).to.gt(0n);

            const assertion = expect(pool.decreasePosition(account, side, marginDelta, sizeDelta, account));
            await assertion.to
                .emit(pool, "ReferralFeeIncreased")
                .withArgs(account, res.referralToken, res.referralFee, res.referralParentToken, res.referralParentFee);
            expect(await pool.referralFees(res.referralToken)).to.eq(res.referralFee);
            expect(await pool.referralFees(res.referralParentToken)).to.eq(res.referralParentFee);
        });

        it("should callback for reward farm", async () => {
            const {
                owner,
                pool,
                USDC,
                ETH,
                mockPriceFeed,
                tokenCfg,
                tokenFeeRateCfg,
                positionUtil,
                liquidityPositionUtil,
                priceUtil,
                efc,
                mockRewardFarmCallback,
            } = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                ethers.constants.AddressZero,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            const _sizeDelta = 2000000n * 10n ** 12n;
            const _marginDelta = tokenCfg.minMarginPerPosition * 2n;

            await USDC.transfer(pool.address, _marginDelta);
            await pool.increasePosition(owner.address, SIDE_SHORT, _marginDelta, _sizeDelta);

            const account = owner.address;
            const sizeDelta = _sizeDelta;
            let marginDelta = 19997999n;
            const side = SIDE_SHORT;
            const res = await _simulateDecreasePosition(
                {
                    pool,
                    ETH,
                    mockPriceFeed,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                },
                {
                    tokenCfg,
                    tokenFeeRateCfg,
                },
                account,
                side,
                marginDelta,
                sizeDelta
            );

            const position = await pool.positions(account, side);
            await pool.decreasePosition(account, side, marginDelta, sizeDelta, account);

            expect(await mockRewardFarmCallback.account()).to.eq(account);
            expect(await mockRewardFarmCallback.side()).to.eq(side);
            expect(await mockRewardFarmCallback.sizeAfter()).to.eq(res.sizeAfter);
            expect(await mockRewardFarmCallback.entryPriceAfterX96()).to.eq(position.entryPriceX96);
        });
    });

    describe("#liquidatePosition", () => {
        it("should revert if caller is not a liquidator", async () => {
            const {owner, other, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            await USDC.mint(other.address, tokenCfg.minMarginPerPosition);
            await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.increasePosition(
                other.address,
                SIDE_SHORT,
                tokenCfg.minMarginPerPosition,
                toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n
            );

            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("3", DECIMALS_18, DECIMALS_6));
            await expect(
                pool.connect(other).liquidatePosition(other.address, SIDE_SHORT, other.address)
            ).to.revertedWithCustomError(pool, "CallerNotLiquidator");
        });

        it("should revert if position does not exist", async () => {
            const {other, pool, ETH, mockPriceFeed} = await loadFixture(deployFixture);

            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1808.235", DECIMALS_18, DECIMALS_6) * 2n);
            await expect(pool.liquidatePosition(other.address, SIDE_SHORT, other.address))
                .to.revertedWithCustomError(pool, "PositionNotFound")
                .withArgs(other.address, SIDE_SHORT);
        });

        it("should revert if risk rate is too low", async () => {
            const {owner, other, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
            await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerLiquidityPosition * 100n,
                tokenCfg.minMarginPerLiquidityPosition * 100n
            );

            await USDC.mint(other.address, tokenCfg.minMarginPerPosition);
            await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.increasePosition(
                other.address,
                SIDE_SHORT,
                tokenCfg.minMarginPerPosition,
                toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n
            );

            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1.1", DECIMALS_18, DECIMALS_6));
            await expect(pool.liquidatePosition(other.address, SIDE_SHORT, other.address)).to.revertedWithCustomError(
                pool,
                "MarginRateTooLow"
            );
        });

        async function _simulateLiquidatePosition(
            contracts: {
                poolFactory: PoolFactory;
                pool: Pool;
                ETH: ERC20Test;
                mockPriceFeed: MockPriceFeed;
                positionUtil: PositionUtilTest;
                liquidityPositionUtil: LiquidityPositionUtilTest;
                priceUtil: PriceUtilTest;
                efc: MockEFC;
            },
            cfg: {
                tokenCfg: {
                    minMarginPerLiquidityPosition: bigint;
                    maxRiskRatePerLiquidityPosition: bigint;
                    maxLeveragePerLiquidityPosition: bigint;
                    minMarginPerPosition: bigint;
                    maxLeveragePerPosition: bigint;
                    liquidationFeeRatePerPosition: bigint;
                    liquidationExecutionFee: bigint;
                    interestRate: bigint;
                    maxFundingRate: bigint;
                };
                tokenFeeRateCfg: {
                    tradingFeeRate: bigint;
                    liquidityFeeRate: bigint;
                    protocolFeeRate: bigint;
                    referralReturnFeeRate: bigint;
                    referralParentReturnFeeRate: bigint;
                    referralDiscountRate: bigint;
                };
            },
            account: string,
            side: Side
        ) {
            const position = await contracts.pool.positions(account, side);
            expect(position.size).to.gt(0n);
            const globalPosition = await contracts.pool.globalPosition();
            const globalLiquidityPosition = await contracts.pool.globalLiquidityPosition();
            expect(globalLiquidityPosition.liquidity).to.gt(0n);
            const decreaseIndexPriceX96 = !isLongSide(side)
                ? await contracts.mockPriceFeed.getMaxPriceX96(contracts.ETH.address)
                : await contracts.mockPriceFeed.getMinPriceX96(contracts.ETH.address);

            // _buildTradingFeeState
            const tradingFeeState = await _buildTradingFeeState(contracts.efc, cfg.tokenFeeRateCfg, account);
            let requiredFundingFee = await contracts.positionUtil.calculateFundingFee(
                isLongSide(side) ? globalPosition.longFundingRateGrowthX96 : globalPosition.shortFundingRateGrowthX96,
                position.entryFundingRateGrowthX96,
                position.size
            );
            const unrealizedPnl = await contracts.positionUtil.calculateUnrealizedPnL(
                side,
                position.size,
                position.entryPriceX96,
                decreaseIndexPriceX96
            );
            const maintenanceMargin = await contracts.positionUtil.calculateMaintenanceMargin(
                position.size,
                position.entryPriceX96,
                decreaseIndexPriceX96,
                cfg.tokenCfg.liquidationFeeRatePerPosition,
                tradingFeeState.tradingFeeRate,
                cfg.tokenCfg.liquidationExecutionFee
            );
            const marginAfter = position.margin.add(requiredFundingFee);
            expect(
                marginAfter.lt(0) ||
                    marginAfter.add(unrealizedPnl).lt(0) ||
                    maintenanceMargin.gte(marginAfter.add(unrealizedPnl))
            );

            // update price state
            const priceState = await contracts.pool.priceState();
            await contracts.priceUtil.setPoolFactory(contracts.poolFactory.address);
            await contracts.priceUtil.setPriceFeed(contracts.mockPriceFeed.address);
            await contracts.priceUtil.setToken(contracts.ETH.address);
            await contracts.priceUtil.setPriceState(priceState);
            await contracts.priceUtil.setGlobalLiquidityPosition(globalLiquidityPosition);
            await contracts.priceUtil.updatePriceState(flipSide(side), position.size, decreaseIndexPriceX96, true);
            const globalLiquidityPositionAfter = await contracts.priceUtil.globalLiquidityPosition();
            const sideAfter = globalLiquidityPositionAfter.side;
            const netSizeAfter = globalLiquidityPositionAfter.netSize;
            const liquidationBufferNetSize = globalLiquidityPositionAfter.liquidationBufferNetSize;

            // _liquidatePosition
            const previousGlobalFundingRate = await contracts.pool.previousGlobalFundingRate();
            await contracts.positionUtil.setPreviousGlobalFundingRate(
                previousGlobalFundingRate.longFundingRateGrowthX96,
                previousGlobalFundingRate.shortFundingRateGrowthX96
            );

            const {liquidationPriceX96, adjustedFundingFee} = await contracts.positionUtil.calculateLiquidationPriceX96(
                position,
                side,
                requiredFundingFee,
                cfg.tokenCfg.liquidationFeeRatePerPosition,
                tradingFeeState.tradingFeeRate,
                cfg.tokenCfg.liquidationExecutionFee
            );
            const liquidationFee = await contracts.positionUtil.calculateLiquidationFee(
                position.size,
                position.entryPriceX96,
                cfg.tokenCfg.liquidationFeeRatePerPosition
            );
            let riskBufferFundDelta = BigNumber.from(liquidationFee);
            let insufficientFundingRateGrowthDeltaX96 = 0n;
            let fundingRateUpdated = false;
            let shortFundingRateGrowthAfterX96 = globalPosition.shortFundingRateGrowthX96;
            let longFundingRateGrowthAfterX96 = globalPosition.longFundingRateGrowthX96;
            let insufficientFundingFee = BigNumber.from(0n);
            if (!requiredFundingFee.eq(adjustedFundingFee)) {
                insufficientFundingFee = adjustedFundingFee.sub(requiredFundingFee);
                const oppositeSize = isLongSide(side) ? globalPosition.shortSize : globalPosition.longSize;
                if (oppositeSize.gt(0n)) {
                    insufficientFundingRateGrowthDeltaX96 = mulDiv(insufficientFundingFee.abs(), Q96, oppositeSize);
                    if (isLongSide(side)) {
                        shortFundingRateGrowthAfterX96 = shortFundingRateGrowthAfterX96.sub(
                            insufficientFundingRateGrowthDeltaX96
                        );
                    } else {
                        longFundingRateGrowthAfterX96 = longFundingRateGrowthAfterX96.sub(
                            insufficientFundingRateGrowthDeltaX96
                        );
                    }
                    fundingRateUpdated = true;
                } else {
                    riskBufferFundDelta = riskBufferFundDelta.sub(insufficientFundingFee);
                }
            }
            // _adjustGlobalLiquidityPosition
            const globalRiskBufferFund = await contracts.pool.globalRiskBufferFund();
            const adjustGlobalLiquidityPositionRes = await _adjustGlobalLiquidityPosition(
                contracts,
                cfg.tokenFeeRateCfg,
                globalRiskBufferFund,
                globalLiquidityPosition,
                tradingFeeState,
                flipSide(side),
                liquidationPriceX96,
                position.size,
                riskBufferFundDelta
            );

            return {
                marginAfter,
                decreaseIndexPriceX96,
                unrealizedPnl,
                requiredFundingFee,
                liquidationPriceX96,
                adjustedFundingFee,
                liquidationFee,
                riskBufferFundDelta,
                insufficientFundingRateGrowthDeltaX96,
                fundingRateUpdated,
                shortFundingRateGrowthAfterX96,
                longFundingRateGrowthAfterX96,
                sideAfter,
                netSizeAfter,
                liquidationBufferNetSize,
                insufficientFundingFee,
                ...adjustGlobalLiquidityPositionRes,
                referralToken: tradingFeeState.referralToken,
                referralParentToken: tradingFeeState.referralParentToken,
            };
        }

        describe("should pass", () => {
            it("should pass", async () => {
                const {
                    owner,
                    other,
                    positionLiquidator,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );

                const position = await pool.positions(account, side);
                const globalPosition = await pool.globalPosition();
                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "PositionLiquidated")
                    .withArgs(
                        positionLiquidator,
                        account,
                        side,
                        res.decreaseIndexPriceX96,
                        res.liquidationPriceX96,
                        res.adjustedFundingFee,
                        res.tradingFee,
                        res.liquidationFee,
                        tokenCfg.liquidationExecutionFee,
                        account
                    );

                {
                    const {longSize, shortSize, longFundingRateGrowthX96, shortFundingRateGrowthX96} =
                        await pool.globalPosition();
                    expect(longSize).to.eq(globalPosition.longSize);
                    expect(shortSize).to.eq(globalPosition.shortSize.sub(position.size));
                    if (isLongSide(side)) {
                        expect(shortFundingRateGrowthX96).to.eq(res.shortFundingRateGrowthAfterX96);
                    } else {
                        expect(longFundingRateGrowthX96).to.eq(res.longFundingRateGrowthAfterX96);
                    }
                }

                {
                    const {margin, size, entryPriceX96, entryFundingRateGrowthX96} = await pool.positions(
                        account,
                        side
                    );
                    expect(margin).to.eq(0n);
                    expect(size).to.eq(0n);
                    expect(entryPriceX96).to.eq(0n);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    if (res.fundingRateUpdated) {
                        const previousGlobalFundingRate = await pool.previousGlobalFundingRate();
                        expect(previousGlobalFundingRate.longFundingRateGrowthX96).to.eq(
                            globalPosition.longFundingRateGrowthX96
                        );
                        expect(previousGlobalFundingRate.shortFundingRateGrowthX96).to.eq(
                            globalPosition.shortFundingRateGrowthX96
                        );
                    }
                }

                {
                    const globalLiquidityPositionAfter = await pool.globalLiquidityPosition();
                    expect(globalLiquidityPositionAfter.liquidity).to.eq(tokenCfg.minMarginPerLiquidityPosition * 100n);
                    expect(globalLiquidityPositionAfter.netSize).to.eq(res.netSizeAfter);
                    expect(globalLiquidityPositionAfter.entryPriceX96).to.eq(res.entryPriceAfterX96);
                    expect(globalLiquidityPositionAfter.side).to.eq(res.sideAfter);
                    expect(globalLiquidityPositionAfter.realizedProfitGrowthX64).to.eq(
                        res.realizedProfitGrowthAfterX64
                    );
                    const {riskBufferFund} = await pool.globalRiskBufferFund();
                    expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
                }
            });

            it("should sample and adjust funding rate", async () => {
                const {owner, other, pool, _fundingRateUtil, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(
                    deployFixture
                );
                const lastTimestamp = await time.latest();
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
                    toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n
                );

                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("2", DECIMALS_18, DECIMALS_6) + 2n);

                const side = SIDE_SHORT;
                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                const assertion = expect(pool.liquidatePosition(other.address, side, other.address));
                await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
                await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
            });

            it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
                const {owner, other, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await USDC.mint(other.address, tokenCfg.minMarginPerPosition);
                await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    other.address,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n
                );

                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("2", DECIMALS_18, DECIMALS_6) + 2n);

                const side = SIDE_SHORT;
                const globalMetric = await pool.globalUnrealizedLossMetrics();
                const nextBlockTimestamp = (await time.latest()) + 60;
                await time.setNextBlockTimestamp(nextBlockTimestamp);
                const assertion = expect(pool.liquidatePosition(other.address, side, other.address));
                await assertion.to
                    .emit(pool, "GlobalUnrealizedLossMetricsChanged")
                    .withArgs(nextBlockTimestamp, globalMetric.liquidity, globalMetric.liquidityTimesUnrealizedLoss);
            });

            it("should emit FundingRateGrowthAdjusted event if funding fee is adjusted and opposite size is positive", async () => {
                const {
                    owner,
                    other,
                    pool,
                    poolFactory,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg: newTokenCfg,
                        tokenFeeRateCfg: newTokenFeeRateCfg,
                    },
                    account,
                    side
                );
                expect(res.fundingRateUpdated).to.true;

                const globalPosition = await pool.globalPosition();
                const position = await pool.positions(account, side);
                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "FundingRateGrowthAdjusted")
                    .withArgs(0n, res.longFundingRateGrowthAfterX96, res.shortFundingRateGrowthAfterX96, () => true);

                {
                    const {
                        shortSize: _shortSize,
                        longSize: _longSize,
                        shortFundingRateGrowthX96: _shortFundingRateGrowthX96,
                        longFundingRateGrowthX96: _longFundingRateGrowthX96,
                    } = await pool.globalPosition();
                    expect(_shortSize).to.eq(globalPosition.shortSize.sub(position.size));
                    expect(_longSize).to.eq(globalPosition.longSize);
                    expect(_shortFundingRateGrowthX96).to.eq(res.shortFundingRateGrowthAfterX96);
                    expect(_longFundingRateGrowthX96).to.eq(res.longFundingRateGrowthAfterX96);
                }

                {
                    const previousGlobalFundingRate = await pool.previousGlobalFundingRate();
                    expect(previousGlobalFundingRate.longFundingRateGrowthX96).to.eq(
                        globalPosition.longFundingRateGrowthX96
                    );
                    expect(previousGlobalFundingRate.shortFundingRateGrowthX96).to.eq(
                        globalPosition.shortFundingRateGrowthX96
                    );
                }
            });

            it("should make insufficientFundingFee to be added to riskBufferFundDelta if funding fee is adjusted and there is no opposite position", async () => {
                const {
                    owner,
                    other,
                    other2,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    poolFactory,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg: newTokenCfg,
                        tokenFeeRateCfg: newTokenFeeRateCfg,
                    },
                    account,
                    side
                );
                expect(res.fundingRateUpdated).to.false;
                expect(res.insufficientFundingFee).to.gt(0n);

                const globalRiskBufferFund = await pool.globalRiskBufferFund();
                await pool.liquidatePosition(account, side, account);
                {
                    const {riskBufferFund: riskBufferFundAfter} = await pool.globalRiskBufferFund();
                    expect(riskBufferFundAfter).to.not.eq(globalRiskBufferFund.riskBufferFund);
                    expect(riskBufferFundAfter).to.eq(
                        globalRiskBufferFund.riskBufferFund
                            .add(res.riskBufferFundDelta)
                            .add(res.realizedPnL)
                            .add(res.riskBufferFundFee)
                    );
                    expect(riskBufferFundAfter).to.eq(res.riskBufferFundAfter);
                }
            });

            it("should transfer out liquidation execution fee to fee receiver", async () => {
                const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(
                    deployFixture
                );
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

                await pool.liquidatePosition(other.address, SIDE_SHORT, other2.address);

                expect(await USDC.balanceOf(other2.address)).to.eq(tokenCfg.liquidationExecutionFee);
            });

            it("should emit GlobalLiquidityPositionNetPositionAdjusted event", async () => {
                const {
                    owner,
                    other,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );

                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "GlobalLiquidityPositionNetPositionAdjusted")
                    .withArgs(res.netSizeAfter, res.liquidationBufferNetSize, res.entryPriceAfterX96, res.sideAfter);
            });

            it("should emit ProtocolFeeIncreased event", async () => {
                const {
                    owner,
                    other,
                    positionLiquidator,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );

                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "ProtocolFeeIncreased")
                    .withArgs(res.protocolFee);
            });

            it("should emit ReferralFeeIncreased event if user has a referral token", async () => {
                const {
                    owner,
                    other,
                    positionLiquidator,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;
                await efc.setRefereeTokens(account, 10000);
                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );

                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "ReferralFeeIncreased")
                    .withArgs(
                        account,
                        res.referralToken,
                        res.referralFee,
                        res.referralParentToken,
                        res.referralParentFee
                    );
                expect(await pool.referralFees(res.referralToken)).to.eq(res.referralFee);
                expect(await pool.referralFees(res.referralParentToken)).to.eq(res.referralParentFee);
            });

            it("should emit GlobalRiskBufferFundChanged event", async () => {
                const {
                    owner,
                    other,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );

                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "GlobalRiskBufferFundChanged")
                    .withArgs(res.riskBufferFundAfter);
            });

            it("should emit GlobalLiquidityPositionRealizedProfitGrowthChanged event", async () => {
                const {
                    owner,
                    other,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );

                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "GlobalLiquidityPositionRealizedProfitGrowthChanged")
                    .withArgs(res.realizedProfitGrowthAfterX64);
            });

            it("should remove position", async () => {
                const {owner, other, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await USDC.mint(other.address, tokenCfg.minMarginPerPosition);
                await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition);
                await pool.increasePosition(
                    other.address,
                    SIDE_SHORT,
                    tokenCfg.minMarginPerPosition,
                    toPriceX96("1", DECIMALS_18, DECIMALS_6) * 600n
                );

                expect(await USDC.balanceOf(other.address)).to.eq(0n);

                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("2", DECIMALS_18, DECIMALS_6) + 2n);
                await pool.liquidatePosition(other.address, SIDE_SHORT, other.address);

                const {margin, size, entryPriceX96, entryFundingRateGrowthX96} = await pool.positions(
                    other.address,
                    SIDE_SHORT
                );
                expect(margin).to.eq(0n);
                expect(size).to.eq(0n);
                expect(entryPriceX96).to.eq(0n);
                expect(entryFundingRateGrowthX96).to.eq(0n);
            });

            it("should emit PositionLiquidated event", async () => {
                const {
                    owner,
                    other,
                    positionLiquidator,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                const account = other.address;
                const side = SIDE_SHORT;

                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );

                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "PositionLiquidated")
                    .withArgs(
                        positionLiquidator,
                        account,
                        side,
                        res.decreaseIndexPriceX96,
                        res.liquidationPriceX96,
                        res.adjustedFundingFee,
                        res.tradingFee,
                        res.liquidationFee,
                        tokenCfg.liquidationExecutionFee,
                        account
                    );
            });

            it("should callback for reward farm", async () => {
                const {owner, other, pool, ETH, USDC, mockPriceFeed, tokenCfg, mockRewardFarmCallback} =
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

                const account = other.address;
                const side = SIDE_SHORT;

                await pool.liquidatePosition(account, side, account);

                expect(await mockRewardFarmCallback.account()).to.eq(account);
                expect(await mockRewardFarmCallback.side()).to.eq(side);
                expect(await mockRewardFarmCallback.sizeAfter()).to.eq(0n);
                expect(await mockRewardFarmCallback.entryPriceAfterX96()).to.eq(0n);
            });
        });

        describe("extreme situation", () => {
            it("should pass if realizedPnL is positive but margin is not enough to pay funding fee", async () => {
                const {
                    owner,
                    other,
                    poolFactory,
                    pool,
                    positionLiquidator,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    tokenFeeRateCfg,
                    positionUtil,
                    liquidityPositionUtil,
                    priceUtil,
                    efc,
                } = await loadFixture(deployFixture);
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

                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("0.5", DECIMALS_18, DECIMALS_6));
                for (let i = 1; i < 75; i++) {
                    await time.setNextBlockTimestamp(nextHourBegin + 3600 * i);
                    await expect(pool.collectReferralFee(0, owner.address)).to.emit(pool, "FundingRateGrowthAdjusted");
                }

                const account = other.address;
                const side = SIDE_SHORT;

                const position = await pool.positions(account, side);
                const res = await _simulateLiquidatePosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        positionUtil,
                        liquidityPositionUtil,
                        priceUtil,
                        efc,
                    },
                    {
                        tokenCfg,
                        tokenFeeRateCfg,
                    },
                    account,
                    side
                );
                expect(res.unrealizedPnl).to.gt(0n);
                expect(res.unrealizedPnl).to.gt(res.requiredFundingFee.abs());
                expect(res.requiredFundingFee.abs()).to.gt(position.margin);
                expect(res.fundingRateUpdated).to.true;

                const globalPosition = await pool.globalPosition();
                await expect(pool.liquidatePosition(account, side, account))
                    .to.emit(pool, "PositionLiquidated")
                    .withArgs(
                        positionLiquidator,
                        account,
                        side,
                        res.decreaseIndexPriceX96,
                        res.liquidationPriceX96,
                        res.adjustedFundingFee,
                        res.tradingFee,
                        res.liquidationFee,
                        tokenCfg.liquidationExecutionFee,
                        account
                    );

                {
                    const {longSize, shortSize, longFundingRateGrowthX96, shortFundingRateGrowthX96} =
                        await pool.globalPosition();
                    expect(longSize).to.eq(globalPosition.longSize);
                    expect(shortSize).to.eq(globalPosition.shortSize.sub(position.size));
                    if (isLongSide(side)) {
                        expect(shortFundingRateGrowthX96).to.eq(res.shortFundingRateGrowthAfterX96);
                    } else {
                        expect(longFundingRateGrowthX96).to.eq(res.longFundingRateGrowthAfterX96);
                    }
                }

                {
                    const {margin, size, entryPriceX96, entryFundingRateGrowthX96} = await pool.positions(
                        account,
                        side
                    );
                    expect(margin).to.eq(0n);
                    expect(size).to.eq(0n);
                    expect(entryPriceX96).to.eq(0n);
                    expect(entryFundingRateGrowthX96).to.eq(0n);
                }

                {
                    if (res.fundingRateUpdated) {
                        const previousGlobalFundingRate = await pool.previousGlobalFundingRate();
                        expect(previousGlobalFundingRate.longFundingRateGrowthX96).to.eq(
                            globalPosition.longFundingRateGrowthX96
                        );
                        expect(previousGlobalFundingRate.shortFundingRateGrowthX96).to.eq(
                            globalPosition.shortFundingRateGrowthX96
                        );
                    }
                }

                {
                    const globalLiquidityPositionAfter = await pool.globalLiquidityPosition();
                    expect(globalLiquidityPositionAfter.liquidity).to.eq(tokenCfg.minMarginPerLiquidityPosition * 100n);
                    expect(globalLiquidityPositionAfter.netSize).to.eq(res.netSizeAfter);
                    expect(globalLiquidityPositionAfter.entryPriceX96).to.eq(res.entryPriceAfterX96);
                    expect(globalLiquidityPositionAfter.side).to.eq(res.sideAfter);
                    expect(globalLiquidityPositionAfter.realizedProfitGrowthX64).to.eq(
                        res.realizedProfitGrowthAfterX64
                    );
                    const {riskBufferFund} = await pool.globalRiskBufferFund();
                    expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
                }
            });
        });
    });

    describe("#liquidateLiquidityPosition", () => {
        it("should revert if caller is not a liquidator", async () => {
            const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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

            await expect(pool.connect(other).liquidateLiquidityPosition(1n, other.address)).to.revertedWithCustomError(
                pool,
                "CallerNotLiquidator"
            );
        });

        it("should revert if liquidity is zero(liquidity position does not exist)", async () => {
            const {other, pool} = await loadFixture(deployFixture);
            await expect(pool.liquidateLiquidityPosition(1n, other.address)).to.revertedWithCustomError(
                pool,
                "LiquidityPositionNotFound"
            );
        });

        it("should revert if risk rate is too low", async () => {
            const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
            const priceX96 = toPriceX96("1", DECIMALS_18, DECIMALS_6) * 6n;
            await mockPriceFeed.setMinPriceX96(ETH.address, priceX96);

            await expect(pool.liquidateLiquidityPosition(1n, other.address)).to.revertedWithCustomError(
                pool,
                "RiskRateTooLow"
            );
        });

        async function _simulateLiquidateLiquidityPosition(
            contracts: {
                poolFactory: PoolFactory;
                pool: Pool;
                ETH: ERC20Test;
                mockPriceFeed: MockPriceFeed;
                liquidityPositionUtil: LiquidityPositionUtilTest;
            },
            tokenCfg: {
                minMarginPerLiquidityPosition: bigint;
                maxRiskRatePerLiquidityPosition: bigint;
                maxLeveragePerLiquidityPosition: bigint;
                minMarginPerPosition: bigint;
                maxLeveragePerPosition: bigint;
                liquidationFeeRatePerPosition: bigint;
                liquidationExecutionFee: bigint;
                interestRate: bigint;
                maxFundingRate: bigint;
            },
            positionID: BigNumberish
        ) {
            const globalLiquidityPosition = await contracts.pool.globalLiquidityPosition();
            const globalMetric = await contracts.pool.globalUnrealizedLossMetrics();
            const liquidityPosition = await contracts.pool.liquidityPositions(positionID);
            const globalRiskBufferFund = await contracts.pool.globalRiskBufferFund();

            const priceX96 = isLongSide(globalLiquidityPosition.side)
                ? await contracts.mockPriceFeed.getMaxPriceX96(contracts.ETH.address)
                : await contracts.mockPriceFeed.getMinPriceX96(contracts.ETH.address);
            const unrealizedLoss = await contracts.liquidityPositionUtil.calculateUnrealizedLoss(
                globalLiquidityPosition.side,
                globalLiquidityPosition.netSize,
                globalLiquidityPosition.entryPriceX96,
                priceX96,
                globalRiskBufferFund.riskBufferFund
            );

            const positionRealizedProfit = await contracts.liquidityPositionUtil.calculateRealizedProfit(
                liquidityPosition,
                globalLiquidityPosition
            );
            let marginAfter = liquidityPosition.margin.add(positionRealizedProfit);

            const positionUnrealizedLoss = await contracts.liquidityPositionUtil.calculatePositionUnrealizedLoss(
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
            if (marginAfter.lt(liquidationExecutionFee)) {
                liquidationExecutionFee = marginAfter;
                marginAfter = BigNumber.from(0);
            } else {
                marginAfter = marginAfter.sub(liquidationExecutionFee);
            }
            let globalLiquidityAfter = globalLiquidityPosition.liquidity.sub(liquidityPosition.liquidity);
            const riskBufferFundAfter = globalRiskBufferFund.riskBufferFund.add(marginAfter);

            const priceState = await contracts.pool.priceState();
            const changePriceVerticesResult = await _changePriceVertices(
                priceState,
                contracts.mockPriceFeed,
                contracts.poolFactory,
                contracts.ETH,
                globalLiquidityAfter
            );

            return {
                positionRealizedProfit,
                liquidationExecutionFee,
                marginAfter,
                globalLiquidityAfter,
                riskBufferFundAfter,
                changePriceVerticesResult,
            };
        }

        describe("should pass", () => {
            it("should pass", async () => {
                const {
                    owner,
                    other,
                    other2,
                    liquidityPositionLiquidator,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    liquidityPositionUtil,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) * 12n);

                const positionID = 1n;
                const res = await _simulateLiquidateLiquidityPosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        liquidityPositionUtil,
                    },
                    tokenCfg,
                    positionID
                );

                const globalLiquidityPosition = await pool.globalLiquidityPosition();
                await expect(pool.liquidateLiquidityPosition(positionID, other.address))
                    .to.emit(pool, "LiquidityPositionLiquidated")
                    .withArgs(
                        liquidityPositionLiquidator,
                        positionID,
                        res.positionRealizedProfit,
                        res.marginAfter,
                        res.liquidationExecutionFee,
                        other.address
                    );

                {
                    const globalLiquidityPositionAfter = await pool.globalLiquidityPosition();
                    expect(globalLiquidityPositionAfter.liquidity).to.eq(res.globalLiquidityAfter);
                    expect(globalLiquidityPositionAfter.netSize).to.eq(globalLiquidityPosition.netSize);
                    expect(globalLiquidityPositionAfter.entryPriceX96).to.eq(globalLiquidityPosition.entryPriceX96);
                    expect(globalLiquidityPositionAfter.side).to.eq(globalLiquidityPosition.side);
                    expect(globalLiquidityPositionAfter.realizedProfitGrowthX64).to.eq(
                        globalLiquidityPosition.realizedProfitGrowthX64
                    );
                    const {riskBufferFund} = await pool.globalRiskBufferFund();
                    expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
                }
            });

            it("should sample and adjust funding rate", async () => {
                const {owner, other, other2, pool, _fundingRateUtil, ETH, USDC, mockPriceFeed, tokenCfg} =
                    await loadFixture(deployFixture);
                const lastTimestamp = await time.latest();
                const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
                await time.setNextBlockTimestamp(nextHourBegin);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 100n);
                await pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 300n
                );
                await time.setNextBlockTimestamp(nextHourBegin + 5);
                await USDC.mint(other.address, tokenCfg.minMarginPerPosition * 100n);
                await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition * 100n);
                await pool.openLiquidityPosition(
                    other.address,
                    tokenCfg.minMarginPerLiquidityPosition * 100n,
                    tokenCfg.minMarginPerLiquidityPosition * 100n
                );

                await time.setNextBlockTimestamp(nextHourBegin + 10);
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

                await time.setNextBlockTimestamp(nextHourBegin + 3600);
                const assertion = expect(pool.liquidateLiquidityPosition(1n, other.address));
                await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
                await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
            });

            it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
                const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(
                    deployFixture
                );
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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

                const globalMetric = await pool.globalUnrealizedLossMetrics();

                const contractTransaction = await pool.liquidateLiquidityPosition(1n, other.address);
                const eventNameFilter = pool.filters.GlobalUnrealizedLossMetricsChanged();
                const events = await pool.queryFilter(eventNameFilter, contractTransaction.blockNumber);
                expect(events.length).to.eq(2);
                events.forEach((event) => {
                    expect(event.args.lastZeroLossTimeAfter).to.eq(globalMetric.lastZeroLossTime);
                    expect(event.args.liquidityAfter).to.eq(globalMetric.liquidity);
                    expect(event.args.liquidityTimesUnrealizedLossAfter).to.eq(
                        globalMetric.liquidityTimesUnrealizedLoss
                    );
                });
            });

            it("should pay for liquidation execution fee to fee receiver if remaining margin enough", async () => {
                const {
                    owner,
                    other,
                    other2,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    liquidityPositionUtil,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) * 12n);

                const positionID = 1n;
                const res = await _simulateLiquidateLiquidityPosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        liquidityPositionUtil,
                    },
                    tokenCfg,
                    positionID
                );
                expect(res.marginAfter).to.gt(res.liquidationExecutionFee);

                await pool.liquidateLiquidityPosition(positionID, other.address);

                expect(await USDC.balanceOf(other.address)).to.eq(res.liquidationExecutionFee);
            });

            it("should add remaining margin to riskBufferFund", async () => {
                const {
                    owner,
                    other,
                    other2,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    liquidityPositionUtil,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
                // make riskBufferFund to have some value
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

                let priceX96 = toPriceX96("1", DECIMALS_18, DECIMALS_6) * 630n;
                await mockPriceFeed.setMinPriceX96(ETH.address, priceX96);

                const positionID = 1n;
                const res = await _simulateLiquidateLiquidityPosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        liquidityPositionUtil,
                    },
                    tokenCfg,
                    positionID
                );
                expect(res.marginAfter).to.gt(0n);
                const {riskBufferFund} = await pool.globalRiskBufferFund();
                expect(res.riskBufferFundAfter).to.eq(riskBufferFund.add(res.marginAfter));

                await pool.liquidateLiquidityPosition(1n, other.address);
                {
                    const {liquidity} = await pool.globalLiquidityPosition();
                    expect(liquidity).to.eq(res.globalLiquidityAfter);
                    const {riskBufferFund} = await pool.globalRiskBufferFund();
                    expect(riskBufferFund).to.eq(res.riskBufferFundAfter);
                }
            });

            it("should remove position", async () => {
                const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(
                    deployFixture
                );
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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

                await pool.liquidateLiquidityPosition(1n, other.address);

                {
                    const liquidityPosition = await pool.liquidityPositions(1n);
                    expect(liquidityPosition.liquidity).to.eq(0);
                }
            });

            it("should emit LiquidityPositionLiquidated event", async () => {
                const {
                    owner,
                    other,
                    other2,
                    liquidityPositionLiquidator,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    liquidityPositionUtil,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) * 12n);

                const positionID = 1n;
                const res = await _simulateLiquidateLiquidityPosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        liquidityPositionUtil,
                    },
                    tokenCfg,
                    positionID
                );

                await expect(pool.liquidateLiquidityPosition(1n, other.address))
                    .to.emit(pool, "LiquidityPositionLiquidated")
                    .withArgs(
                        liquidityPositionLiquidator,
                        positionID,
                        res.positionRealizedProfit,
                        res.marginAfter,
                        res.liquidationExecutionFee,
                        other.address
                    );
            });

            it("should emit GlobalRiskBufferFundChanged event", async () => {
                const {
                    owner,
                    other,
                    other2,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    liquidityPositionUtil,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) * 12n);

                const positionID = 1n;
                const res = await _simulateLiquidateLiquidityPosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        liquidityPositionUtil,
                    },
                    tokenCfg,
                    positionID
                );

                await expect(pool.liquidateLiquidityPosition(positionID, other.address))
                    .to.emit(pool, "GlobalRiskBufferFundChanged")
                    .withArgs(res.riskBufferFundAfter);
            });

            it("should emit PriceVertexChanged event ", async () => {
                const {
                    owner,
                    other,
                    other2,
                    poolFactory,
                    pool,
                    ETH,
                    USDC,
                    mockPriceFeed,
                    tokenCfg,
                    liquidityPositionUtil,
                } = await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) * 12n);

                const positionID = 1n;
                const res = await _simulateLiquidateLiquidityPosition(
                    {
                        poolFactory,
                        pool,
                        ETH,
                        mockPriceFeed,
                        liquidityPositionUtil,
                    },
                    tokenCfg,
                    positionID
                );

                const assertion = expect(pool.liquidateLiquidityPosition(positionID, other.address));
                for (const v of res.changePriceVerticesResult) {
                    await assertion.to
                        .emit(pool, "PriceVertexChanged")
                        .withArgs(v.vertexIndex, v.sizeAfter, v.premiumRateAfterX96);
                }
            });

            it("should callback for reward farm", async () => {
                const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg, mockRewardFarmCallback} =
                    await loadFixture(deployFixture);
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) + 1n);
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
                await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6) * 12n);

                await pool.liquidateLiquidityPosition(1n, other.address);

                expect(await mockRewardFarmCallback.account()).to.eq(owner.address);
                expect(await mockRewardFarmCallback.liquidityDelta()).to.eq(
                    -(tokenCfg.minMarginPerLiquidityPosition * 300n)
                );
            });
        });
    });

    describe("#marketPriceX96", () => {
        it("should pass", async () => {
            const {owner, pool, USDC, ETH, priceUtil, mockPriceFeed} = await loadFixture(deployFixture);
            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            const globalLiquidityPosition = await pool.globalLiquidityPosition();
            const priceState = await pool.priceState();
            expect(await pool.marketPriceX96(SIDE_LONG)).to.eq(
                await priceUtil.calculateMarketPriceX96(
                    globalLiquidityPosition.side,
                    SIDE_LONG,
                    mockPriceFeed.getMaxPriceX96(ETH.address),
                    priceState.premiumRateX96
                )
            );
        });
    });

    describe("#onChangeTokenConfig", () => {
        it("should revert if caller is not the pool factory", async () => {
            const {pool, poolFactory} = await loadFixture(deployFixture);
            await expect(pool.onChangeTokenConfig())
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(poolFactory.address);
        });

        it("should sample and adjust funding rate", async () => {
            const {owner, pool, _fundingRateUtil, USDC, ETH, poolFactory, tokenCfg, tokenFeeRateCfg, tokenPriceCfg} =
                await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const assertion = expect(
                poolFactory.updateTokenConfig(ETH.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
            );
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
            const {pool, ETH, poolFactory, tokenCfg, tokenFeeRateCfg, tokenPriceCfg} = await loadFixture(deployFixture);
            await expect(poolFactory.updateTokenConfig(ETH.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)).to.emit(
                pool,
                "GlobalUnrealizedLossMetricsChanged"
            );
        });

        it("should change token config", async () => {
            const {pool, ETH, poolFactory, tokenCfg, tokenFeeRateCfg} = await loadFixture(deployFixture);
            const newTokenPriceCfg = newTokenPriceConfig();
            newTokenPriceCfg.maxPriceImpactLiquidity += 1n;
            await poolFactory.updateTokenConfig(ETH.address, tokenCfg, tokenFeeRateCfg, newTokenPriceCfg);
            {
                const priceState = await pool.priceState();
                expect(priceState.maxPriceImpactLiquidity).to.eq(newTokenPriceCfg.maxPriceImpactLiquidity);
            }
        });

        it("should adjust price vertices if price config changed", async () => {
            const {owner, pool, USDC, ETH, poolFactory, tokenCfg, tokenFeeRateCfg, mockPriceFeed} = await loadFixture(
                deployFixture
            );
            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);
            const newTokenPriceCfg = newTokenPriceConfig();
            newTokenPriceCfg.maxPriceImpactLiquidity += 1n;

            const assertion = expect(
                poolFactory.updateTokenConfig(ETH.address, tokenCfg, tokenFeeRateCfg, newTokenPriceCfg)
            );
            const changePriceVerticesResult = await _changePriceVertices(
                await pool.priceState(),
                mockPriceFeed,
                poolFactory,
                ETH,
                20_000n * 10n ** 18n
            );
            for (const value of changePriceVerticesResult) {
                await assertion.to
                    .emit(pool, "PriceVertexChanged")
                    .withArgs(value.vertexIndex, value.sizeAfter, value.premiumRateAfterX96);
            }
        });

        it("should change price feed", async () => {
            const {pool, ETH, poolFactory, tokenCfg, tokenFeeRateCfg, tokenPriceCfg} = await loadFixture(deployFixture);
            await poolFactory.setPriceFeed(pool.address);
            await poolFactory.updateTokenConfig(ETH.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);

            expect(await pool.priceFeed()).to.eq(pool.address);
        });
    });

    describe("#sampleAndAdjustFundingRate", () => {
        it("should do nothing if time delta is less than 5 seconds", async () => {
            const {pool} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await time.setNextBlockTimestamp(nextHourBegin + 2);

            await expect(pool.sampleAndAdjustFundingRate()).to.not.emit(pool, "FundingRateGrowthAdjusted");

            {
                const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} =
                    await pool.globalFundingRateSample();
                expect(lastAdjustFundingRateTime).to.eq(nextHourBegin);
                expect(sampleCount).to.eq(0);
                expect(cumulativePremiumRateX96).to.eq(0);
            }
        });

        it("shouldn't update cumulativePremiumRateX96 if liquidity is zero", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await time.setNextBlockTimestamp(nextHourBegin + 5);

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await expect(pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 100n * 10n ** 18n)).to.not.emit(
                pool,
                "FundingRateGrowthAdjusted"
            );

            {
                const {lastAdjustFundingRateTime, sampleCount, cumulativePremiumRateX96} =
                    await pool.globalFundingRateSample();
                expect(lastAdjustFundingRateTime).to.eq(nextHourBegin);
                expect(sampleCount).to.eq(1);
                expect(cumulativePremiumRateX96).to.eq(0);
            }
        });

        it("should decrease longFundingRateGrowthX96 if funding rate is positive", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            {
                const {sampleCount, cumulativePremiumRateX96} = await pool.globalFundingRateSample();
                expect(sampleCount).to.eq(1);
                expect(cumulativePremiumRateX96).to.eq(0n);
            }

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);
            {
                const {sampleCount, cumulativePremiumRateX96} = await pool.globalFundingRateSample();
                expect(sampleCount).to.gte(2);
                expect(cumulativePremiumRateX96).to.gt(0n);
            }

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(pool.sampleAndAdjustFundingRate())
                .to.emit(pool, "FundingRateGrowthAdjusted")
                .withArgs(
                    (fundingRateDeltaX96: BigNumber) => fundingRateDeltaX96.gt(0n),
                    (longFundingRateGrowthAfterX96: BigNumber) => longFundingRateGrowthAfterX96.lt(0n),
                    (shortFundingRateGrowthAfterX96: BigNumber) => shortFundingRateGrowthAfterX96.gt(0n),
                    (lastAdjustFundingRateTimeAfter: BigNumber) =>
                        lastAdjustFundingRateTimeAfter.eq(nextHourBegin + 3600)
                );
        });

        it("should decrease shortFundingRateGrowthX96 if funding rate is negative", async () => {
            const {owner, pool, USDC, tokenCfg, fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.collectProtocolFee()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 100n * 10n ** 12n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 50n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 50n * 10n ** 18n, 6800n * 10n ** 18n);
            {
                const {sampleCount, cumulativePremiumRateX96} = await pool.globalFundingRateSample();
                expect(sampleCount).to.eq(1);
                expect(cumulativePremiumRateX96).to.eq(0n);
            }

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 50n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 50n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 1n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 1n * 10n ** 18n, 100n * 10n ** 18n);
            {
                const {sampleCount, cumulativePremiumRateX96} = await pool.globalFundingRateSample();
                expect(sampleCount).to.gte(2);
                expect(cumulativePremiumRateX96).to.lt(0n);
            }

            await time.setNextBlockTimestamp(nextHourBegin + 3600);

            {
                const globalLiquidityPosition = await pool.globalLiquidityPosition();
                const globalFundingRateSample = await pool.globalFundingRateSample();
                const priceState = await pool.priceState();
                expect(globalLiquidityPosition.side).to.eq(SIDE_LONG);
                expect(globalLiquidityPosition.liquidity).to.gt(0n);

                let premiumRateX96 = priceState.premiumRateX96.toBigInt();
                if (globalLiquidityPosition.liquidity.gt(priceState.maxPriceImpactLiquidity)) {
                    premiumRateX96 = mulDiv(
                        premiumRateX96,
                        priceState.maxPriceImpactLiquidity,
                        globalLiquidityPosition.liquidity,
                        Rounding.Up
                    );
                }

                premiumRateX96 = -premiumRateX96;
                expect(premiumRateX96).to.lt(0n);
                const cumulativeBalanceRateDeltaX96 =
                    premiumRateX96 *
                    (((BigInt(globalFundingRateSample.sampleCount) + 1n + 720n) *
                        (720n - BigInt(globalFundingRateSample.sampleCount))) >>
                        2n);
                const cumulativePremiumRateAfterX96 =
                    globalFundingRateSample.cumulativePremiumRateX96.add(cumulativeBalanceRateDeltaX96);
                let premiumRateAvgX96: bigint;
                if (cumulativePremiumRateAfterX96.gte(0)) {
                    premiumRateAvgX96 = mulDiv(
                        cumulativePremiumRateAfterX96,
                        1n,
                        PREMIUM_RATE_AVG_DENOMINATOR,
                        Rounding.Up
                    );
                } else {
                    premiumRateAvgX96 = -mulDiv(
                        cumulativePremiumRateAfterX96.abs(),
                        1n,
                        PREMIUM_RATE_AVG_DENOMINATOR,
                        Rounding.Up
                    );
                }
                expect(premiumRateAvgX96).to.lt(0n);
                const interestRateX96 = mulDiv(tokenCfg.interestRate, Q96, 100_000_000, Rounding.Up);
                expect(premiumRateAvgX96).to.lt(interestRateX96 - PREMIUM_RATE_CLAMP_BOUNDARY_X96);
                const rateDeltaX96 = interestRateX96 - premiumRateAvgX96;
                expect(rateDeltaX96).to.gt(PREMIUM_RATE_CLAMP_BOUNDARY_X96);
                const fundingRateDeltaX96 = premiumRateAvgX96 + PREMIUM_RATE_CLAMP_BOUNDARY_X96;
                expect(fundingRateDeltaX96).to.lt(0n);

                await fundingRateUtil.updatePosition(
                    globalLiquidityPosition.side,
                    globalLiquidityPosition.netSize,
                    globalLiquidityPosition.entryPriceX96,
                    globalLiquidityPosition.liquidity
                );
                await fundingRateUtil.updateSample(
                    globalFundingRateSample.lastAdjustFundingRateTime,
                    globalFundingRateSample.sampleCount,
                    globalFundingRateSample.cumulativePremiumRateX96
                );
                await fundingRateUtil.updatePriceState(priceState.maxPriceImpactLiquidity, priceState.premiumRateX96);
                await fundingRateUtil.samplePremiumRate(tokenCfg.interestRate, nextHourBegin + 3600);
                const shouldAdjustFundingRate = await fundingRateUtil.shouldAdjustFundingRate();
                const _fundingRateDeltaX96 = await fundingRateUtil.fundingRateDeltaX96();
                expect(shouldAdjustFundingRate).to.true;
                expect(_fundingRateDeltaX96).to.lt(0n);
            }

            const globalPosition = await pool.globalPosition();
            expect(globalPosition.longFundingRateGrowthX96).to.lt(0n);
            expect(globalPosition.shortFundingRateGrowthX96).to.eq(0n);
            await expect(pool.sampleAndAdjustFundingRate())
                .to.emit(pool, "FundingRateGrowthAdjusted")
                .withArgs(
                    (fundingRateDeltaX96: BigNumber) => fundingRateDeltaX96.lt(0n),
                    (longFundingRateGrowthAfterX96: BigNumber) => longFundingRateGrowthAfterX96.gt(0n),
                    (shortFundingRateGrowthAfterX96: BigNumber) => shortFundingRateGrowthAfterX96.lt(0n),
                    (lastAdjustFundingRateTimeAfter: BigNumber) =>
                        lastAdjustFundingRateTimeAfter.eq(nextHourBegin + 3600)
                );
        });

        it("should increase global riskBufferFund if opposite positions is empty", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.collectProtocolFee()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            {
                const {sampleCount, cumulativePremiumRateX96} = await pool.globalFundingRateSample();
                expect(sampleCount).to.eq(1);
                expect(cumulativePremiumRateX96).to.eq(0n);
            }

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            {
                const {sampleCount, cumulativePremiumRateX96} = await pool.globalFundingRateSample();
                expect(sampleCount).to.gte(2);
                expect(cumulativePremiumRateX96).to.gt(0n);
            }

            const {riskBufferFund} = await pool.globalRiskBufferFund();

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(pool.sampleAndAdjustFundingRate())
                .to.emit(pool, "GlobalRiskBufferFundChanged")
                .withArgs((n: BigNumber) => n.gt(riskBufferFund));
        });
    });

    describe("#collectProtocolFee", () => {
        it("should sample and adjust funding rate", async () => {
            const {owner, pool, USDC, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const assertion = expect(pool.collectProtocolFee());
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should reset protocol fee", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            expect(await pool.protocolFee()).to.gt(0n);
            await pool.collectProtocolFee();
            expect(await pool.protocolFee()).to.eq(0n);
        });

        it("should transfer protocol fee to fee distributor and update balance", async () => {
            const {owner, pool, USDC, feeDistributor} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const protocolFee = await pool.protocolFee();
            await expect(pool.collectProtocolFee()).changeTokenBalances(
                USDC,
                [pool.address, feeDistributor.address],
                [-protocolFee.toBigInt(), protocolFee.toBigInt()]
            );
        });

        it("should deposit protocol fee to fee distributor", async () => {
            const {owner, pool, USDC, feeDistributor} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const protocolFee = await pool.protocolFee();
            expect(await feeDistributor.balance()).to.eq(0n);
            await pool.collectProtocolFee();
            expect(await feeDistributor.balance()).to.eq(protocolFee);
        });

        it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(pool.collectProtocolFee()).to.emit(pool, "GlobalUnrealizedLossMetricsChanged");
        });

        it("should emit ProtocolFeeCollected event", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const protocolFee = await pool.protocolFee();
            await expect(pool.collectProtocolFee()).to.emit(pool, "ProtocolFeeCollected").withArgs(protocolFee);
        });
    });

    describe("#collectReferralFee", () => {
        it("should revert if caller is not a router", async () => {
            const {owner, other, pool, router} = await loadFixture(deployFixture);
            await expect(pool.connect(other).collectReferralFee(1001, owner.address))
                .to.revertedWithCustomError(pool, "InvalidCaller")
                .withArgs(router);
        });

        it("should sample and adjust funding rate", async () => {
            const {owner, pool, USDC, _fundingRateUtil} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const assertion = expect(pool.collectReferralFee(1001, owner.address));
            await assertion.to.emit(pool, "FundingRateGrowthAdjusted");
            await assertion.to.emit(_fundingRateUtil.attach(pool.address), "GlobalFundingRateSampleAdjusted");
        });

        it("should reset referral fee", async () => {
            const {owner, pool, USDC, efc} = await loadFixture(deployFixture);
            await efc.setRefereeTokens(owner.address, 10000);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            expect(await pool.referralFees(10000)).to.gt(0n);
            await pool.collectReferralFee(10000, owner.address);
            expect(await pool.referralFees(10000)).to.eq(0n);
        });

        it("should transfer referral fee to receiver and update balance", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const referralFee = await pool.referralFees(10000);
            await expect(pool.collectReferralFee(10000, owner.address)).changeTokenBalances(
                USDC,
                [pool.address, owner.address],
                [-referralFee.toBigInt(), referralFee.toBigInt()]
            );
        });

        it("should emit GlobalUnrealizedLossMetricsChanged event", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            await expect(pool.collectReferralFee(10000, owner.address)).to.emit(
                pool,
                "GlobalUnrealizedLossMetricsChanged"
            );
        });

        it("should emit ReferralFeeCollected event", async () => {
            const {owner, pool, USDC} = await loadFixture(deployFixture);
            const lastTimestamp = await time.latest();
            const nextHourBegin = lastTimestamp - (lastTimestamp % 3600) + 3600;
            await time.setNextBlockTimestamp(nextHourBegin);
            await expect(pool.sampleAndAdjustFundingRate()).to.emit(pool, "FundingRateGrowthAdjusted");

            await USDC.transfer(pool.address, 100n * 10n ** 18n);
            await pool.openLiquidityPosition(owner.address, 100n * 10n ** 18n, 20_000n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 5);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 10);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_LONG, 10n * 10n ** 18n, 100n * 10n ** 18n);
            await USDC.transfer(pool.address, 10n * 10n ** 18n);
            await pool.increasePosition(owner.address, SIDE_SHORT, 10n * 10n ** 18n, 100n * 10n ** 18n);

            await time.setNextBlockTimestamp(nextHourBegin + 3600);
            const referralFee = await pool.referralFees(10000);
            await expect(pool.collectReferralFee(10000, owner.address))
                .to.emit(pool, "ReferralFeeCollected")
                .withArgs(10000n, owner.address, referralFee);
        });
    });

    describe("#changePriceVertices", () => {
        it("should use the size and premiumRateX96 of the previous vertex if previous size is greater or previous premiumRateX96 is greater", async () => {
            const {owner, pool, USDC, tokenCfg} = await loadFixture(deployFixture);

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition);
            await pool.openLiquidityPosition(
                owner.address,
                tokenCfg.minMarginPerPosition,
                tokenCfg.minMarginPerPosition * 200n
            );

            await USDC.transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
            await pool.increasePosition(
                owner.address,
                SIDE_LONG,
                tokenCfg.minMarginPerPosition * 200n,
                tokenCfg.minMarginPerPosition * 200n
            );

            await pool.closeLiquidityPosition(1n, owner.address);

            const priceState = await pool.priceState();
            expect(priceState.priceVertices[2].size).to.eq(priceState.priceVertices[1].size);
            expect(priceState.priceVertices[2].premiumRateX96).to.eq(priceState.priceVertices[1].premiumRateX96);
            expect(priceState.priceVertices[3].size).to.eq(priceState.priceVertices[2].size);
            expect(priceState.priceVertices[3].premiumRateX96).to.eq(priceState.priceVertices[2].premiumRateX96);

            expect(priceState.priceVertices[4].size).to.gt(priceState.priceVertices[3].size);
            expect(priceState.priceVertices[4].premiumRateX96).to.gt(priceState.priceVertices[3].premiumRateX96);
            expect(priceState.priceVertices[5].size).to.gt(priceState.priceVertices[4].size);
            expect(priceState.priceVertices[5].premiumRateX96).to.gt(priceState.priceVertices[4].premiumRateX96);
            expect(priceState.priceVertices[6].size).to.gt(priceState.priceVertices[5].size);
            expect(priceState.priceVertices[6].premiumRateX96).to.gt(priceState.priceVertices[5].premiumRateX96);
        });

        it("should update the vertices in range (start, LATEST_VERTEX] if the vertex represented by end is the same as the vertex represented by end + 1", async () => {
            const {owner, other, other2, pool, ETH, USDC, mockPriceFeed, tokenCfg} = await loadFixture(deployFixture);
            await mockPriceFeed.setMinPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("1", DECIMALS_18, DECIMALS_6));
            {
                await USDC.transfer(pool.address, tokenCfg.minMarginPerLiquidityPosition * 50n);
                await pool.openLiquidityPosition(
                    owner.address,
                    tokenCfg.minMarginPerLiquidityPosition * 50n,
                    tokenCfg.minMarginPerLiquidityPosition * 50n
                );

                await USDC.mint(other2.address, tokenCfg.minMarginPerPosition * 200n);
                await USDC.connect(other2).transfer(pool.address, tokenCfg.minMarginPerPosition * 200n);
                await pool.increasePosition(
                    other2.address,
                    SIDE_LONG,
                    tokenCfg.minMarginPerPosition * 200n,
                    toPriceX96("1", DECIMALS_18, DECIMALS_6) * 200n
                );

                await USDC.mint(other.address, tokenCfg.minMarginPerPosition * 10n);
                await USDC.connect(other).transfer(pool.address, tokenCfg.minMarginPerPosition * 10n);
                await pool.openLiquidityPosition(
                    other.address,
                    tokenCfg.minMarginPerLiquidityPosition * 10n,
                    tokenCfg.minMarginPerLiquidityPosition * 10n
                );

                const {currentVertexIndex: startExclusive, pendingVertexIndex: endInclusive} = await pool.priceState();
                expect(startExclusive).to.eq(3);
                expect(endInclusive).to.eq(3);

                await mockPriceFeed.setMaxPriceX96(ETH.address, toPriceX96("0.5", DECIMALS_18, DECIMALS_6));
                const assertion = expect(
                    await pool.decreasePosition(
                        other2.address,
                        SIDE_LONG,
                        0n,
                        toPriceX96("1", DECIMALS_18, DECIMALS_6) * 200n,
                        other2.address
                    )
                );
                const {priceVertices: priceVerticesAfter} = await pool.priceState();

                await assertion.to
                    .emit(pool, "PriceVertexChanged")
                    .withArgs(4, priceVerticesAfter[4].size, priceVerticesAfter[4].premiumRateX96);
                await assertion.to
                    .emit(pool, "PriceVertexChanged")
                    .withArgs(5, priceVerticesAfter[5].size, priceVerticesAfter[5].premiumRateX96);
                await assertion.to
                    .emit(pool, "PriceVertexChanged")
                    .withArgs(6, priceVerticesAfter[6].size, priceVerticesAfter[6].premiumRateX96);
            }
        });
    });
});

async function _changePriceVertices(
    _priceState0: {
        maxPriceImpactLiquidity: BigNumber;
        premiumRateX96: BigNumber;
        pendingVertexIndex: number;
        liquidationVertexIndex: number;
        currentVertexIndex: number;
        priceVertices: IPool.PriceVertexStructOutput[];
        liquidationBufferNetSizes: BigNumber[];
    },
    _priceFeed: MockPriceFeed,
    _poolFactory: PoolFactory,
    _token: ERC20Test,
    _globalLiquidityPositionLiquidity: BigNumberish
) {
    let currentVertexIndex = _priceState0.currentVertexIndex;
    return await _changePriceVertex(
        _priceState0,
        _priceFeed,
        _poolFactory,
        _token,
        BigNumber.from(_globalLiquidityPositionLiquidity),
        currentVertexIndex,
        Number(LATEST_VERTEX)
    );
}

async function _changePriceVertex(
    _priceState0: {
        maxPriceImpactLiquidity: BigNumber;
        premiumRateX96: BigNumber;
        pendingVertexIndex: number;
        liquidationVertexIndex: number;
        currentVertexIndex: number;
        priceVertices: IPool.PriceVertexStructOutput[];
        liquidationBufferNetSizes: BigNumber[];
    },
    _priceFeed: MockPriceFeed,
    _poolFactory: PoolFactory,
    _token: ERC20Test,
    _globalLiquidityPositionLiquidity: BigNumber,
    _startExclusive: number,
    _endInclusive: number
) {
    const indexPriceX96 = await _priceFeed.getMaxPriceX96(_token.address);
    const liquidity = _globalLiquidityPositionLiquidity.gt(_priceState0.maxPriceImpactLiquidity)
        ? _priceState0.maxPriceImpactLiquidity
        : _globalLiquidityPositionLiquidity;
    let res: {vertexIndex: number; sizeAfter: BigNumber; premiumRateAfterX96: BigNumber}[] = [];
    for (let i = _startExclusive + 1; i <= _endInclusive; i++) {
        const {balanceRate, premiumRate} = await _poolFactory.tokenPriceVertexConfigs(_token.address, i);
        let {size: sizeAfter, premiumRateX96: premiumRateAfterX96} = _calculatePriceVertex(
            BigNumber.from(balanceRate),
            BigNumber.from(premiumRate),
            liquidity,
            indexPriceX96
        );

        if (i > 1) {
            const previous = _priceState0.priceVertices[i - 1];
            let previousSize = previous.size;
            let previousPremiumRateX96 = previous.premiumRateX96;
            if (i > _startExclusive + 1) {
                previousSize = res[i - _startExclusive - 2].sizeAfter;
                previousPremiumRateX96 = res[i - _startExclusive - 2].premiumRateAfterX96;
            }
            if (previousSize.gte(sizeAfter) || previousPremiumRateX96.gte(premiumRateAfterX96)) {
                sizeAfter = previousSize;
                premiumRateAfterX96 = previousPremiumRateX96;
            }
        }
        res.push({
            vertexIndex: i,
            sizeAfter: sizeAfter,
            premiumRateAfterX96: premiumRateAfterX96,
        });

        if (i == _endInclusive && _endInclusive < Number(LATEST_VERTEX)) {
            const next = _priceState0.priceVertices[i + 1];
            if (sizeAfter.gte(next.size) || premiumRateAfterX96.gte(next.premiumRateX96)) {
                _endInclusive = Number(LATEST_VERTEX);
            }
        }
    }
    return res;
}

function _calculatePriceVertex(
    _balanceRate: BigNumber,
    _premiumRate: BigNumber,
    _liquidity: BigNumber,
    _indexPriceX96: BigNumber
) {
    const balanceRateX64 = (Q96 * _balanceRate.toBigInt()) / BASIS_POINTS_DIVISOR;
    const size = BigNumber.from(mulDiv(balanceRateX64, _liquidity, _indexPriceX96));
    const premiumRateX96 = BigNumber.from((Q96 * _premiumRate.toBigInt()) / BASIS_POINTS_DIVISOR);
    return {
        size,
        premiumRateX96,
    };
}

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

function _splitFee(_tradingFee: BigNumberish, _feeRate: BigNumberish) {
    return BigNumber.from(_tradingFee).mul(_feeRate).div(BASIS_POINTS_DIVISOR);
}

async function _buildTradingFeeState(
    _efc: MockEFC,
    _tokenFeeRateCfg: {
        tradingFeeRate: bigint;
        referralReturnFeeRate: bigint;
        referralParentReturnFeeRate: bigint;
        referralDiscountRate: bigint;
    },
    _account: string
) {
    const {_memberTokenId: referralToken, _connectorTokenId: referralParentToken} = await _efc.referrerTokens(_account);
    let referralReturnFeeRate = 0n;
    let referralParentReturnFeeRate = 0n;
    let tradingFeeRate = 0n;
    if (referralToken.eq(0n)) {
        tradingFeeRate = _tokenFeeRateCfg.tradingFeeRate;
    } else {
        tradingFeeRate = mulDiv(
            _tokenFeeRateCfg.tradingFeeRate,
            _tokenFeeRateCfg.referralDiscountRate,
            BASIS_POINTS_DIVISOR,
            Rounding.Up
        );
        referralReturnFeeRate = _tokenFeeRateCfg.referralReturnFeeRate;
        referralParentReturnFeeRate = _tokenFeeRateCfg.referralParentReturnFeeRate;
    }
    return {
        tradingFeeRate,
        referralReturnFeeRate,
        referralParentReturnFeeRate,
        referralToken,
        referralParentToken,
    };
}

async function _adjustGlobalLiquidityPosition(
    contracts: {
        liquidityPositionUtil: LiquidityPositionUtilTest;
        positionUtil: PositionUtilTest;
        priceUtil: PriceUtilTest;
    },
    tokenFeeRateCfg: {
        liquidityFeeRate: bigint;
        protocolFeeRate: bigint;
    },
    globalRiskBufferFund: {
        riskBufferFund: BigNumber;
        liquidity: BigNumber;
    },
    globalLiquidityPosition: {
        netSize: BigNumber;
        liquidationBufferNetSize: BigNumber;
        entryPriceX96: BigNumber;
        side: number;
        liquidity: BigNumber;
        realizedProfitGrowthX64: BigNumber;
    },
    tradingFeeState: {
        tradingFeeRate: bigint;
        referralReturnFeeRate: bigint;
        referralParentReturnFeeRate: bigint;
        referralToken: BigNumber;
        referralParentToken: BigNumber;
    },
    side: Side,
    tradePriceX96: BigNumber,
    sizeDelta: BigNumberish,
    riskBufferFundDelta: BigNumberish
) {
    const {realizedPnL, entryPriceAfterX96} =
        await contracts.liquidityPositionUtil.calculateRealizedPnLAndNextEntryPriceX96(
            globalLiquidityPosition,
            side,
            tradePriceX96,
            sizeDelta
        );
    // _calculateFee
    const tradingFee = await contracts.positionUtil.calculateTradingFee(
        sizeDelta,
        tradePriceX96,
        tradingFeeState.tradingFeeRate
    );
    const liquidityFee = _splitFee(tradingFee, tokenFeeRateCfg.liquidityFeeRate);
    const protocolFee = _splitFee(tradingFee, tokenFeeRateCfg.protocolFeeRate);
    let riskBufferFundFee = tradingFee.sub(liquidityFee).sub(protocolFee);
    let referralFee = BigNumber.from(0n);
    let referralParentFee = BigNumber.from(0n);
    if (tradingFeeState.referralToken.gt(0n)) {
        referralFee = _splitFee(tradingFee, tradingFeeState.referralReturnFeeRate);
        referralParentFee = _splitFee(tradingFee, tradingFeeState.referralParentReturnFeeRate);
        riskBufferFundFee = riskBufferFundFee.sub(referralFee.add(referralParentFee));
    }

    const riskBufferFundRealizedPnLDelta = BigNumber.from(riskBufferFundDelta).add(realizedPnL).add(riskBufferFundFee);
    const riskBufferFundAfter = globalRiskBufferFund.riskBufferFund.add(riskBufferFundRealizedPnLDelta);
    const realizedProfitGrowthAfterX64 = globalLiquidityPosition.realizedProfitGrowthX64.add(
        mulDiv(liquidityFee, Q64, globalLiquidityPosition.liquidity)
    );
    return {
        realizedPnL,
        entryPriceAfterX96,
        tradingFee,
        liquidityFee,
        protocolFee,
        referralFee,
        referralParentFee,
        riskBufferFundFee,
        riskBufferFundRealizedPnLDelta,
        riskBufferFundAfter,
        realizedProfitGrowthAfterX64,
    };
}
