import {ethers} from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {computePoolAddress, initializePoolByteCode} from "./shared/address";
import {concatPoolCreationCode} from "./shared/creationCode";
import {ERC20Test} from "../typechain-types";
import {DECIMALS_18, DECIMALS_6, LATEST_VERTEX, toPriceX96} from "./shared/Constants";
import {newTokenConfig, newTokenFeeRateConfig, newTokenPriceConfig} from "./shared/tokenConfig";

describe("PoolFactory", () => {
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

    describe("Configurable", () => {
        describe("#enableToken", () => {
            it("should revert if caller is not gov", async () => {
                const {other, poolFactory} = await loadFixture(deployFixture);
                await expect(
                    poolFactory
                        .connect(other)
                        .enableToken(
                            ethers.constants.AddressZero,
                            newTokenConfig(),
                            newTokenFeeRateConfig(),
                            newTokenPriceConfig()
                        )
                ).to.revertedWithCustomError(poolFactory, "Forbidden");
            });

            it("should revert if token already enabled", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                await poolFactory.enableToken(
                    router.address,
                    newTokenConfig(),
                    newTokenFeeRateConfig(),
                    newTokenPriceConfig()
                );
                await expect(
                    poolFactory.enableToken(
                        router.address,
                        newTokenConfig(),
                        newTokenFeeRateConfig(),
                        newTokenPriceConfig()
                    )
                ).to.revertedWithCustomError(poolFactory, "TokenAlreadyEnabled");
            });

            it("should emit event", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await expect(poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.emit(poolFactory, "TokenConfigChanged")
                    .withArgs(
                        router.address,
                        [
                            tokenCfg.minMarginPerLiquidityPosition,
                            tokenCfg.maxRiskRatePerLiquidityPosition,
                            tokenCfg.maxLeveragePerLiquidityPosition,
                            tokenCfg.minMarginPerPosition,
                            tokenCfg.maxLeveragePerPosition,
                            tokenCfg.liquidationFeeRatePerPosition,
                            tokenCfg.liquidationExecutionFee,
                            tokenCfg.interestRate,
                            tokenCfg.maxFundingRate,
                        ],
                        [
                            tokenFeeRateCfg.tradingFeeRate,
                            tokenFeeRateCfg.liquidityFeeRate,
                            tokenFeeRateCfg.protocolFeeRate,
                            tokenFeeRateCfg.referralReturnFeeRate,
                            tokenFeeRateCfg.referralParentReturnFeeRate,
                            tokenFeeRateCfg.referralDiscountRate,
                        ],
                        (priceCfg: any) => {
                            expect(priceCfg.maxPriceImpactLiquidity).to.eq(priceCfg.maxPriceImpactLiquidity);
                            expect(priceCfg.liquidationVertexIndex).to.eq(priceCfg.liquidationVertexIndex);
                            let i = 0;
                            for (const v of priceCfg.vertices) {
                                expect(v.balanceRate).to.eq(tokenPriceCfg.vertices[i].balanceRate);
                                expect(v.premiumRate).to.eq(tokenPriceCfg.vertices[i].premiumRate);
                                i++;
                            }
                            return true;
                        }
                    );
            });
        });

        describe("#isEnabledToken", () => {
            it("should pass", async () => {
                const {poolFactory, router, feeDistributor} = await loadFixture(deployFixture);
                await poolFactory.enableToken(
                    router.address,
                    newTokenConfig(),
                    newTokenFeeRateConfig(),
                    newTokenPriceConfig()
                );
                expect(await poolFactory.isEnabledToken(router.address)).to.true;
                expect(await poolFactory.isEnabledToken(feeDistributor.address)).to.false;
            });
        });

        describe("#updateTokenConfig", () => {
            it("should revert if caller is not gov", async () => {
                const {other, poolFactory} = await loadFixture(deployFixture);
                await expect(
                    poolFactory
                        .connect(other)
                        .updateTokenConfig(
                            ethers.constants.AddressZero,
                            newTokenConfig(),
                            newTokenFeeRateConfig(),
                            newTokenPriceConfig()
                        )
                ).to.revertedWithCustomError(poolFactory, "Forbidden");
            });

            it("should revert if token not enabled", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                await expect(
                    poolFactory.updateTokenConfig(
                        router.address,
                        newTokenConfig(),
                        newTokenFeeRateConfig(),
                        newTokenPriceConfig()
                    )
                ).to.revertedWithCustomError(poolFactory, "TokenNotEnabled");
            });

            it("should revert if max risk rate per liquidity position is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenCfg.maxRiskRatePerLiquidityPosition = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidMaxRiskRatePerLiquidityPosition");
            });

            it("should revert if max leverage per liquidity position is zero", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenCfg.maxLeveragePerLiquidityPosition = 0n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidMaxLeveragePerLiquidityPosition");
            });

            it("should revert if max leverage per position is zero", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenCfg.maxLeveragePerPosition = 0n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidMaxLeveragePerPosition");
            });

            it("should revert if liquidation fee rate per position is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenCfg.liquidationFeeRatePerPosition = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidLiquidationFeeRatePerPosition");
            });

            it("should revert if interest rate is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenCfg.interestRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidInterestRate");
            });

            it("should revert if max funding rate is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenCfg.maxFundingRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidMaxFundingRate");
            });

            it("should revert if trading fee rate is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenFeeRateCfg.tradingFeeRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidTradingFeeRate");
            });

            it("should revert if liquidity fee rate is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenFeeRateCfg.liquidityFeeRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidLiquidityFeeRate");
            });

            it("should revert if protocol fee rate is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenFeeRateCfg.protocolFeeRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidProtocolFeeRate");
            });

            it("should revert if referral return fee rate is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenFeeRateCfg.referralReturnFeeRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidReferralReturnFeeRate");
            });

            it("should revert if referral parent return fee rate is greater than 0000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenFeeRateCfg.referralParentReturnFeeRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidReferralParentReturnFeeRate");
            });

            it("should revert if referral discount rate is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenFeeRateCfg.referralDiscountRate = 100000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidReferralDiscountRate");
            });

            it("should revert if the sum of liquidity fee rate and protocol fee rate and referral return fee rate and referral parent return fee is greater than 100000000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenFeeRateCfg.referralReturnFeeRate = 20000001n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidFeeRate");
            });

            it("should revert if max price impact liquidity is zero", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.maxPriceImpactLiquidity = 0n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidMaxPriceImpactLiquidity");
            });

            it("should revert if the length of vertices is not equal to VERTEX_NUM", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.vertices = tokenPriceCfg.vertices.slice(1);
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidVerticesLength");
            });

            it("should revert if liquidation vertex index is greater than LATEST_VERTEX", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.liquidationVertexIndex = LATEST_VERTEX + 1n;
                await expect(
                    poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg)
                ).to.revertedWithCustomError(poolFactory, "InvalidLiquidationVertexIndex");
            });

            it("should revert if the first vertex is not (0,0)", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.vertices[0].balanceRate = 1n;
                await expect(poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.revertedWithCustomError(poolFactory, "InvalidVertex")
                    .withArgs(0n);
                tokenPriceCfg.vertices[0].balanceRate = 0n;
                tokenPriceCfg.vertices[0].premiumRate = 1n;
                await expect(poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.revertedWithCustomError(poolFactory, "InvalidVertex")
                    .withArgs(0n);
            });

            it("should revert if the previous balance rate is greater than the current", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.vertices[1].balanceRate = tokenPriceCfg.vertices[2].balanceRate + 1n;
                await expect(poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.revertedWithCustomError(poolFactory, "InvalidVertex")
                    .withArgs(2n);
            });

            it("should revert if the previous premium rate is greater than the current", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.vertices[2].premiumRate = tokenPriceCfg.vertices[3].premiumRate + 1n;
                await expect(poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.revertedWithCustomError(poolFactory, "InvalidVertex")
                    .withArgs(3n);
            });

            it("should revert if the balance rate is greater than 100_000_000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.vertices[6].balanceRate = 100_000_001n;
                await expect(poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.revertedWithCustomError(poolFactory, "InvalidVertex")
                    .withArgs(6n);
            });

            it("should revert if the premium rate is greater than 100_000_000", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                tokenPriceCfg.vertices[6].premiumRate = 100_000_001n;
                await expect(poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.revertedWithCustomError(poolFactory, "InvalidVertex")
                    .withArgs(6n);
            });

            it("should emit event", async () => {
                const {poolFactory, router} = await loadFixture(deployFixture);
                const tokenCfg = newTokenConfig();
                const tokenFeeRateCfg = newTokenFeeRateConfig();
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg);
                await expect(poolFactory.updateTokenConfig(router.address, tokenCfg, tokenFeeRateCfg, tokenPriceCfg))
                    .to.emit(poolFactory, "TokenConfigChanged")
                    .withArgs(
                        router.address,
                        [
                            tokenCfg.minMarginPerLiquidityPosition,
                            tokenCfg.maxRiskRatePerLiquidityPosition,
                            tokenCfg.maxLeveragePerLiquidityPosition,
                            tokenCfg.minMarginPerPosition,
                            tokenCfg.maxLeveragePerPosition,
                            tokenCfg.liquidationFeeRatePerPosition,
                            tokenCfg.liquidationExecutionFee,
                            tokenCfg.interestRate,
                            tokenCfg.maxFundingRate,
                        ],
                        [
                            tokenFeeRateCfg.tradingFeeRate,
                            tokenFeeRateCfg.liquidityFeeRate,
                            tokenFeeRateCfg.protocolFeeRate,
                            tokenFeeRateCfg.referralReturnFeeRate,
                            tokenFeeRateCfg.referralParentReturnFeeRate,
                            tokenFeeRateCfg.referralDiscountRate,
                        ],
                        (priceCfg: any) => {
                            expect(priceCfg.maxPriceImpactLiquidity).to.eq(priceCfg.maxPriceImpactLiquidity);
                            expect(priceCfg.liquidationVertexIndex).to.eq(priceCfg.liquidationVertexIndex);
                            let i = 0;
                            for (const v of priceCfg.vertices) {
                                expect(v.balanceRate).to.eq(tokenPriceCfg.vertices[i].balanceRate);
                                expect(v.premiumRate).to.eq(tokenPriceCfg.vertices[i].premiumRate);
                                i++;
                            }
                            return true;
                        }
                    );
            });
        });

        describe("#afterTokenConfigChanged", () => {
            it("should be invoked when updateTokenConfig called successfully", async () => {
                const {poolFactory, USD, ETH, Pool} = await loadFixture(deployFixture);
                const tokenPriceCfg = newTokenPriceConfig();
                await poolFactory.enableToken(ETH.address, newTokenConfig(), newTokenFeeRateConfig(), tokenPriceCfg);
                await poolFactory.createPool(ETH.address);
                tokenPriceCfg.maxPriceImpactLiquidity = tokenPriceCfg.maxPriceImpactLiquidity + 1n;
                await poolFactory.updateTokenConfig(
                    ETH.address,
                    newTokenConfig(),
                    newTokenFeeRateConfig(),
                    tokenPriceCfg
                );
                const poolAddress = computePoolAddress(poolFactory.address, ETH.address, USD.address);
                expect(poolAddress).to.not.eq(ethers.constants.AddressZero);

                const pool = Pool.attach(poolAddress);
                const priceState = await pool.priceState();
                expect(priceState.maxPriceImpactLiquidity).to.eq(tokenPriceCfg.maxPriceImpactLiquidity);
            });
        });
    });

    describe("#setPriceFeed", () => {
        it("should revert if caller is not gov", async () => {
            const {poolFactory, other} = await loadFixture(deployFixture);
            await expect(
                poolFactory.connect(other).setPriceFeed(ethers.constants.AddressZero)
            ).to.revertedWithCustomError(poolFactory, "Forbidden");
        });

        it("should pass", async () => {
            const {poolFactory, other} = await loadFixture(deployFixture);
            await poolFactory.setPriceFeed(other.address);

            expect(await poolFactory.priceFeed()).to.eq(other.address);
        });
    });

    describe("#createPool", () => {
        it("should revert if caller is not gov", async () => {
            const {other, poolFactory, router} = await loadFixture(deployFixture);
            await expect(poolFactory.connect(other).createPool(router.address)).to.revertedWithCustomError(
                poolFactory,
                "Forbidden"
            );
        });

        it("should revert if token not enabled", async () => {
            const {poolFactory, router} = await loadFixture(deployFixture);
            await expect(poolFactory.createPool(router.address)).to.revertedWithCustomError(
                poolFactory,
                "TokenNotEnabled"
            );
        });

        it("should revert if pool already exists", async () => {
            const {poolFactory, router} = await loadFixture(deployFixture);
            await poolFactory.enableToken(
                router.address,
                newTokenConfig(),
                newTokenFeeRateConfig(),
                newTokenPriceConfig()
            );
            await poolFactory.createPool(router.address);
            await expect(poolFactory.createPool(router.address)).to.revertedWithCustomError(
                poolFactory,
                "PoolAlreadyExists"
            );
        });

        it("should emit event", async () => {
            const {poolFactory, ETH, USD} = await loadFixture(deployFixture);
            await poolFactory.enableToken(
                ETH.address,
                newTokenConfig(),
                newTokenFeeRateConfig(),
                newTokenPriceConfig()
            );
            await expect(poolFactory.createPool(ETH.address))
                .to.emit(poolFactory, "PoolCreated")
                .withArgs(computePoolAddress(poolFactory.address, ETH.address, USD.address), ETH.address, USD.address);
        });
    });

    describe("#pools", () => {
        it("should pass", async () => {
            const {poolFactory, router, USD} = await loadFixture(deployFixture);
            await poolFactory.enableToken(
                router.address,
                newTokenConfig(),
                newTokenFeeRateConfig(),
                newTokenPriceConfig()
            );
            await poolFactory.createPool(router.address);
            expect(await poolFactory.pools(router.address)).to.eq(
                computePoolAddress(poolFactory.address, router.address, USD.address)
            );
            expect(await poolFactory.pools(USD.address)).to.eq(ethers.constants.AddressZero);
        });
    });

    describe("#changeGov", () => {
        it("sender should be gov and admin", async () => {
            const {gov, poolFactory} = await loadFixture(deployFixture);
            expect(await poolFactory.gov()).to.eq(gov.address);
            expect(await poolFactory.hasRole(poolFactory.DEFAULT_ADMIN_ROLE(), gov.address)).to.true;
        });

        it("previous gov should not be gov and admin", async () => {
            const {gov, other, poolFactory, router} = await loadFixture(deployFixture);
            await poolFactory.changeGov(other.address);
            const assertion = expect(await poolFactory.connect(other).acceptGov());
            await assertion.to.emit(poolFactory, "GovChanged").withArgs(gov.address, other.address);
            await assertion.to
                .emit(poolFactory, "RoleRevoked")
                .withArgs(await poolFactory.DEFAULT_ADMIN_ROLE(), gov.address, other.address);
            await assertion.to
                .emit(poolFactory, "RoleGranted")
                .withArgs(await poolFactory.DEFAULT_ADMIN_ROLE(), other.address, other.address);

            expect(await poolFactory.gov()).to.eq(other.address);
            await expect(
                poolFactory.enableToken(
                    router.address,
                    newTokenConfig(),
                    newTokenFeeRateConfig(),
                    newTokenPriceConfig()
                )
            ).to.revertedWithCustomError(poolFactory, "Forbidden");
            await expect(
                poolFactory
                    .connect(other)
                    .enableToken(router.address, newTokenConfig(), newTokenFeeRateConfig(), newTokenPriceConfig())
            ).to.not.reverted;
        });
    });
});
