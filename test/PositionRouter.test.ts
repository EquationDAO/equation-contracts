import {loadFixture, mine, time} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {ethers} from "hardhat";

import {SIDE_LONG, SIDE_SHORT} from "./shared/Constants";

describe("PositionRouter", function () {
    const defaultMinExecutionFee = 3000;

    async function deployFixture() {
        const [owner, otherAccount1, otherAccount2] = await ethers.getSigners();
        const ERC20Test = await ethers.getContractFactory("ERC20Test");
        const USDC = await ERC20Test.connect(otherAccount1).deploy("USDC", "USDC", 6, 100_000_000n);
        const ETH = await ERC20Test.connect(otherAccount1).deploy("ETHER", "ETH", 18, 100_000_000);
        await USDC.deployed();
        await ETH.deployed();

        const Pool = await ethers.getContractFactory("MockPool");
        const pool = await Pool.deploy(USDC.address, ETH.address);
        await pool.deployed();

        const Router = await ethers.getContractFactory("MockRouter");
        const router = await Router.deploy();
        await router.deployed();

        const GasRouter = await ethers.getContractFactory("GasDrainingMockRouter");
        const gasRouter = await GasRouter.deploy();
        await gasRouter.deployed();

        // router can transfer owner's USDC
        await USDC.connect(otherAccount1).approve(router.address, 100_000_000n);
        await USDC.connect(otherAccount1).approve(gasRouter.address, 100_000_000n);

        const PositionRouter = await ethers.getContractFactory("PositionRouter");
        const positionRouter = await PositionRouter.deploy(USDC.address, router.address, defaultMinExecutionFee);
        await positionRouter.deployed();

        const positionRouterWithBadRouter = await PositionRouter.deploy(
            USDC.address,
            gasRouter.address,
            defaultMinExecutionFee
        );
        await positionRouterWithBadRouter.deployed();

        const RevertedFeeReceiver = await ethers.getContractFactory("RevertedFeeReceiver");
        const revertedFeeReceiver = await RevertedFeeReceiver.deploy();
        await revertedFeeReceiver.deployed();

        return {
            owner,
            otherAccount1,
            otherAccount2,
            router,
            positionRouter,
            positionRouterWithBadRouter,
            USDC,
            ETH,
            pool,
            revertedFeeReceiver,
        };
    }

    describe("#updatePositionExecutor", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {otherAccount1, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.connect(otherAccount1).updatePositionExecutor(otherAccount1.address, true)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });

        it("should emit correct event and update param", async () => {
            const {positionRouter, otherAccount1} = await loadFixture(deployFixture);

            await expect(positionRouter.updatePositionExecutor(otherAccount1.address, true))
                .to.emit(positionRouter, "PositionExecutorUpdated")
                .withArgs(otherAccount1.address, true);
            expect(await positionRouter.positionExecutors(otherAccount1.address)).to.eq(true);

            await expect(positionRouter.updatePositionExecutor(otherAccount1.address, false))
                .to.emit(positionRouter, "PositionExecutorUpdated")
                .withArgs(otherAccount1.address, false);
            expect(await positionRouter.positionExecutors(otherAccount1.address)).to.eq(false);
        });
    });

    describe("#updateDelayValues", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {otherAccount1, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.connect(otherAccount1).updateDelayValues(0n, 0n, 0n)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });

        it("should emit correct event and update param", async () => {
            const {positionRouter} = await loadFixture(deployFixture);
            await expect(positionRouter.updateDelayValues(10n, 20n, 30n))
                .to.emit(positionRouter, "DelayValuesUpdated")
                .withArgs(10n, 20n, 30n);
            expect(await positionRouter.minBlockDelayExecutor()).to.eq(10n);
            expect(await positionRouter.minTimeDelayPublic()).to.eq(20n);
            expect(await positionRouter.maxTimeDelay()).to.eq(30n);
        });
    });

    describe("#updateMinExecutionFee", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {otherAccount1, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.connect(otherAccount1).updateMinExecutionFee(3000n)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });

        it("should emit correct event and update params", async () => {
            const {positionRouter} = await loadFixture(deployFixture);
            await expect(positionRouter.updateMinExecutionFee(3000n))
                .to.emit(positionRouter, "MinExecutionFeeUpdated")
                .withArgs(3000n);
            expect(await positionRouter.minExecutionFee()).to.eq(3000n);
        });
    });

    describe("#updateExecutionGasLimit", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {otherAccount1, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.connect(otherAccount1).updateExecutionGasLimit(2000000n)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });

        it("should update param", async () => {
            const {positionRouter, otherAccount1} = await loadFixture(deployFixture);

            await positionRouter.updateExecutionGasLimit(2000000n);
            expect(await positionRouter.executionGasLimit()).to.eq(2000000n);
        });
    });

    describe("OpenLiquidityPosition", async () => {
        describe("#createOpenLiquidityPosition", async () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, otherAccount1} = await loadFixture(deployFixture);
                // insufficient execution fee
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createOpenLiquidityPosition(ethers.constants.AddressZero, 10n, 100n, {value: 0})
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(0n, 3000n);
            });

            it("should pass", async () => {
                const {positionRouter, USDC, pool, otherAccount1} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    const assertion = expect(
                        await positionRouter
                            .connect(otherAccount1)
                            .createOpenLiquidityPosition(pool.address, 1000n, 10000n, {
                                value: 3000,
                            })
                    );
                    await assertion.to.changeEtherBalance(positionRouter, "3000");
                    await assertion.to.changeTokenBalance(USDC, positionRouter, "1000");
                    await assertion.to
                        .emit(positionRouter, "OpenLiquidityPositionCreated")
                        .withArgs(otherAccount1.address, pool.address, 1000n, 10000n, 3000n, i);

                    expect(await positionRouter.openLiquidityPositionIndexNext()).to.eq(i + 1);
                    expect(await positionRouter.openLiquidityPositionRequests(i)).to.deep.eq([
                        otherAccount1.address,
                        await time.latestBlock(),
                        pool.address,
                        await time.latest(),
                        1000n,
                        10000n,
                        3000n,
                    ]);
                }
                expect(await positionRouter.openLiquidityPositionIndex()).to.eq(0n);
            });
        });

        describe("#cancelOpenLiquidityPosition", async () => {
            describe("shouldCancel/shouldExecuteOrCancel", async () => {
                it("should revert if caller is not request owner nor executor", async () => {
                    const {positionRouter, pool, otherAccount1, owner} = await loadFixture(deployFixture);
                    // create a new request
                    await positionRouter
                        .connect(otherAccount1)
                        .createOpenLiquidityPosition(pool.address, 1000n, 10000n, {
                            value: 3000,
                        });

                    await expect(
                        positionRouter.cancelOpenLiquidityPosition(0n, owner.address)
                    ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                });

                it("should wait at least minBlockDelayExecutor until executors can cancel", async () => {
                    const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                    // account2 is now executor
                    await positionRouter.updatePositionExecutor(otherAccount2.address, true);
                    // executor has to wait 10 blocks
                    await positionRouter.updateDelayValues(10n, 3000n, 6000n);
                    // create a new request
                    await positionRouter
                        .connect(otherAccount1)
                        .createOpenLiquidityPosition(pool.address, 1000n, 10000n, {
                            value: 3000,
                        });

                    // should fail to cancel
                    await positionRouter.connect(otherAccount2).cancelOpenLiquidityPosition(0n, otherAccount2.address);
                    let [account] = await positionRouter.openLiquidityPositionRequests(0n);
                    expect(account).eq(otherAccount1.address);

                    // mine 10 blocks
                    await mine(10);

                    // should be cancelled
                    await positionRouter.connect(otherAccount2).cancelOpenLiquidityPosition(0n, otherAccount2.address);
                    [account] = await positionRouter.openLiquidityPositionRequests(0n);
                    expect(account).eq(ethers.constants.AddressZero.toString());
                });

                it("should wait at least minTimeDelayPublic until public can cancel", async () => {
                    const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
                    // public has to wait 3m
                    await expect(positionRouter.updateDelayValues(10n, 180n, 6000n)).not.to.be.reverted;
                    // create a new request
                    await positionRouter
                        .connect(otherAccount1)
                        .createOpenLiquidityPosition(pool.address, 1000n, 20000n, {
                            value: 3000,
                        });
                    const earliest = (await time.latest()) + 180;
                    await expect(
                        positionRouter.connect(otherAccount1).cancelOpenLiquidityPosition(0n, otherAccount1.address)
                    )
                        .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                        .withArgs(earliest);

                    // increase 3m
                    await time.increase(180n);

                    let [account] = await positionRouter.openLiquidityPositionRequests(0n);
                    expect(account).eq(otherAccount1.address);
                    await positionRouter.connect(otherAccount1).cancelOpenLiquidityPosition(0n, otherAccount1.address);
                    [account] = await positionRouter.openLiquidityPositionRequests(0n);
                    expect(account).eq(ethers.constants.AddressZero.toString());
                });
            });

            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.cancelOpenLiquidityPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not request owner", async () => {
                const {positionRouter, otherAccount1, otherAccount2, pool} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000n, 10000n, {
                    value: 3000,
                });
                // _positionID 1 owner is `0x0`
                await expect(
                    positionRouter.connect(otherAccount2).cancelOpenLiquidityPosition(0n, otherAccount1.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should be ok if executor cancel", async () => {
                const {positionRouter, pool, USDC, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000n, 20000n, {
                    value: 3000,
                });
                await positionRouter.updatePositionExecutor(otherAccount2.address, true);
                const assertion = expect(
                    await positionRouter.connect(otherAccount2).cancelOpenLiquidityPosition(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-3000", "3000"]);
                await assertion.to.changeTokenBalances(USDC, [positionRouter, otherAccount1], ["-1000", "1000"]);
                await assertion.to
                    .emit(positionRouter, "OpenLiquidityPositionCancelled")
                    .withArgs(0n, otherAccount2.address);
                // validation
                let [account] = await positionRouter.openLiquidityPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });

            it("should be ok if request owner calls", async () => {
                const {positionRouter, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000n, 20000n, {
                    value: 3000,
                });
                await time.increase(180);
                const assertion = expect(
                    await positionRouter.connect(otherAccount1).cancelOpenLiquidityPosition(0n, otherAccount1.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount1], ["-3000", "3000"]);
                await assertion.to.changeTokenBalances(USDC, [positionRouter, otherAccount1], ["-1000", "1000"]);
                await assertion.to
                    .emit(positionRouter, "OpenLiquidityPositionCancelled")
                    .withArgs(0n, otherAccount1.address);
                // validation
                let [account] = await positionRouter.openLiquidityPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });
        });

        describe("#executeOpenLiquidityPosition", async () => {
            it("should pass if request is not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.executeOpenLiquidityPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {owner, otherAccount1, otherAccount2, pool, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000n, 20000n, {
                    value: 3000,
                });
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter.connect(otherAccount2).executeOpenLiquidityPosition(0n, owner.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should revert with 'Expired' if maxTimeDelay passed", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000n, 20000n, {
                    value: 3000,
                });
                const positionBlockTs = await time.latest();
                await positionRouter.updatePositionExecutor(otherAccount2.address, true);
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                const expiredAt = positionBlockTs + 600;
                await time.increase(600n);
                await expect(
                    positionRouter.connect(otherAccount2).executeOpenLiquidityPosition(0n, otherAccount2.address)
                )
                    .to.be.revertedWithCustomError(positionRouter, "Expired")
                    .withArgs(expiredAt);
            });

            it("should emit event and distribute funds", async () => {
                const {positionRouter, pool, USDC, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000n, 30000n, {
                    value: 3000,
                });
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter.updatePositionExecutor(otherAccount2.address, true);
                const assertion = expect(
                    await positionRouter.connect(otherAccount2).executeOpenLiquidityPosition(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-3000", "3000"]);
                await assertion.to.changeTokenBalances(USDC, [positionRouter, pool], ["-1000", "1000"]);
                await assertion.to
                    .emit(positionRouter, "OpenLiquidityPositionExecuted")
                    .withArgs(0n, otherAccount2.address);
                // delete request
                let [account] = await positionRouter.openLiquidityPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000n, 30000n, {
                    value: 3000,
                });
                const current = await time.latest();
                await expect(
                    positionRouter.connect(otherAccount1).executeOpenLiquidityPosition(0n, otherAccount1.address)
                )
                    .to.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + 180);
                await time.setNextBlockTimestamp(current + 180);
                await expect(
                    positionRouter.connect(otherAccount1).executeOpenLiquidityPosition(0n, otherAccount1.address)
                ).not.to.be.reverted;
            });
        });
    });

    describe("CloseLiquidityPosition", async () => {
        describe("#createCloseLiquidityPosition", async () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, otherAccount1, pool} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                // Insufficient execution fee
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                            value: 1000,
                        })
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(1000n, 3000n);

                await positionRouter
                    .connect(otherAccount1)
                    .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                        value: 3000,
                    });
            });

            it("should revert with 'Forbidden' if caller is not request owner", async () => {
                const {positionRouter, otherAccount1, pool} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(1n, ethers.constants.AddressZero);
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createCloseLiquidityPosition(pool.address, 1n, otherAccount1.address, {
                            value: 3000,
                        })
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should pass", async () => {
                const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                for (let i = 0; i < 10; i++) {
                    await expect(
                        positionRouter
                            .connect(otherAccount1)
                            .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                                value: 3000,
                            })
                    )
                        .to.emit(positionRouter, "CloseLiquidityPositionCreated")
                        .withArgs(otherAccount1.address, pool.address, 2n, otherAccount1.address, 3000n, i);
                    expect(await positionRouter.closeLiquidityPositionIndexNext()).to.eq(i + 1);
                    expect(await positionRouter.closeLiquidityPositionRequests(i)).to.deep.eq([
                        otherAccount1.address,
                        2n,
                        pool.address,
                        await time.latestBlock(),
                        3000n,
                        otherAccount1.address,
                        await time.latest(),
                    ]);
                }
                expect(await positionRouter.openLiquidityPositionIndex()).to.eq(0n);
            });
        });

        describe("#cancelCloseLiquidityPosition", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.cancelCloseLiquidityPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                        value: 20000,
                    });
                await time.increase(180);
                await expect(
                    positionRouter.connect(otherAccount2).cancelCloseLiquidityPosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                // request owner should be able to cancel
                await positionRouter.connect(otherAccount1).cancelCloseLiquidityPosition(0n, otherAccount1.address);
            });

            it("should emit event and refund", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                        value: 20000,
                    });

                await positionRouter.updatePositionExecutor(otherAccount2.address, true);

                const assertion = expect(
                    await positionRouter.connect(otherAccount2).cancelCloseLiquidityPosition(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-20000", "20000"]);
                await assertion.to
                    .emit(positionRouter, "CloseLiquidityPositionCancelled")
                    .withArgs(0n, otherAccount2.address);

                // validation
                let [account] = await positionRouter.closeLiquidityPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });
        });

        describe("#executeCloseLiquidityPosition", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.executeCloseLiquidityPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                        value: 20000,
                    });
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter.connect(otherAccount2).executeCloseLiquidityPosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should emit event and transfer execution fee", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                        value: 30000,
                    });

                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter.updatePositionExecutor(otherAccount2.address, true);

                const assertion = expect(
                    await positionRouter.connect(otherAccount2).executeCloseLiquidityPosition(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-30000", "30000"]);
                await assertion.to
                    .emit(positionRouter, "CloseLiquidityPositionExecuted")
                    .withArgs(0n, otherAccount2.address);
                // delete request
                let [account] = await positionRouter.closeLiquidityPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                        value: 30000,
                    });
                const current = await time.latest();
                await expect(
                    positionRouter.connect(otherAccount1).executeCloseLiquidityPosition(0n, otherAccount1.address)
                )
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + 180);
                await time.setNextBlockTimestamp(current + 180);
                await expect(
                    positionRouter.connect(otherAccount1).executeCloseLiquidityPosition(0n, otherAccount1.address)
                ).not.to.be.reverted;
            });
        });
    });

    describe("AdjustLiquidityPositionMargin", async () => {
        describe("#createAdjustLiquidityPositionMargin", async () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, otherAccount1, pool} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                // insufficient execution fee
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createAdjustLiquidityPositionMargin(pool.address, 2n, 1000n, otherAccount1.address, {
                            value: 1000,
                        })
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(1000n, 3000n);
                await positionRouter
                    .connect(otherAccount1)
                    .createAdjustLiquidityPositionMargin(pool.address, 2n, 1000n, otherAccount1.address, {
                        value: 3000,
                    });
            });

            it("should revert with 'Forbidden' if caller is not executor nor position owner", async () => {
                const {positionRouter, otherAccount1, pool} = await loadFixture(deployFixture);
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createAdjustLiquidityPositionMargin(pool.address, 1n, 100n, otherAccount1.address, {
                            value: 3000,
                        })
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should pass", async () => {
                const {positionRouter, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                for (let i = 0; i < 10; i++) {
                    const assertion = expect(
                        await positionRouter
                            .connect(otherAccount1)
                            .createAdjustLiquidityPositionMargin(pool.address, 2n, 100n, otherAccount1.address, {
                                value: 3000,
                            })
                    );
                    await assertion.to.changeEtherBalance(positionRouter, "3000");
                    await assertion.to.changeTokenBalance(USDC, positionRouter, "100");
                    await assertion.to
                        .emit(positionRouter, "AdjustLiquidityPositionMarginCreated")
                        .withArgs(otherAccount1.address, pool.address, 2n, 100n, otherAccount1.address, 3000n, i);

                    expect(await positionRouter.adjustLiquidityPositionMarginIndexNext()).to.eq(i + 1);
                    expect(await positionRouter.adjustLiquidityPositionMarginRequests(i)).to.deep.eq([
                        otherAccount1.address,
                        2n,
                        pool.address,
                        await time.latestBlock(),
                        100n,
                        await time.latest(),
                        otherAccount1.address,
                        3000n,
                    ]);
                }
                expect(await positionRouter.openLiquidityPositionIndex()).to.eq(0n);
            });
        });

        describe("#cancelAdjustLiquidityPositionMargin", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.cancelAdjustLiquidityPositionMargin(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor position owner", async () => {
                const {positionRouter, otherAccount1, otherAccount2, pool} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createAdjustLiquidityPositionMargin(pool.address, 2n, 100n, otherAccount1.address, {
                        value: 3000,
                    });
                await expect(
                    positionRouter.connect(otherAccount2).cancelAdjustLiquidityPositionMargin(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should emit event and refund", async () => {
                const {positionRouter, pool, USDC, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createAdjustLiquidityPositionMargin(pool.address, 2n, 100n, otherAccount1.address, {
                        value: 3000,
                    });

                await positionRouter.updatePositionExecutor(otherAccount2.address, true);
                const assertion = expect(
                    await positionRouter
                        .connect(otherAccount2)
                        .cancelAdjustLiquidityPositionMargin(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-3000", "3000"]);
                await assertion.to.changeTokenBalances(USDC, [positionRouter, otherAccount1], ["-100", "100"]);
                await assertion.to
                    .emit(positionRouter, "AdjustLiquidityPositionMarginCancelled")
                    .withArgs(0n, otherAccount2.address);

                // validation
                let [account] = await positionRouter.openLiquidityPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });
        });

        describe("#executeAdjustLiquidityPositionMargin", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.executeAdjustLiquidityPositionMargin(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor position owner", async () => {
                const {positionRouter, otherAccount1, otherAccount2, pool} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createAdjustLiquidityPositionMargin(pool.address, 2n, 100n, otherAccount1.address, {
                        value: 3000,
                    });
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter
                        .connect(otherAccount2)
                        .executeAdjustLiquidityPositionMargin(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should emit event and distribute funds", async () => {
                const {positionRouter, pool, USDC, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                await positionRouter
                    .connect(otherAccount1)
                    .createAdjustLiquidityPositionMargin(pool.address, 2n, 100n, otherAccount1.address, {
                        value: 3000,
                    });
                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter.updatePositionExecutor(otherAccount2.address, true);
                const assertion = expect(
                    await positionRouter
                        .connect(otherAccount2)
                        .executeAdjustLiquidityPositionMargin(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-3000", "3000"]);
                await assertion.to.changeTokenBalances(USDC, [positionRouter, pool], ["-100", "100"]);
                await assertion.to
                    .emit(positionRouter, "AdjustLiquidityPositionMarginExecuted")
                    .withArgs(0n, otherAccount2.address);
                // request deleted
                let [account] = await positionRouter.adjustLiquidityPositionMarginRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
                await pool.setPositionIDAddress(2n, otherAccount1.address);
                expect(
                    await positionRouter
                        .connect(otherAccount1)
                        .createAdjustLiquidityPositionMargin(pool.address, 2n, 100n, otherAccount1.address, {
                            value: 3000,
                        })
                );
                const current = await time.latest();
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .executeAdjustLiquidityPositionMargin(0n, otherAccount1.address)
                )
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + 180);
                await time.setNextBlockTimestamp(current + 180);
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .executeAdjustLiquidityPositionMargin(0n, otherAccount1.address)
                ).not.to.be.reverted;
            });
        });
    });

    describe("IncreasePosition", async () => {
        describe("#createIncreasePosition", async () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
                // insufficient execution fee
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createIncreasePosition(pool.address, SIDE_LONG, 100n, 100n, 100n, {
                            value: 1000,
                        })
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(1000n, 3000n);
            });

            it("should pass", async () => {
                const {positionRouter, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    const assertion = expect(
                        await positionRouter
                            .connect(otherAccount1)
                            .createIncreasePosition(pool.address, SIDE_LONG, 100n, 100n, 100n, {
                                value: 3000,
                            })
                    );
                    await assertion.to.changeEtherBalance(positionRouter, "3000");
                    await assertion.to.changeTokenBalance(USDC, positionRouter, "100");
                    await assertion.to
                        .emit(positionRouter, "IncreasePositionCreated")
                        .withArgs(otherAccount1.address, pool.address, SIDE_LONG, 100n, 100n, 100n, 3000n, i);
                    expect(await positionRouter.increasePositionIndexNext()).to.eq(i + 1);
                    expect(await positionRouter.increasePositionRequests(i)).to.deep.eq([
                        otherAccount1.address,
                        await time.latestBlock(),
                        pool.address,
                        100n,
                        100n,
                        100n,
                        await time.latest(),
                        SIDE_LONG,
                        3000n,
                    ]);
                }
                expect(await positionRouter.increasePositionIndex()).to.eq(0n);
            });
        });

        describe("#cancelIncreasePosition", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.cancelIncreasePosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {otherAccount1, otherAccount2, pool, positionRouter} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createIncreasePosition(pool.address, SIDE_LONG, 100n, 100n, 100n, {
                        value: 3000,
                    });
                await expect(
                    positionRouter.connect(otherAccount2).cancelIncreasePosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });
        });

        describe("#executeIncreasePosition", async () => {
            it("should return true if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.executeIncreasePosition(1000n, owner.address);
            });

            it("should revert with 'InvalidTradePrice' if trade price is not met", async () => {
                const {positionRouter, router, pool, otherAccount1, USDC} = await loadFixture(deployFixture);
                await positionRouter.updateDelayValues(0n, 0n, 600n);

                await positionRouter
                    .connect(otherAccount1)
                    .createIncreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1900n, {
                        value: 3000,
                    });

                await router.setTradePriceX96(1910n);

                await expect(positionRouter.connect(otherAccount1).executeIncreasePosition(0n, otherAccount1.address))
                    .to.be.revertedWithCustomError(positionRouter, "InvalidTradePrice")
                    .withArgs(1910n, 1900n);

                await router.setTradePriceX96(1890);

                {
                    const assertion = expect(
                        await positionRouter.connect(otherAccount1).executeIncreasePosition(0n, otherAccount1.address)
                    );
                    await assertion.to.changeEtherBalances([positionRouter, otherAccount1], ["-3000", "3000"]);
                    await assertion.to.changeTokenBalances(USDC, [positionRouter, pool], ["-100", "100"]);
                    await assertion.to
                        .emit(positionRouter, "IncreasePositionExecuted")
                        .withArgs(0n, otherAccount1.address);
                }

                await positionRouter
                    .connect(otherAccount1)
                    .createIncreasePosition(pool.address, SIDE_SHORT, 100n, 100n, 1790n, {
                        value: 3000,
                    });
                await router.setTradePriceX96(1750n);
                await expect(positionRouter.connect(otherAccount1).executeIncreasePosition(1n, otherAccount1.address))
                    .to.be.revertedWithCustomError(positionRouter, "InvalidTradePrice")
                    .withArgs(1750n, 1790n);
                await router.setTradePriceX96(1795n);

                {
                    const assertion = expect(
                        await positionRouter.connect(otherAccount1).executeIncreasePosition(1n, otherAccount1.address)
                    );
                    await assertion.to.changeEtherBalances([positionRouter, otherAccount1], ["-3000", "3000"]);
                    await assertion.to.changeTokenBalances(USDC, [positionRouter, pool], ["-100", "100"]);
                    await assertion.to
                        .emit(positionRouter, "IncreasePositionExecuted")
                        .withArgs(1n, otherAccount1.address);
                }
            });

            it("should not revert if acceptable trade price is zero", async () => {
                const {positionRouter, router, pool, otherAccount1} = await loadFixture(deployFixture);
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter
                    .connect(otherAccount1)
                    .createIncreasePosition(pool.address, SIDE_SHORT, 100n, 100n, 0n, {
                        value: 3000,
                    });
                // trade price is very low for increasing short position, but still
                // expected to not revert
                await router.setTradePriceX96(1n);
                await expect(positionRouter.connect(otherAccount1).executeIncreasePosition(0n, otherAccount1.address))
                    .not.to.be.reverted;
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, pool, router, otherAccount1} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createIncreasePosition(pool.address, SIDE_SHORT, 100n, 100n, 0n, {
                        value: 3000,
                    });
                const current = await time.latest();
                const earliest = (await time.latest()) + 180;
                await router.setTradePriceX96(1n);
                await time.setNextBlockTimestamp(current + 179);
                await expect(positionRouter.connect(otherAccount1).executeIncreasePosition(0n, otherAccount1.address))
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(earliest);

                await time.setNextBlockTimestamp(current + 180);
                await expect(positionRouter.connect(otherAccount1).executeIncreasePosition(0n, otherAccount1.address))
                    .not.to.be.reverted;
            });
        });
    });

    describe("DecreasePosition", async () => {
        describe("#createDecreasePosition", async () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);

                // insufficient execution fee
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1800n, otherAccount1.address, {
                            value: 2000,
                        })
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(2000n, 3000n);
            });

            it("should pass", async () => {
                const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    const assertion = expect(
                        await positionRouter
                            .connect(otherAccount1)
                            .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1800n, otherAccount1.address, {
                                value: 3000,
                            })
                    );
                    await assertion.to.changeEtherBalance(positionRouter, "3000");
                    await assertion.to
                        .emit(positionRouter, "DecreasePositionCreated")
                        .withArgs(
                            otherAccount1.address,
                            pool.address,
                            SIDE_LONG,
                            100n,
                            100n,
                            1800n,
                            otherAccount1.address,
                            3000n,
                            i
                        );
                    expect(await positionRouter.decreasePositionIndexNext()).to.eq(i + 1);
                    expect(await positionRouter.decreasePositionRequests(i)).to.deep.eq([
                        otherAccount1.address,
                        await time.latestBlock(),
                        pool.address,
                        100n,
                        100n,
                        1800n,
                        await time.latest(),
                        SIDE_LONG,
                        otherAccount1.address,
                        3000n,
                    ]);
                }
                expect(await positionRouter.decreasePositionIndex()).to.eq(0n);
            });
        });

        describe("#cancelDecreasePosition", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.cancelDecreasePosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {otherAccount1, otherAccount2, pool, positionRouter} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 1800n, otherAccount1.address, {
                        value: 3000,
                    });
                await expect(
                    positionRouter.connect(otherAccount2).cancelDecreasePosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });
        });

        describe("#executeDecreasePosition", async () => {
            it("should return true if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.executeDecreasePosition(1000n, owner.address);
            });

            it("should revert with 'InvalidTradePrice' if trade price is not met", async () => {
                const {positionRouter, pool, otherAccount1, router} = await loadFixture(deployFixture);
                await positionRouter.updateDelayValues(0n, 0n, 600n);

                // decrease long, use min price,
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1790n, otherAccount1.address, {
                        value: 3000,
                    });
                await pool.setMarketPriceX96(1800n, 1800n);
                await router.setTradePriceX96(1780n);
                await expect(positionRouter.connect(otherAccount1).executeDecreasePosition(0n, otherAccount1.address))
                    .to.be.revertedWithCustomError(positionRouter, "InvalidTradePrice")
                    .withArgs(1780n, 1790n);
                await router.setTradePriceX96(1795n);
                {
                    const assertion = expect(
                        await positionRouter.connect(otherAccount1).executeDecreasePosition(0n, otherAccount1.address)
                    );
                    await assertion.to.changeEtherBalances([positionRouter, otherAccount1], ["-3000", "3000"]);
                    await assertion.to
                        .emit(positionRouter, "DecreasePositionExecuted")
                        .withArgs(0n, otherAccount1.address);
                }

                // short, use max price
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreasePosition(pool.address, SIDE_SHORT, 100n, 100n, 1820n, otherAccount1.address, {
                        value: 3000,
                    });
                await router.setTradePriceX96(1850n);
                await expect(positionRouter.connect(otherAccount1).executeDecreasePosition(1n, otherAccount1.address))
                    .to.be.revertedWithCustomError(positionRouter, "InvalidTradePrice")
                    .withArgs(1850n, 1820n);
                await router.setTradePriceX96(1810n);
                {
                    const assertion = expect(
                        await positionRouter.connect(otherAccount1).executeDecreasePosition(1n, otherAccount1.address)
                    );
                    await assertion.to.changeEtherBalances([positionRouter, otherAccount1], ["-3000", "3000"]);
                    await assertion.to
                        .emit(positionRouter, "DecreasePositionExecuted")
                        .withArgs(1n, otherAccount1.address);
                }
            });

            it("should not revert if acceptable trade price is zero", async () => {
                const {positionRouter, otherAccount1, pool, router} = await loadFixture(deployFixture);
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 0n, otherAccount1.address, {
                        value: 3000,
                    });
                // trade price is very low for decreasing long position, but still
                // expected to not revert
                await router.setTradePriceX96(1n);
                await expect(positionRouter.connect(otherAccount1).executeDecreasePosition(0n, otherAccount1.address))
                    .not.to.be.reverted;
            });
            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, pool, router, otherAccount1} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreasePosition(pool.address, SIDE_SHORT, 100n, 100n, 1820n, otherAccount1.address, {
                        value: 3000,
                    });
                const current = await time.latest();
                await router.setTradePriceX96(1810n);
                await time.setNextBlockTimestamp(current + 179);
                await expect(positionRouter.connect(otherAccount1).executeDecreasePosition(0n, otherAccount1.address))
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + 180);
                await time.setNextBlockTimestamp(current + 180);
                await expect(positionRouter.connect(otherAccount1).executeDecreasePosition(0n, otherAccount1.address))
                    .not.to.be.reverted;
            });
        });
    });

    describe("IncreaseRiskBufferFundPosition", async () => {
        describe("#createIncreaseRiskBufferFundPosition", async () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
                // insufficient execution fee
                await expect(
                    positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 100n, {
                        value: 1000,
                    })
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(1000n, 3000n);
            });

            it("should pass", async () => {
                const {positionRouter, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    const assertion = expect(
                        await positionRouter
                            .connect(otherAccount1)
                            .createIncreaseRiskBufferFundPosition(pool.address, 100n, {
                                value: 3000,
                            })
                    );
                    await assertion.to.changeEtherBalance(positionRouter, "3000");
                    await assertion.to.changeTokenBalance(USDC, positionRouter, "100");
                    await assertion.to
                        .emit(positionRouter, "IncreaseRiskBufferFundPositionCreated")
                        .withArgs(otherAccount1.address, pool.address, 100n, 3000n, i);

                    expect(await positionRouter.increaseRiskBufferFundPositionIndexNext()).to.eq(i + 1);
                    expect(await positionRouter.increaseRiskBufferFundPositionRequests(i)).to.deep.eq([
                        otherAccount1.address,
                        await time.latestBlock(),
                        pool.address,
                        await time.latest(),
                        100n,
                        3000n,
                    ]);
                }
                expect(await positionRouter.increaseRiskBufferFundPositionIndex()).to.eq(0n);
            });
        });

        describe("#cancelIncreaseRiskBufferFundPosition", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.cancelIncreaseRiskBufferFundPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {otherAccount1, otherAccount2, pool, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 100n, {
                    value: 3000,
                });
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter
                        .connect(otherAccount2)
                        .cancelIncreaseRiskBufferFundPosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                expect(
                    await positionRouter
                        .connect(otherAccount1)
                        .cancelIncreaseRiskBufferFundPosition(0n, otherAccount1.address)
                );
            });
        });

        describe("#executeIncreaseRiskBufferFundPosition", async () => {
            it("should return true if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.executeIncreaseRiskBufferFundPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 200n, {
                    value: 3000,
                });
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter
                        .connect(otherAccount2)
                        .executeIncreaseRiskBufferFundPosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should emit event and transfer execution fee", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 100n, {
                    value: 30000,
                });

                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter.updatePositionExecutor(otherAccount2.address, true);

                const assertion = expect(
                    await positionRouter
                        .connect(otherAccount2)
                        .executeIncreaseRiskBufferFundPosition(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-30000", "30000"]);
                await assertion.to
                    .emit(positionRouter, "IncreaseRiskBufferFundPositionExecuted")
                    .withArgs(0n, otherAccount2.address);
                // delete request
                let [account] = await positionRouter.increaseRiskBufferFundPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });
            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
                await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 100n, {
                    value: 30000,
                });
                const current = await time.latest();
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .executeIncreaseRiskBufferFundPosition(0n, otherAccount1.address)
                )
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + 180);
                await time.setNextBlockTimestamp(current + 180);
                await expect(
                    await positionRouter
                        .connect(otherAccount1)
                        .executeIncreaseRiskBufferFundPosition(0n, otherAccount1.address)
                ).not.to.be.reverted;
            });
        });
    });

    describe("DecreaseRiskBufferFundPosition", async () => {
        describe("#createDecreaseRiskBufferFundPosition", async () => {
            it("should transfer correct execution fee to position router", async () => {
                const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
                // insufficient execution fee
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .createDecreaseRiskBufferFundPosition(pool.address, 100n, otherAccount1.address, {
                            value: 1000,
                        })
                )
                    .to.be.revertedWithCustomError(positionRouter, "InsufficientExecutionFee")
                    .withArgs(1000n, 3000n);
            });

            it("should pass", async () => {
                const {positionRouter, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
                for (let i = 0; i < 10; i++) {
                    const assertion = expect(
                        await positionRouter
                            .connect(otherAccount1)
                            .createDecreaseRiskBufferFundPosition(pool.address, 100n, otherAccount1.address, {
                                value: 3000,
                            })
                    );
                    await assertion.to.changeEtherBalance(positionRouter, "3000");
                    await assertion.to
                        .emit(positionRouter, "DecreaseRiskBufferFundPositionCreated")
                        .withArgs(otherAccount1.address, pool.address, 100n, otherAccount1.address, 3000n, i);

                    expect(await positionRouter.decreaseRiskBufferFundPositionIndexNext()).to.eq(i + 1);
                    expect(await positionRouter.decreaseRiskBufferFundPositionRequests(i)).to.deep.eq([
                        otherAccount1.address,
                        await time.latestBlock(),
                        pool.address,
                        await time.latest(),
                        100n,
                        otherAccount1.address,
                        3000n,
                    ]);
                }
                expect(await positionRouter.decreaseRiskBufferFundPositionIndex()).to.eq(0n);
            });
        });

        describe("#cancelDecreaseRiskBufferFundPosition", async () => {
            it("should pass if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.cancelDecreaseRiskBufferFundPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {otherAccount1, otherAccount2, pool, positionRouter} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreaseRiskBufferFundPosition(pool.address, 100n, otherAccount1.address, {
                        value: 3000,
                    });
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter
                        .connect(otherAccount2)
                        .cancelDecreaseRiskBufferFundPosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
                expect(
                    await positionRouter
                        .connect(otherAccount1)
                        .cancelDecreaseRiskBufferFundPosition(0n, otherAccount1.address)
                );
            });
        });

        describe("#executeDecreaseRiskBufferFundPosition", async () => {
            it("should return true if request not exist", async () => {
                const {owner, positionRouter} = await loadFixture(deployFixture);
                await positionRouter.executeDecreaseRiskBufferFundPosition(1000n, owner.address);
            });

            it("should revert with 'Forbidden' if caller is not executor nor request owner", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreaseRiskBufferFundPosition(pool.address, 200n, otherAccount1.address, {
                        value: 3000,
                    });
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await expect(
                    positionRouter
                        .connect(otherAccount2)
                        .executeDecreaseRiskBufferFundPosition(0n, otherAccount2.address)
                ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
            });

            it("should emit event and transfer execution fee", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreaseRiskBufferFundPosition(pool.address, 100n, otherAccount1.address, {
                        value: 30000,
                    });

                // set a delay value to prevent expire
                await positionRouter.updateDelayValues(0n, 0n, 600n);
                await positionRouter.updatePositionExecutor(otherAccount2.address, true);

                const assertion = expect(
                    await positionRouter
                        .connect(otherAccount2)
                        .executeDecreaseRiskBufferFundPosition(0n, otherAccount2.address)
                );
                await assertion.to.changeEtherBalances([positionRouter, otherAccount2], ["-30000", "30000"]);
                await assertion.to
                    .emit(positionRouter, "DecreaseRiskBufferFundPositionExecuted")
                    .withArgs(0n, otherAccount2.address);
                // delete request
                let [account] = await positionRouter.decreaseRiskBufferFundPositionRequests(0n);
                expect(account).eq(ethers.constants.AddressZero.toString());
            });

            it("should revert with 'TooEarly' if someone who are not the executor executes his own request and pass if sufficient time elapsed", async () => {
                const {positionRouter, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
                await positionRouter
                    .connect(otherAccount1)
                    .createDecreaseRiskBufferFundPosition(pool.address, 100n, otherAccount1.address, {
                        value: 30000,
                    });
                const current = await time.latest();
                await expect(
                    positionRouter
                        .connect(otherAccount1)
                        .executeDecreaseRiskBufferFundPosition(0n, otherAccount1.address)
                )
                    .to.be.revertedWithCustomError(positionRouter, "TooEarly")
                    .withArgs(current + 180);
                await time.setNextBlockTimestamp(current + 180);
                await expect(
                    await positionRouter
                        .connect(otherAccount1)
                        .executeDecreaseRiskBufferFundPosition(0n, otherAccount1.address)
                ).not.to.be.reverted;
            });
        });
    });

    describe("#executeOpenLiquidityPositions", async () => {
        it("should revert with 'Forbidden' if caller is not executor", async () => {
            const {owner, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.executeOpenLiquidityPositions(100n, owner.address)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });
        it("should cancel request if expired", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);

            await positionRouter.updateDelayValues(0, 0, 180);
            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });

            await time.increase(180);
            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouter.executeOpenLiquidityPositions(1n, owner.address));
            await assertion.to.changeEtherBalances([positionRouter, owner], ["-3000", "3000"]);
            await assertion.to.emit(positionRouter, "OpenLiquidityPositionCancelled").withArgs(0, owner.address);

            let [account] = await positionRouter.openLiquidityPositionRequests(0n);
            expect(account).eq(ethers.constants.AddressZero);
            expect(await positionRouter.openLiquidityPositionIndex()).to.eq(1);
        });

        it("should not execute any requests if minBlockDelayExecutor is not met", async () => {
            const {owner, positionRouter, pool, otherAccount1, USDC} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(100, 0, 10000);
            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });

            await mine(50);

            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });

            await positionRouter.updatePositionExecutor(owner.address, true);
            await positionRouter.executeOpenLiquidityPositions(2n, owner.address);

            // no request executed
            expect(await positionRouter.openLiquidityPositionIndex()).to.eq(0n);
            let [account] = await positionRouter.openLiquidityPositionRequests(0n);
            expect(account).eq(otherAccount1.address);

            await mine(50);

            // expect first request executed while second not
            {
                const assertion = expect(await positionRouter.executeOpenLiquidityPositions(2n, owner.address));
                await assertion.to.changeEtherBalances([positionRouter, owner], ["-3000", "3000"]);
                await assertion.to.changeTokenBalances(USDC, [positionRouter, pool], ["-1000", "1000"]);
                await assertion.to.emit(positionRouter, "OpenLiquidityPositionExecuted").withArgs(0n, owner.address);
                expect(await positionRouter.openLiquidityPositionIndex()).to.eq(1n);
            }

            // expect send execute
            await mine(50);
            {
                const assertion = expect(await positionRouter.executeOpenLiquidityPositions(2n, owner.address));
                await assertion.to.changeEtherBalances([positionRouter, owner], ["-3000", "3000"]);
                await assertion.to.changeTokenBalances(USDC, [positionRouter, pool], ["-1000", "1000"]);
                await assertion.to.emit(positionRouter, "OpenLiquidityPositionExecuted").withArgs(1n, owner.address);
                expect(await positionRouter.openLiquidityPositionIndex()).to.eq(2n);
            }
        });

        it("should cancel if execution reverted and continue to execute", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 0);

            // all requests should be cancelled because they reverted
            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });
            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });
            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });

            await positionRouter.updatePositionExecutor(owner.address, true);
            const assertion = expect(await positionRouter.executeOpenLiquidityPositions(3n, owner.address));
            await assertion.to.emit(positionRouter, "OpenLiquidityPositionCancelled").withArgs(0n, owner.address);
            await assertion.to.emit(positionRouter, "OpenLiquidityPositionCancelled").withArgs(1n, owner.address);
            await assertion.to.emit(positionRouter, "OpenLiquidityPositionCancelled").withArgs(2n, owner.address);

            expect(await positionRouter.openLiquidityPositionIndex()).eq(3n);
        });

        it("should cancel request if execution reverted and continue to execute when pool is malformed which drain gas", async () => {
            const {owner, positionRouter, positionRouterWithBadRouter, pool, otherAccount1} = await loadFixture(
                deployFixture
            );
            await positionRouterWithBadRouter.updateDelayValues(0, 0, 100);
            await positionRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateExecutionGasLimit(50000);

            // all requests should be cancelled because they reverted
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createOpenLiquidityPosition(pool.address, 1000, 10000, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createOpenLiquidityPosition(pool.address, 1000, 10000, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createOpenLiquidityPosition(pool.address, 1000, 10000, {
                    value: 3000,
                });

            await positionRouterWithBadRouter.updatePositionExecutor(owner.address, true);
            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(
                await positionRouterWithBadRouter.executeOpenLiquidityPositions(300n, owner.address)
            );
            await assertion.to
                .emit(positionRouterWithBadRouter, "OpenLiquidityPositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "OpenLiquidityPositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "OpenLiquidityPositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouterWithBadRouter.openLiquidityPositionIndex()).eq(3n);

            // as a control, use another position router which has a no-op router to try again
            // the only difference is the router
            // expect to emit executed event
            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });
            const assertion2 = expect(await positionRouter.executeOpenLiquidityPositions(300n, owner.address));

            await assertion2.to.emit(positionRouter, "OpenLiquidityPositionExecuted").withArgs(0n, owner.address);
        });

        it("should continue to execute if cancellation reverted", async () => {
            const {owner, positionRouter, pool, otherAccount1, revertedFeeReceiver} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(0, 0, 0);

            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });
            await positionRouter.connect(otherAccount1).createOpenLiquidityPosition(pool.address, 1000, 10000, {
                value: 3000,
            });

            await positionRouter.updatePositionExecutor(owner.address, true);

            // execution will revert with `Expired`
            // cancellation will revert with `Reverted`
            // expect index still increases
            await positionRouter.executeOpenLiquidityPositions(1000n, revertedFeeReceiver.address);

            // requests still there
            let [account] = await positionRouter.openLiquidityPositionRequests(0n);
            expect(account).eq(otherAccount1.address);

            [account] = await positionRouter.openLiquidityPositionRequests(1n);
            expect(account).eq(otherAccount1.address);

            expect(await positionRouter.openLiquidityPositionIndex()).eq(2n);
        });
    });

    describe("#executeCloseLiquidityPositions", async () => {
        it("should revert with 'Forbidden' if caller is not executor", async () => {
            const {owner, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.executeCloseLiquidityPositions(100n, owner.address)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });
        it("should cancel if execution reverted and continue to execute next", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 0);

            await pool.setPositionIDAddress(2n, otherAccount1.address);

            // all requests should be cancelled because they reverted
            await positionRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouter.executeCloseLiquidityPositions(300n, owner.address));
            await assertion.to.emit(positionRouter, "CloseLiquidityPositionCancelled").withArgs(0n, owner.address);
            await assertion.to.emit(positionRouter, "CloseLiquidityPositionCancelled").withArgs(1n, owner.address);
            await assertion.to.emit(positionRouter, "CloseLiquidityPositionCancelled").withArgs(2n, owner.address);

            expect(await positionRouter.closeLiquidityPositionIndex()).eq(3n);
        });

        it("should cancel if execution reverted and continue to execute next when pool is malformed which will drain gas", async () => {
            const {owner, positionRouter, positionRouterWithBadRouter, pool, otherAccount1} = await loadFixture(
                deployFixture
            );
            await positionRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateExecutionGasLimit(50000);

            await pool.setPositionIDAddress(2n, otherAccount1.address);

            // all requests should be cancelled because they reverted
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouterWithBadRouter.updatePositionExecutor(owner.address, true);
            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(
                await positionRouterWithBadRouter.executeCloseLiquidityPositions(300n, owner.address)
            );
            await assertion.to
                .emit(positionRouterWithBadRouter, "CloseLiquidityPositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "CloseLiquidityPositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "CloseLiquidityPositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouterWithBadRouter.closeLiquidityPositionIndex()).eq(3n);

            await positionRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });

            const assertion2 = expect(await positionRouter.executeCloseLiquidityPositions(300n, owner.address));
            await assertion2.to.emit(positionRouter, "CloseLiquidityPositionExecuted").withArgs(0n, owner.address);
        });

        it("should continue to execute next if cancellation reverted", async () => {
            const {owner, positionRouter, pool, otherAccount1, revertedFeeReceiver} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(0, 0, 0);

            await pool.setPositionIDAddress(2n, otherAccount1.address);

            await positionRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createCloseLiquidityPosition(pool.address, 2n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);
            // execution will revert with `Expired`
            // cancellation will revert with `Reverted`
            // expect index still increases
            await positionRouter.executeCloseLiquidityPositions(1000n, revertedFeeReceiver.address);

            // requests still there
            let [account] = await positionRouter.closeLiquidityPositionRequests(0n);
            expect(account).eq(otherAccount1.address);

            [account] = await positionRouter.closeLiquidityPositionRequests(1n);
            expect(account).eq(otherAccount1.address);

            expect(await positionRouter.closeLiquidityPositionIndex()).eq(2n);
        });
    });

    describe("#executeAdjustLiquidityPositionMargins", async () => {
        it("should revert with 'Forbidden' if caller is not executor", async () => {
            const {owner, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.executeAdjustLiquidityPositionMargins(100n, owner.address)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });
        it("should cancel if execution reverted and continue to execute", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 0);

            await pool.setPositionIDAddress(2n, otherAccount1.address);

            // all requests should be cancelled because they reverted
            await positionRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouter.executeAdjustLiquidityPositionMargins(300n, owner.address));
            await assertion.to
                .emit(positionRouter, "AdjustLiquidityPositionMarginCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouter, "AdjustLiquidityPositionMarginCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouter, "AdjustLiquidityPositionMarginCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouter.adjustLiquidityPositionMarginIndex()).eq(3n);
        });

        it("should cancel if execution reverted and continue to execute when pool is malformed which will drain gas", async () => {
            const {owner, positionRouter, positionRouterWithBadRouter, pool, otherAccount1} = await loadFixture(
                deployFixture
            );
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateExecutionGasLimit(50000);

            await pool.setPositionIDAddress(2n, otherAccount1.address);

            // all requests should be cancelled because they reverted
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);
            await positionRouterWithBadRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(
                await positionRouterWithBadRouter.executeAdjustLiquidityPositionMargins(300n, owner.address)
            );
            await assertion.to
                .emit(positionRouterWithBadRouter, "AdjustLiquidityPositionMarginCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "AdjustLiquidityPositionMarginCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "AdjustLiquidityPositionMarginCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouterWithBadRouter.adjustLiquidityPositionMarginIndex()).eq(3n);

            await positionRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000, otherAccount1.address, {
                    value: 3000,
                });
            const assertion2 = expect(await positionRouter.executeAdjustLiquidityPositionMargins(300n, owner.address));
            await assertion2.emit(positionRouter, "AdjustLiquidityPositionMarginExecuted").withArgs(0n, owner.address);
        });

        it("should continue to execute next if cancellation reverted", async () => {
            const {owner, positionRouter, pool, otherAccount1, revertedFeeReceiver} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(0, 0, 0);

            await pool.setPositionIDAddress(2n, otherAccount1.address);

            await positionRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createAdjustLiquidityPositionMargin(pool.address, 2n, 3000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);
            // execution will revert with `Expired`
            // cancellation will revert with `Reverted`
            // expect index still increases
            await positionRouter.executeAdjustLiquidityPositionMargins(1000n, revertedFeeReceiver.address);

            // requests still there
            let [account] = await positionRouter.adjustLiquidityPositionMarginRequests(0n);
            expect(account).eq(otherAccount1.address);

            [account] = await positionRouter.adjustLiquidityPositionMarginRequests(1n);
            expect(account).eq(otherAccount1.address);

            expect(await positionRouter.adjustLiquidityPositionMarginIndex()).eq(2n);
        });
    });

    describe("#executeIncreasePositions", async () => {
        it("should revert with 'Forbidden' if caller is not executor", async () => {
            const {owner, positionRouter} = await loadFixture(deployFixture);
            await expect(positionRouter.executeIncreasePositions(100n, owner.address)).to.be.revertedWithCustomError(
                positionRouter,
                "Forbidden"
            );
        });
        it("should cancel request if execution reverted and continue to execute", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 0);

            // all requests should be cancelled because they reverted
            await positionRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouter.executeIncreasePositions(300n, owner.address));
            await assertion.to.emit(positionRouter, "IncreasePositionCancelled").withArgs(0n, owner.address);
            await assertion.to.emit(positionRouter, "IncreasePositionCancelled").withArgs(1n, owner.address);
            await assertion.to.emit(positionRouter, "IncreasePositionCancelled").withArgs(2n, owner.address);

            expect(await positionRouter.increasePositionIndex()).eq(3n);
        });

        it("should cancel request if execution reverted and continue to execute when pool is malformed which will drain gas", async () => {
            const {owner, positionRouter, positionRouterWithBadRouter, pool, otherAccount1} = await loadFixture(
                deployFixture
            );
            await positionRouterWithBadRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateExecutionGasLimit(50000);
            await positionRouter.updateDelayValues(0, 0, 100);

            // all requests should be cancelled because they reverted
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouterWithBadRouter.updatePositionExecutor(owner.address, true);
            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouterWithBadRouter.executeIncreasePositions(300n, owner.address));
            await assertion.to
                .emit(positionRouterWithBadRouter, "IncreasePositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "IncreasePositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "IncreasePositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouterWithBadRouter.increasePositionIndex()).eq(3n);

            await positionRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            const assertion2 = expect(await positionRouter.executeIncreasePositions(300n, owner.address));
            await assertion2.to.emit(positionRouter, "IncreasePositionExecuted").withArgs(0n, owner.address);

            // note that the gas specified in the code is just an upper limit.
            // when the gas left is lower than this value, code can still be executed
            await positionRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });
            const assertion3 = expect(
                await positionRouter.executeIncreasePositions(300n, owner.address, {gasLimit: 990000})
            );
            await assertion3.to.emit(positionRouter, "IncreasePositionExecuted").withArgs(1n, owner.address);
        });

        it("should continue to execute next request if cancellation reverted", async () => {
            const {owner, positionRouter, pool, otherAccount1, revertedFeeReceiver} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(0, 0, 0);

            await positionRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouter
                .connect(otherAccount1)
                .createIncreasePosition(pool.address, SIDE_LONG, 1000n, 1000n, 100n, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);
            // execution will revert with `Expired`
            // cancellation will revert with `Reverted`
            // expect index still increases
            await positionRouter.executeIncreasePositions(1000n, revertedFeeReceiver.address);

            // requests still there
            let [account] = await positionRouter.increasePositionRequests(0n);
            expect(account).eq(otherAccount1.address);

            [account] = await positionRouter.increasePositionRequests(1n);
            expect(account).eq(otherAccount1.address);

            expect(await positionRouter.increasePositionIndex()).eq(2n);
        });
    });

    describe("#executeDecreasePositions", async () => {
        it("should revert with 'Forbidden' if caller is not executor", async () => {
            const {owner, positionRouter} = await loadFixture(deployFixture);
            await expect(positionRouter.executeDecreasePositions(100n, owner.address)).to.be.revertedWithCustomError(
                positionRouter,
                "Forbidden"
            );
        });

        it("should cancel request if execution reverted and continue to execute", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 0);

            // all requests should be cancelled because they reverted
            await positionRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1000n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1000n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouter.executeDecreasePositions(300n, owner.address));
            await assertion.to.emit(positionRouter, "DecreasePositionCancelled").withArgs(0n, owner.address);
            await assertion.to.emit(positionRouter, "DecreasePositionCancelled").withArgs(1n, owner.address);
            await assertion.to.emit(positionRouter, "DecreasePositionCancelled").withArgs(2n, owner.address);

            expect(await positionRouter.decreasePositionIndex()).eq(3n);
        });

        it("should cancel request if execution reverted and continue to execute when pool is malformed which will drain gas", async () => {
            const {owner, positionRouter, positionRouterWithBadRouter, pool, otherAccount1} = await loadFixture(
                deployFixture
            );
            await positionRouterWithBadRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateExecutionGasLimit(50000);
            await positionRouter.updateDelayValues(0, 0, 100);

            // all requests should be cancelled because they reverted
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 0n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 0n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 0n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouterWithBadRouter.updatePositionExecutor(owner.address, true);
            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouterWithBadRouter.executeDecreasePositions(300n, owner.address));
            await assertion.to
                .emit(positionRouterWithBadRouter, "DecreasePositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "DecreasePositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "DecreasePositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouterWithBadRouter.decreasePositionIndex()).eq(3n);

            await positionRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 0n, otherAccount1.address, {
                    value: 3000,
                });

            const assertion2 = expect(await positionRouter.executeDecreasePositions(300n, owner.address));
            await assertion2.to.emit(positionRouter, "DecreasePositionExecuted").withArgs(0n, owner.address);
        });

        it("should continue to execute next request if cancellation reverted", async () => {
            const {owner, positionRouter, pool, otherAccount1, revertedFeeReceiver} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(0, 0, 0);

            await positionRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1000n, otherAccount1.address, {
                    value: 3000,
                });
            await positionRouter
                .connect(otherAccount1)
                .createDecreasePosition(pool.address, SIDE_LONG, 100n, 100n, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);
            // execution will revert with `Expired`
            // cancellation will revert with `Reverted`
            // expect index still increases
            await positionRouter.executeDecreasePositions(1000n, revertedFeeReceiver.address);

            // requests still there
            let [account] = await positionRouter.decreasePositionRequests(0n);
            expect(account).eq(otherAccount1.address);

            [account] = await positionRouter.decreasePositionRequests(1n);
            expect(account).eq(otherAccount1.address);

            expect(await positionRouter.decreasePositionIndex()).eq(2n);
        });
    });

    describe("#executeIncreaseRiskBufferFundPositions", async () => {
        it("should revert with 'Forbidden' if caller is not executor", async () => {
            const {owner, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.executeIncreaseRiskBufferFundPositions(100n, owner.address)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });
        it("should cancel request if execution reverted and continue to execute", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 0);

            // all requests should be cancelled because they reverted
            await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                value: 3000,
            });

            await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                value: 3000,
            });

            await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                value: 3000,
            });

            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouter.executeIncreaseRiskBufferFundPositions(300n, owner.address));
            await assertion.to
                .emit(positionRouter, "IncreaseRiskBufferFundPositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouter, "IncreaseRiskBufferFundPositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouter, "IncreaseRiskBufferFundPositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouter.increaseRiskBufferFundPositionIndex()).eq(3n);
        });

        it("should cancel request if execution reverted and continue to execute when pool is malformed which will drain gas", async () => {
            const {owner, positionRouter, positionRouterWithBadRouter, pool, otherAccount1} = await loadFixture(
                deployFixture
            );
            await positionRouterWithBadRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateExecutionGasLimit(50000);
            await positionRouter.updateDelayValues(0, 0, 100);

            // all requests should be cancelled because they reverted
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                    value: 3000,
                });

            await positionRouterWithBadRouter.updatePositionExecutor(owner.address, true);
            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(
                await positionRouterWithBadRouter.executeIncreaseRiskBufferFundPositions(300n, owner.address)
            );
            await assertion.to
                .emit(positionRouterWithBadRouter, "IncreaseRiskBufferFundPositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "IncreaseRiskBufferFundPositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "IncreaseRiskBufferFundPositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouterWithBadRouter.increaseRiskBufferFundPositionIndex()).eq(3n);

            await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                value: 3000,
            });
            const assertion2 = expect(await positionRouter.executeIncreaseRiskBufferFundPositions(300n, owner.address));

            await assertion2.to
                .emit(positionRouter, "IncreaseRiskBufferFundPositionExecuted")
                .withArgs(0n, owner.address);
        });

        it("should continue to execute next request if cancellation reverted", async () => {
            const {owner, positionRouter, pool, otherAccount1, revertedFeeReceiver} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(0, 0, 0);

            await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                value: 3000,
            });

            await positionRouter.connect(otherAccount1).createIncreaseRiskBufferFundPosition(pool.address, 1000n, {
                value: 3000,
            });

            await positionRouter.updatePositionExecutor(owner.address, true);
            // execution will revert with `Expired`
            // cancellation will revert with `Reverted`
            // expect index still increases
            await positionRouter.executeIncreaseRiskBufferFundPositions(1000n, revertedFeeReceiver.address);

            // requests still there
            let [account] = await positionRouter.increaseRiskBufferFundPositionRequests(0n);
            expect(account).eq(otherAccount1.address);

            [account] = await positionRouter.increaseRiskBufferFundPositionRequests(1n);
            expect(account).eq(otherAccount1.address);

            expect(await positionRouter.increaseRiskBufferFundPositionIndex()).eq(2n);
        });
    });

    describe("#executeDecreaseRiskBufferFundPositions", async () => {
        it("should revert with 'Forbidden' if caller is not executor", async () => {
            const {owner, positionRouter} = await loadFixture(deployFixture);
            await expect(
                positionRouter.executeDecreaseRiskBufferFundPositions(100n, owner.address)
            ).to.be.revertedWithCustomError(positionRouter, "Forbidden");
        });
        it("should cancel request if execution reverted and continue to execute", async () => {
            const {owner, positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
            // _maxTimeDelay is 0, execution will revert immediately
            await positionRouter.updateDelayValues(0, 0, 0);

            // all requests should be cancelled because they reverted
            await positionRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(await positionRouter.executeDecreaseRiskBufferFundPositions(300n, owner.address));
            await assertion.to
                .emit(positionRouter, "DecreaseRiskBufferFundPositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouter, "DecreaseRiskBufferFundPositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouter, "DecreaseRiskBufferFundPositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouter.decreaseRiskBufferFundPositionIndex()).eq(3n);
        });

        it("should cancel request if execution reverted and continue to execute when pool is malformed which drain gas", async () => {
            const {owner, positionRouter, positionRouterWithBadRouter, pool, otherAccount1} = await loadFixture(
                deployFixture
            );
            await positionRouterWithBadRouter.updateDelayValues(0, 0, 100);
            await positionRouterWithBadRouter.updateExecutionGasLimit(50000);
            await positionRouter.updateDelayValues(0, 0, 100);

            // all requests should be cancelled because they reverted
            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouterWithBadRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouterWithBadRouter.updatePositionExecutor(owner.address, true);
            await positionRouter.updatePositionExecutor(owner.address, true);

            const assertion = expect(
                await positionRouterWithBadRouter.executeDecreaseRiskBufferFundPositions(300n, owner.address)
            );
            await assertion.to
                .emit(positionRouterWithBadRouter, "DecreaseRiskBufferFundPositionCancelled")
                .withArgs(0n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "DecreaseRiskBufferFundPositionCancelled")
                .withArgs(1n, owner.address);
            await assertion.to
                .emit(positionRouterWithBadRouter, "DecreaseRiskBufferFundPositionCancelled")
                .withArgs(2n, owner.address);

            expect(await positionRouterWithBadRouter.decreaseRiskBufferFundPositionIndex()).eq(3n);

            await positionRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });
            const assertion2 = expect(await positionRouter.executeDecreaseRiskBufferFundPositions(300n, owner.address));

            await assertion2.to
                .emit(positionRouter, "DecreaseRiskBufferFundPositionExecuted")
                .withArgs(0n, owner.address);
        });

        it("should continue to execute next request if cancellation reverted", async () => {
            const {owner, positionRouter, pool, otherAccount1, revertedFeeReceiver} = await loadFixture(deployFixture);
            await positionRouter.updateDelayValues(0, 0, 0);

            await positionRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter
                .connect(otherAccount1)
                .createDecreaseRiskBufferFundPosition(pool.address, 1000n, otherAccount1.address, {
                    value: 3000,
                });

            await positionRouter.updatePositionExecutor(owner.address, true);
            // execution will revert with `Expired`
            // cancellation will revert with `Reverted`
            // expect index still increases
            await positionRouter.executeDecreaseRiskBufferFundPositions(1000n, revertedFeeReceiver.address);

            // requests still there
            let [account] = await positionRouter.decreaseRiskBufferFundPositionRequests(0n);
            expect(account).eq(otherAccount1.address);

            [account] = await positionRouter.decreaseRiskBufferFundPositionRequests(1n);
            expect(account).eq(otherAccount1.address);

            expect(await positionRouter.decreaseRiskBufferFundPositionIndex()).eq(2n);
        });
    });
});
