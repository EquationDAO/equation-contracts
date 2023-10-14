import {ethers} from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {BigNumber} from "ethers";
import {SIDE_LONG} from "./shared/Constants";

const MAX_UINT_128 = BigNumber.from(2).pow(128).sub(1);
describe("Router", () => {
    async function deployFixture() {
        const MockRewardFarmCallback = await ethers.getContractFactory("MockRewardFarmCallback");
        const mockRewardFarmCallback = await MockRewardFarmCallback.deploy();
        await mockRewardFarmCallback.deployed();

        const MockFeeDistributorCallback = await ethers.getContractFactory("MockFeeDistributorCallback");
        const mockFeeDistributorCallback = await MockFeeDistributorCallback.deploy();
        await mockFeeDistributorCallback.deployed();

        const MockEFC = await ethers.getContractFactory("MockEFC");
        const mockEFC = await MockEFC.deploy();
        await mockEFC.deployed();
        await mockEFC.initialize(100n, mockRewardFarmCallback.address);

        const MockRewardFarm = await ethers.getContractFactory("MockRewardFarm");
        const mockRewardFarm = await MockRewardFarm.deploy();
        await mockRewardFarm.deployed();

        const FeeDistributor = await ethers.getContractFactory("MockFeeDistributor");
        const feeDistributor = await FeeDistributor.deploy();
        await feeDistributor.deployed();

        const [user, other, gov] = await ethers.getSigners();
        const Router = await ethers.getContractFactory("Router");
        const router = await Router.deploy(mockEFC.address, mockRewardFarm.address, feeDistributor.address);
        await router.deployed();
        await router.changeGov(gov.address);
        await router.connect(gov).acceptGov();

        const ERC20Test = await ethers.getContractFactory("ERC20Test");
        const erc20 = await ERC20Test.connect(user).deploy("TestToken", "TTC", 18, MAX_UINT_128);

        const MockPool = await ethers.getContractFactory("MockPool");
        const mockPool = await MockPool.deploy(ethers.constants.AddressZero, erc20.address);
        await mockPool.deployed();

        return {
            user,
            gov,
            other,
            mockEFC,
            mockRewardFarm,
            router,
            mockPool,
            feeDistributor,
            erc20,
            mockRewardFarmCallback,
            mockFeeDistributorCallback,
        };
    }

    describe("PluginManager", () => {
        describe("#registerPlugin", () => {
            it("should pass", async () => {
                const {user, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
            });
            it("should revert if caller is not gov", async () => {
                const {user, other, router} = await loadFixture(deployFixture);
                await expect(router.connect(other).registerPlugin(user.address)).to.revertedWithCustomError(
                    router,
                    "Forbidden"
                );
            });
            it("should revert if plugin has been registered", async () => {
                const {user, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                await expect(router.connect(gov).registerPlugin(user.address)).to.revertedWithCustomError(
                    router,
                    "PluginAlreadyRegistered"
                );
            });
        });

        describe("#registeredPlugins", () => {
            it("should be true", async () => {
                const {user, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                expect(await router.registeredPlugins(user.address)).to.true;
            });
            it("should be false", async () => {
                const {user, router} = await loadFixture(deployFixture);
                expect(await router.registeredPlugins(user.address)).to.false;
            });
        });

        describe("#approvePlugin", () => {
            it("should revert if plugin not registered yet", async () => {
                const {user, gov, router} = await loadFixture(deployFixture);
                await expect(router.approvePlugin(user.address)).to.revertedWithCustomError(
                    router,
                    "PluginNotRegistered"
                );
            });
            it("should emit event if pass", async () => {
                const {user, other, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                await expect(router.connect(other).approvePlugin(user.address))
                    .to.emit(router, "PluginApproved")
                    .withArgs(other.address, user.address);
            });
            it("should revert if plugin has been approved", async () => {
                const {user, other, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                await router.connect(other).approvePlugin(user.address);
                await expect(router.connect(other).approvePlugin(user.address)).to.revertedWithCustomError(
                    router,
                    "PluginAlreadyApproved"
                );
            });
        });

        describe("#revokePlugin", () => {
            it("should revert if plugin has not been approved", async () => {
                const {user, other, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                await expect(router.connect(other).revokePlugin(user.address)).to.revertedWithCustomError(
                    router,
                    "PluginNotApproved"
                );
            });
            it("should emit event if pass", async () => {
                const {user, other, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                await router.connect(other).approvePlugin(user.address);
                await expect(router.connect(other).revokePlugin(user.address))
                    .to.emit(router, "PluginRevoked")
                    .withArgs(other.address, user.address);
            });
        });

        describe("#isPluginApproved", () => {
            it("should be false if plugin has not been approved", async () => {
                const {user, other, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                expect(await router.connect(other).isPluginApproved(other.address, user.address)).to.false;
            });
            it("should be true if plugin has been approved", async () => {
                const {user, other, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                await router.connect(other).approvePlugin(user.address);
                expect(await router.connect(other).isPluginApproved(other.address, user.address)).to.true;
            });
            it("should be false after plugin be revoked", async () => {
                const {user, other, gov, router} = await loadFixture(deployFixture);
                await router.connect(gov).registerPlugin(user.address);
                await router.connect(other).approvePlugin(user.address);
                await router.connect(other).revokePlugin(user.address);
                expect(await router.connect(other).isPluginApproved(other.address, user.address)).to.false;
            });
        });
    });

    describe("#pluginTransfer", () => {
        it("should pass", async () => {
            const {user, other, gov, erc20, router} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            const balanceBefore = await erc20.balanceOf(other.address);
            expect(balanceBefore).to.eq(0n);
            await router.connect(other).pluginTransfer(erc20.address, user.address, other.address, 10n ** 18n * 100n);
            const balanceAfter = await erc20.balanceOf(other.address);
            expect(balanceAfter).to.eq(10n ** 18n * 100n);
        });
        it("should revert if caller is not a plugin approved", async () => {
            const {user, other, gov, erc20, router} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router.connect(other).pluginTransfer(erc20.address, user.address, other.address, 10n ** 18n * 100n)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginTransferNFT", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockRewardFarmCallback, mockFeeDistributorCallback} = await loadFixture(
                deployFixture
            );

            const EFC = await ethers.getContractFactory("EFC");
            const efc = await EFC.deploy(
                10,
                10,
                10,
                mockRewardFarmCallback.address,
                mockFeeDistributorCallback.address
            );

            await efc.batchMintArchitect([user.address]);
            const tokenID = await mockFeeDistributorCallback.tokenID();
            await efc.approve(router.address, tokenID);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router.connect(other).pluginTransferNFT(efc.address, user.address, other.address, tokenID);
            expect(await efc.ownerOf(tokenID)).to.eq(other.address);
        });
        it("should revert if caller is not a plugin approved", async () => {
            const {user, other, gov, router, mockRewardFarmCallback, mockFeeDistributorCallback} = await loadFixture(
                deployFixture
            );
            const EFC = await ethers.getContractFactory("EFC");
            const efc = await EFC.deploy(
                10,
                10,
                10,
                mockRewardFarmCallback.address,
                mockFeeDistributorCallback.address
            );

            await efc.batchMintArchitect([user.address]);
            const tokenID = await mockFeeDistributorCallback.tokenID();
            await efc.approve(router.address, tokenID);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router.connect(other).pluginTransferNFT(efc.address, user.address, other.address, tokenID)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginOpenLiquidityPosition", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router
                .connect(other)
                .pluginOpenLiquidityPosition(mockPool.address, user.address, 10n ** 18n * 100n, 10n ** 18n * 1000n);
        });
        it("should revert if caller is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router
                    .connect(other)
                    .pluginOpenLiquidityPosition(mockPool.address, user.address, 10n ** 18n * 100n, 10n ** 18n * 1000n)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginCloseLiquidityPosition", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await mockPool.setLiquidityPositionID(1n);
            await mockPool.setPositionIDAddress(1n, user.address);
            await router.connect(other).pluginCloseLiquidityPosition(mockPool.address, 1n, user.address);
        });
        it("should revert if account of position is not a plugin approved", async () => {
            const {user, other, gov, router, mockPool} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await mockPool.setLiquidityPositionID(1n);
            await mockPool.setPositionIDAddress(1n, user.address);
            await expect(
                router.connect(other).pluginCloseLiquidityPosition(mockPool.address, 1n, user.address)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginAdjustLiquidityPositionMargin", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await mockPool.setPositionIDAddress(1n, user.address);
            await router
                .connect(other)
                .pluginAdjustLiquidityPositionMargin(mockPool.address, 1n, 10n ** 18n * 100n, user.address);
        });
        it("should revert if account of position is not a plugin approved", async () => {
            const {user, other, gov, router, mockPool} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await mockPool.setPositionIDAddress(1n, user.address);
            await expect(
                router
                    .connect(other)
                    .pluginAdjustLiquidityPositionMargin(mockPool.address, 1n, 10n ** 18n * 100n, user.address)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginIncreasePosition", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router
                .connect(other)
                .pluginIncreasePosition(
                    mockPool.address,
                    user.address,
                    SIDE_LONG,
                    10n ** 18n * 100n,
                    10n ** 18n * 1000n
                );
        });
        it("should revert if caller is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router
                    .connect(other)
                    .pluginIncreasePosition(
                        mockPool.address,
                        user.address,
                        SIDE_LONG,
                        10n ** 18n * 100n,
                        10n ** 18n * 1000n
                    )
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginDecreasePosition", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router
                .connect(other)
                .pluginDecreasePosition(
                    mockPool.address,
                    user.address,
                    SIDE_LONG,
                    10n ** 18n * 100n,
                    10n ** 18n * 1000n,
                    gov.address
                );
        });
        it("should revert if caller is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router
                    .connect(other)
                    .pluginDecreasePosition(
                        mockPool.address,
                        user.address,
                        SIDE_LONG,
                        10n ** 18n * 100n,
                        10n ** 18n * 1000n,
                        gov.address
                    )
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginCollectReferralFee", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool, mockEFC} = await loadFixture(deployFixture);
            await mockEFC.setOwner(1, user.address);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router.connect(other).pluginCollectReferralFee(mockPool.address, 1, user.address);
        });
        it("should revert if owner is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router.connect(other).pluginCollectReferralFee(mockPool.address, 1, user.address)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginCollectFarmLiquidityRewardBatch", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool, mockRewardFarm} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router
                .connect(other)
                .pluginCollectFarmLiquidityRewardBatch([mockPool.address], user.address, user.address);
            expect(await mockRewardFarm.rewardDebtRes()).to.eq(1n);
        });
        it("should revert if owner is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router
                    .connect(other)
                    .pluginCollectFarmLiquidityRewardBatch([mockPool.address], user.address, user.address)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginCollectFarmRiskBufferFundRewardBatch", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockPool, mockRewardFarm} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router
                .connect(other)
                .pluginCollectFarmRiskBufferFundRewardBatch([mockPool.address], user.address, user.address);
            expect(await mockRewardFarm.rewardDebtRes()).to.eq(2n);
        });
        it("should revert if owner is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router
                    .connect(other)
                    .pluginCollectFarmRiskBufferFundRewardBatch([mockPool.address], user.address, user.address)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginCollectFarmReferralRewardBatch", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockEFC, mockPool} = await loadFixture(deployFixture);
            await mockEFC.setOwner(1, user.address);
            await mockEFC.setOwner(2, user.address);
            await mockEFC.setOwner(3, user.address);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router
                .connect(other)
                .pluginCollectFarmReferralRewardBatch([mockPool.address], [1, 2, 3], user.address);
        });
        it("should revert if tokens length is zero", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await expect(router.pluginCollectFarmReferralRewardBatch([mockPool.address], [1], user.address)).to
                .reverted;
        });
        it("should revert if owner is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router.connect(other).pluginCollectFarmReferralRewardBatch([mockPool.address], [1], user.address)
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
        it("should revert if owner mismatch", async () => {
            const {user, other, gov, router, mockEFC, mockPool} = await loadFixture(deployFixture);
            await mockEFC.setOwner(1, user.address);
            await mockEFC.setOwner(2, user.address);
            await mockEFC.setOwner(3, other.address);

            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await expect(
                router.connect(other).pluginCollectFarmReferralRewardBatch([mockPool.address], [1, 2, 3], user.address)
            )
                .to.revertedWithCustomError(router, "OwnerMismatch")
                .withArgs(other.address, user.address);
        });
    });

    describe("#pluginCollectStakingRewardBatch", () => {
        it("should pass", async () => {
            const {user, other, gov, router, feeDistributor} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router.connect(other).pluginCollectStakingRewardBatch(user.address, user.address, [1]);
            expect(await feeDistributor.rewardAmountRes()).to.eq(1n);
        });
        it("should revert if owner is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router.connect(other).pluginCollectStakingRewardBatch(user.address, user.address, [1])
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginCollectV3PosStakingRewardBatch", () => {
        it("should pass", async () => {
            const {user, other, gov, router, feeDistributor} = await loadFixture(deployFixture);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router.connect(other).pluginCollectV3PosStakingRewardBatch(user.address, user.address, [1]);
            expect(await feeDistributor.rewardAmountRes()).to.eq(2n);
        });
        it("should revert if owner is not a plugin approved", async () => {
            const {user, other, gov, erc20, router, mockPool} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router.connect(other).pluginCollectV3PosStakingRewardBatch(user.address, user.address, [1])
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });

    describe("#pluginCollectArchitectRewardBatch", () => {
        it("should pass", async () => {
            const {user, other, gov, router, mockEFC, feeDistributor} = await loadFixture(deployFixture);
            await mockEFC.setOwner(1, user.address);
            await router.connect(gov).registerPlugin(other.address);
            await router.connect(user).approvePlugin(other.address);
            await router.connect(other).pluginCollectArchitectRewardBatch(user.address, [1]);
            expect(await feeDistributor.rewardAmountRes()).to.eq(3n);
        });
        it("should revert if owner is not a plugin approved", async () => {
            const {user, other, gov, erc20, router} = await loadFixture(deployFixture);
            await erc20.connect(user).approve(router.address, 10n ** 18n * 100n);
            await router.connect(gov).registerPlugin(other.address);
            await expect(
                router.connect(other).pluginCollectArchitectRewardBatch(user.address, [1])
            ).to.revertedWithCustomError(router, "CallerUnauthorized");
        });
    });
});
