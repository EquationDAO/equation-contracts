import {loadFixture, time} from "@nomicfoundation/hardhat-network-helpers";
import {ethers, network} from "hardhat";
import {expect} from "chai";
import {ERC20Test} from "../../typechain-types";
import {BigNumber, BigNumberish} from "ethers";

const zeroAddress = "0x0000000000000000000000000000000000000000";
describe("PriceFeed", () => {
    const tokenDecimals = 18n;
    const usdDecimals = 6n;
    const refPriceDecimals = 8n;

    function toPriceX96(
        price: BigNumberish,
        tokenDecimals: BigNumberish,
        usdDecimals: BigNumberish,
        refPriceDecimals: BigNumberish
    ): bigint {
        return BigNumber.from(price)
            .mul(BigNumber.from(10).pow(refPriceDecimals))
            .mul(BigNumber.from(2).pow(96))
            .div(BigNumber.from(10).pow(tokenDecimals))
            .mul(BigNumber.from(10).pow(usdDecimals))
            .div(BigNumber.from(10).pow(refPriceDecimals))
            .toBigInt();
    }

    async function deployPriceFeedFixture() {
        const [owner] = await ethers.getSigners();
        const ERC20 = await ethers.getContractFactory("ERC20Test");
        const usdc = (await ERC20.deploy("USDC", "USDC", usdDecimals, 100000000000000000000000n)) as ERC20Test;
        await usdc.deployed();

        const weth = (await ERC20.deploy("WETH", "WETH", tokenDecimals, 100000000000000000000000n)) as ERC20Test;
        await weth.deployed();

        const mockStableTokenPriceFeedFactory = await ethers.getContractFactory("MockChainLinkPriceFeed");
        const mockStableTokenPriceFeed = await mockStableTokenPriceFeedFactory.deploy();
        await mockStableTokenPriceFeed.deployed();
        const latestBlockTimestamp = await time.latest();
        await mockStableTokenPriceFeed.setRoundData(
            99,
            1n * 10n ** refPriceDecimals,
            latestBlockTimestamp,
            latestBlockTimestamp,
            99
        );

        const priceFeedFactory = await ethers.getContractFactory("PriceFeed");
        const priceFeed = await priceFeedFactory.deploy(mockStableTokenPriceFeed.address, 0);
        await priceFeed.deployed();
        await priceFeed.setUpdater(owner.address, true);
        await priceFeed.setMaxCumulativeDeltaDiffs(weth.address, 100 * 1000);

        const mockRefPriceFeedFactory = await ethers.getContractFactory("MockChainLinkPriceFeed");
        const mockRefPriceFeed = await mockRefPriceFeedFactory.deploy();
        await mockRefPriceFeed.deployed();

        const sequencerUptimeFeed = await mockRefPriceFeedFactory.deploy();
        await sequencerUptimeFeed.deployed();
        return {priceFeed, mockRefPriceFeed, usdc, weth, sequencerUptimeFeed, mockStableTokenPriceFeed};
    }

    describe("setter and getter", () => {
        it("setter and getter should work correctly", async () => {
            const {priceFeed, mockRefPriceFeed, usdc, weth} = await loadFixture(deployPriceFeedFixture);
            const [, newUpdater, noAccessUser] = await ethers.getSigners();

            await priceFeed.setRefHeartbeatDuration(usdc.address, 300);
            await expect((await priceFeed.tokenConfigs(usdc.address)).refHeartbeatDuration).to.be.eq(300);
            await expect((await priceFeed.tokenConfigs(weth.address)).refHeartbeatDuration).to.be.eq(0);

            await priceFeed.setRefPriceFeed(usdc.address, mockRefPriceFeed.address);
            await expect((await priceFeed.tokenConfigs(usdc.address)).refPriceFeed).to.be.eq(mockRefPriceFeed.address);
            await expect((await priceFeed.tokenConfigs(weth.address)).refPriceFeed).to.be.eq(zeroAddress);

            await priceFeed.setMaxCumulativeDeltaDiffs(usdc.address, 30000);
            await expect((await priceFeed.tokenConfigs(usdc.address)).maxCumulativeDeltaDiff).to.be.eq(30000);
            await expect((await priceFeed.tokenConfigs(weth.address)).maxCumulativeDeltaDiff).to.be.eq(100000);

            await priceFeed.setCumulativeRoundDuration(1234);
            await priceFeed.setMaxDeviationRatio(100);
            await priceFeed.setRefPriceExtraSample(3);

            const {cumulativeRoundDuration, maxDeviationRatio, refPriceExtraSample} = await priceFeed.slot();
            expect(cumulativeRoundDuration).to.be.eq(1234);
            expect(maxDeviationRatio).to.be.eq(100);
            expect(refPriceExtraSample).to.be.eq(3);

            await priceFeed.setUpdater(newUpdater.address, true);
            await expect(await priceFeed.isUpdater(newUpdater.address)).to.be.eq(true);
            await expect(await priceFeed.isUpdater(noAccessUser.address)).to.be.eq(false);

            await expect(
                priceFeed.connect(noAccessUser).setRefHeartbeatDuration(usdc.address, 300)
            ).to.be.revertedWithCustomError(priceFeed, "Forbidden");
            await expect(
                priceFeed.connect(noAccessUser).setRefPriceFeed(usdc.address, mockRefPriceFeed.address)
            ).to.be.revertedWithCustomError(priceFeed, "Forbidden");
            await expect(
                priceFeed.connect(noAccessUser).setMaxCumulativeDeltaDiffs(usdc.address, 30000)
            ).to.be.revertedWithCustomError(priceFeed, "Forbidden");
            await expect(
                priceFeed.connect(noAccessUser).setCumulativeRoundDuration(1234)
            ).to.be.revertedWithCustomError(priceFeed, "Forbidden");
            await expect(priceFeed.connect(noAccessUser).setMaxDeviationRatio(100)).to.be.revertedWithCustomError(
                priceFeed,
                "Forbidden"
            );
            await expect(priceFeed.connect(noAccessUser).setRefPriceExtraSample(3)).to.be.revertedWithCustomError(
                priceFeed,
                "Forbidden"
            );
            await expect(
                priceFeed.connect(noAccessUser).setUpdater(newUpdater.address, true)
            ).to.be.revertedWithCustomError(priceFeed, "Forbidden");
        });
    });

    describe("price feed config test", () => {
        it("should revert with 'RefReference price feed not set'", async () => {
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: 1,
                        },
                    ],
                    latestBlockTimestamp
                )
            ).to.be.revertedWithCustomError(priceFeed, "ReferencePriceFeedNotSet");

            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(100, 179070000000, 1684331747, 1684331747, 100);
        });

        it("should revert with 'Reference price out of range'", async () => {
            const latestBlockTimestamp = await time.latest();
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(100, -179070000000, 1684331747, 1684331747, 100);
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: 1,
                        },
                    ],
                    latestBlockTimestamp
                )
            ).to.be.revertedWithCustomError(priceFeed, "InvalidReferencePrice");
            await mockRefPriceFeed.setRoundData(
                101,
                1461501637330902918203684832716283019655932542977n,
                1684331747,
                1684331747,
                101
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: 1,
                        },
                    ],
                    latestBlockTimestamp
                )
            ).to.be.revertedWithCustomError(priceFeed, "SafeCastOverflowedUintDowncast");
        });

        it("should revert with 'Reference price feed exceed'", async () => {
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            const heartbeatDuration = 300;
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                100,
                latestBlockTimestamp - heartbeatDuration,
                latestBlockTimestamp - heartbeatDuration,
                100
            );
            await priceFeed.setRefHeartbeatDuration(weth.address, heartbeatDuration);
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: 1,
                        },
                    ],
                    latestBlockTimestamp
                )
            ).to.be.revertedWithCustomError(priceFeed, "ReferencePriceTimeout");
        });

        it("the difference between price and refPrice is greater than maxDeviationRatio", async () => {
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            const preCalculated = await priceFeed.calculatePriceX96s([
                {
                    token: weth.address,
                    priceX96: toPriceX96("111", tokenDecimals, usdDecimals, refPriceDecimals),
                },
            ]);
            await expect(preCalculated.maxPriceX96s[0]).to.be.eq(
                toPriceX96("111", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(preCalculated.minPriceX96s[0]).to.be.eq(
                toPriceX96("100", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("111", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("111", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("100", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("111", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("111", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("100", tokenDecimals, usdDecimals, refPriceDecimals)
            );
        });

        it("the difference between price and refPrice is not greater than maxDeviationRatio", async () => {
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            const preCalculated = await priceFeed.calculatePriceX96s([
                {
                    token: weth.address,
                    priceX96: toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals),
                },
            ]);
            await expect(preCalculated.maxPriceX96s[0]).to.be.eq(
                toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(preCalculated.minPriceX96s[0]).to.be.eq(
                toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("110", tokenDecimals, usdDecimals, refPriceDecimals)
            );
        });

        it("price change to apply maxCumulativeDeltaDiffs", async () => {
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setCumulativeRoundDuration(3600 * 24 * 7);
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            const preCalculated = await priceFeed.calculatePriceX96s([
                {
                    token: weth.address,
                    priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                },
            ]);
            await expect(preCalculated.maxPriceX96s[0]).to.be.eq(
                toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(preCalculated.minPriceX96s[0]).to.be.eq(
                toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp - 1
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await mockRefPriceFeed.setRoundData(
                101,
                99n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                101
            );
            const preCalculated2 = await priceFeed.calculatePriceX96s([
                {
                    token: weth.address,
                    priceX96: toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                },
            ]);
            await expect(preCalculated2.maxPriceX96s[0]).to.be.eq(
                toPriceX96("99", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(preCalculated2.minPriceX96s[0]).to.be.eq(
                toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],

                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("99", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("99", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals)
            );
        });

        it("refPriceExtraSample test", async () => {
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await priceFeed.setRefPriceExtraSample(1);
            await mockRefPriceFeed.setRoundData(
                99,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                99
            );
            await mockRefPriceFeed.setRoundData(
                100,
                102n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            await priceFeed.setPriceX96s(
                [
                    {
                        token: weth.address,
                        priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    },
                ],
                latestBlockTimestamp - 1
            );
            await mockRefPriceFeed.setRoundData(
                101,
                99n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                101
            );
            const preCalculated = await priceFeed.calculatePriceX96s([
                {
                    token: weth.address,
                    priceX96: toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                },
            ]);
            await expect(preCalculated.maxPriceX96s[0]).to.be.eq(
                toPriceX96("102", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(preCalculated.minPriceX96s[0]).to.be.eq(
                toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("102", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("102", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals)
            );
        });

        it("updateTxTimeout test", async () => {
            const {priceFeed, mockRefPriceFeed, weth} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await priceFeed.setRefPriceExtraSample(1);
            await mockRefPriceFeed.setRoundData(
                99,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                99
            );
            await mockRefPriceFeed.setRoundData(
                100,
                102n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await mockRefPriceFeed.setRoundData(
                101,
                99n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                101
            );
            const preCalculated = await priceFeed.calculatePriceX96s([
                {
                    token: weth.address,
                    priceX96: toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                },
            ]);
            await expect(preCalculated.maxPriceX96s[0]).to.be.eq(
                toPriceX96("102", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(preCalculated.minPriceX96s[0]).to.be.eq(
                toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp + 1
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("102", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("102", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("90", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            ).not.emit(priceFeed, "PriceUpdated");
        });

        it("expired price can not be updated", async () => {
            const {priceFeed, mockRefPriceFeed, weth, usdc} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await priceFeed.setRefPriceFeed(usdc.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                102n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
                );

            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            ).not.emit(priceFeed, "PriceUpdated");

            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp + 1
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals)
                );

            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: usdc.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    usdc.address,
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
                );
        });

        it("different token price can be updated in two txs within 1 second", async () => {
            const {priceFeed, mockRefPriceFeed, weth, usdc} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await network.provider.send("evm_setAutomine", [false]);
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await priceFeed.setRefPriceFeed(usdc.address, mockRefPriceFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                102n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            await network.provider.send("evm_setAutomine", [false]);
            await priceFeed.setPriceX96s(
                [
                    {
                        token: weth.address,
                        priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    },
                ],
                latestBlockTimestamp
            );
            await priceFeed.setPriceX96s(
                [
                    {
                        token: weth.address,
                        priceX96: toPriceX96("999", tokenDecimals, usdDecimals, refPriceDecimals),
                    },
                ],
                latestBlockTimestamp + 1
            );

            await network.provider.send("evm_setAutomine", [true]);
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: usdc.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    usdc.address,
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp + 1
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("108", tokenDecimals, usdDecimals, refPriceDecimals)
                );
        });

        it("should revert with `SequencerDown` if sequencer is down", async () => {
            const {priceFeed, mockRefPriceFeed, weth, sequencerUptimeFeed} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setCumulativeRoundDuration(3600 * 24 * 7);
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await priceFeed.setSequencerUptimeFeed(sequencerUptimeFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            await sequencerUptimeFeed.setRoundData(100, 1, 0, 0, 100);
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp - 1
                )
            ).revertedWithCustomError(priceFeed, "SequencerDown");
            await expect(priceFeed.getMinPriceX96(weth.address)).revertedWithCustomError(priceFeed, "SequencerDown");
            await expect(priceFeed.getMaxPriceX96(weth.address)).revertedWithCustomError(priceFeed, "SequencerDown");
        });

        it("should revert with `GracePeriodNotOver` if sequencer is just started few minutes ago", async () => {
            const {priceFeed, mockRefPriceFeed, weth, sequencerUptimeFeed} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setCumulativeRoundDuration(3600 * 24 * 7);
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await priceFeed.setSequencerUptimeFeed(sequencerUptimeFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            await sequencerUptimeFeed.setRoundData(100, 0, latestBlockTimestamp - 1700, 0, 100);
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp - 1
                )
            ).revertedWithCustomError(priceFeed, "GracePeriodNotOver");

            await expect(priceFeed.getMinPriceX96(weth.address)).revertedWithCustomError(
                priceFeed,
                "GracePeriodNotOver"
            );
            await expect(priceFeed.getMaxPriceX96(weth.address)).revertedWithCustomError(
                priceFeed,
                "GracePeriodNotOver"
            );
        });

        it("should work well if sequencer is up", async () => {
            const {priceFeed, mockRefPriceFeed, weth, sequencerUptimeFeed} = await loadFixture(deployPriceFeedFixture);
            const latestBlockTimestamp = await time.latest();
            await priceFeed.setCumulativeRoundDuration(3600 * 24 * 7);
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            await priceFeed.setSequencerUptimeFeed(sequencerUptimeFeed.address);
            await mockRefPriceFeed.setRoundData(
                100,
                100n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            await sequencerUptimeFeed.setRoundData(100, 0, latestBlockTimestamp - 2000, 0, 100);
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp - 1
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
                );

            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("109", tokenDecimals, usdDecimals, refPriceDecimals)
            );
        });

        it("should set right price if stable token price is not $1", async () => {
            const {priceFeed, mockRefPriceFeed, weth, mockStableTokenPriceFeed} = await loadFixture(
                deployPriceFeedFixture
            );
            await priceFeed.setRefPriceFeed(weth.address, mockRefPriceFeed.address);
            const latestBlockTimestamp = await time.latest();
            // stableToken / usd = 1.1
            await mockStableTokenPriceFeed.setRoundData(
                100,
                (1n * 10n ** refPriceDecimals * 11n) / 10n,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );
            // token / usd = 110
            await mockRefPriceFeed.setRoundData(
                100,
                110n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );

            // token / stableToken = 110/1.1 = $100
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp - 1
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("100", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("100", tokenDecimals, usdDecimals, refPriceDecimals)
            );

            // stableToken / usd = 0.99
            await mockStableTokenPriceFeed.setRoundData(
                100,
                (1n * 10n ** refPriceDecimals * 50n) / 100n,
                latestBlockTimestamp,
                latestBlockTimestamp,
                100
            );

            // token / stableToken = 110/0.5 = 220
            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("220", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("220", tokenDecimals, usdDecimals, refPriceDecimals)
            );

            await priceFeed.setRefPriceExtraSample(1);

            await mockRefPriceFeed.setRoundData(
                99,
                30n * 10n ** refPriceDecimals,
                latestBlockTimestamp,
                latestBlockTimestamp,
                99
            );

            await expect(
                priceFeed.setPriceX96s(
                    [
                        {
                            token: weth.address,
                            priceX96: toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                        },
                    ],
                    latestBlockTimestamp + 1
                )
            )
                .emit(priceFeed, "PriceUpdated")
                .withArgs(
                    weth.address,
                    toPriceX96("80", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("60", tokenDecimals, usdDecimals, refPriceDecimals),
                    toPriceX96("220", tokenDecimals, usdDecimals, refPriceDecimals)
                );
            await expect(await priceFeed.getMinPriceX96(weth.address)).to.be.eq(
                toPriceX96("60", tokenDecimals, usdDecimals, refPriceDecimals)
            );
            await expect(await priceFeed.getMaxPriceX96(weth.address)).to.be.eq(
                toPriceX96("220", tokenDecimals, usdDecimals, refPriceDecimals)
            );
        });
    });
});
