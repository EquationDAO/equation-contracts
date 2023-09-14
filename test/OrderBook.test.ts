import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {ethers} from "hardhat";
import {expect} from "chai";
import {SIDE_LONG, SIDE_SHORT} from "./shared/Constants";

describe("OrderBook", function () {
    async function deployFixture() {
        const [owner, otherAccount1, otherAccount2] = await ethers.getSigners();
        const ERC20Test = await ethers.getContractFactory("ERC20Test");
        const USDC = await ERC20Test.connect(otherAccount1).deploy("USDC", "USDC", 6, 100_000_000n);
        const ETH = await ERC20Test.connect(otherAccount1).deploy("ETH", "ETH", 18, 100_000_000);
        await USDC.deployed();
        await ETH.deployed();

        const Router = await ethers.getContractFactory("MockRouter");
        const router = await Router.deploy();
        await router.deployed();

        // a bad router that will drain the gas
        const GasRouter = await ethers.getContractFactory("GasDrainingMockRouter");
        const gasRouter = await GasRouter.deploy();
        await gasRouter.deployed();

        const Pool = await ethers.getContractFactory("MockPool");
        const pool = await Pool.deploy(USDC.address, ETH.address);
        await pool.deployed();

        const OrderBook = await ethers.getContractFactory("OrderBook");
        const orderBook = await OrderBook.deploy(USDC.address, router.address, 3000);
        await orderBook.deployed();

        const orderBookWithBadRouter = await OrderBook.deploy(USDC.address, gasRouter.address, 3000);
        await orderBookWithBadRouter.deployed();

        await USDC.connect(otherAccount1).approve(router.address, 100_000_000n);
        await USDC.connect(otherAccount1).approve(gasRouter.address, 100_000_000n);

        const RevertedFeeReceiver = await ethers.getContractFactory("RevertedFeeReceiver");
        const revertedFeeReceiver = await RevertedFeeReceiver.deploy();
        await revertedFeeReceiver.deployed();

        return {
            orderBook,
            orderBookWithBadRouter,
            owner,
            otherAccount1,
            otherAccount2,
            USDC,
            ETH,
            router,
            pool,
            revertedFeeReceiver,
        };
    }

    describe("#updateMinExecutionFee", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {orderBook, otherAccount1} = await loadFixture(deployFixture);
            await expect(orderBook.connect(otherAccount1).updateMinExecutionFee(3000n)).to.be.revertedWithCustomError(
                orderBook,
                "Forbidden"
            );
        });

        it("should emit correct event and update params", async () => {
            const {orderBook} = await loadFixture(deployFixture);
            await expect(orderBook.updateMinExecutionFee(3000n))
                .to.emit(orderBook, "MinExecutionFeeUpdated")
                .withArgs(3000n);
            expect(await orderBook.minExecutionFee()).to.eq(3000n);
        });
    });

    describe("#updateOrderExecutor", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {otherAccount1, orderBook} = await loadFixture(deployFixture);
            await expect(
                orderBook.connect(otherAccount1).updateOrderExecutor(otherAccount1.address, true)
            ).to.be.revertedWithCustomError(orderBook, "Forbidden");
        });

        it("should emit correct event and update param", async () => {
            const {orderBook, otherAccount1} = await loadFixture(deployFixture);

            await expect(orderBook.updateOrderExecutor(otherAccount1.address, true))
                .to.emit(orderBook, "OrderExecutorUpdated")
                .withArgs(otherAccount1.address, true);
            expect(await orderBook.orderExecutors(otherAccount1.address)).to.eq(true);

            await expect(orderBook.updateOrderExecutor(otherAccount1.address, false))
                .to.emit(orderBook, "OrderExecutorUpdated")
                .withArgs(otherAccount1.address, false);
            expect(await orderBook.orderExecutors(otherAccount1.address)).to.eq(false);
        });
    });

    describe("#updateExecutionGasLimit", async () => {
        it("should revert with 'Forbidden' if caller is not gov", async () => {
            const {otherAccount1, orderBook} = await loadFixture(deployFixture);
            await expect(
                orderBook.connect(otherAccount1).updateExecutionGasLimit(2000000n)
            ).to.be.revertedWithCustomError(orderBook, "Forbidden");
        });

        it("should emit correct event and update param", async () => {
            const {orderBook} = await loadFixture(deployFixture);
            await orderBook.updateExecutionGasLimit(2000000n);
            expect(await orderBook.executionGasLimit()).to.eq(2000000n);
        });
    });

    describe("#createIncreaseOrder", async () => {
        it("should revert if insufficient execution fee", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            // executionFee is insufficient
            await expect(
                orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 1n, 1000n, true, 1100n, {
                        value: 2000,
                    })
            )
                .to.be.revertedWithCustomError(orderBook, "InsufficientExecutionFee")
                .withArgs(2000n, 3000n);
        });

        it("should pass", async () => {
            const {orderBook, pool, otherAccount1, USDC} = await loadFixture(deployFixture);
            let side = SIDE_LONG;
            for (let i = 0; i < 10; i++) {
                await expect(
                    orderBook
                        .connect(otherAccount1)
                        .createIncreaseOrder(pool.address, side, 100n, 100n, 1000n, true, 1100n, {
                            value: 3000,
                        })
                )
                    .to.changeEtherBalances([orderBook, otherAccount1], ["3000", "-3000"])
                    .to.changeTokenBalances(USDC, [otherAccount1, orderBook], ["-100", "100"])
                    .to.emit(orderBook, "IncreaseOrderCreated")
                    .withArgs(otherAccount1.address, pool.address, side, 100n, 100n, 1000n, true, 1100n, 3000n, i);

                expect(await orderBook.increaseOrdersIndexNext()).to.eq(i + 1);
                expect(await orderBook.increaseOrders(i)).to.deep.eq([
                    otherAccount1.address,
                    pool.address,
                    side,
                    100n,
                    100n,
                    1000n,
                    true,
                    1100n,
                    3000n,
                ]);
                side = (side % 2) + 1;
            }
            expect(await orderBook.increaseOrdersIndexNext()).eq(10);
        });
    });

    describe("#updateIncreaseOrder", async () => {
        it("should revert with 'Forbidden' if caller is not request owner", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);

            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1000n, true, 1100n, {
                        value: 3000,
                    })
            );

            await expect(orderBook.updateIncreaseOrder(0n, 2n, 2n)).to.be.revertedWithCustomError(
                orderBook,
                "Forbidden"
            );
        });

        it("should pass", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1000n, true, 1100n, {
                        value: 3000,
                    })
            );
            await expect(orderBook.connect(otherAccount1).updateIncreaseOrder(0n, 1200n, 1300n))
                .to.emit(orderBook, "IncreaseOrderUpdated")
                .withArgs(0n, 1200n, 1300n);
            let order = await orderBook.increaseOrders(0n);
            expect(order.triggerMarketPriceX96).eq(1200n);
            expect(order.acceptableTradePriceX96).eq(1300n);
        });
    });

    describe("#cancelIncreaseOrder", async () => {
        it("should revert with 'Forbidden' if caller is not request owner", async () => {
            const {orderBook, pool, owner, otherAccount1} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1000n, true, 1100n, {value: 3000})
            );
            await expect(orderBook.cancelIncreaseOrder(0n, owner.address)).to.be.revertedWithCustomError(
                orderBook,
                "Forbidden"
            );
        });
        it("should pass", async () => {
            const {orderBook, pool, USDC, otherAccount1} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1000n, true, 1100n, {value: 3000})
            );
            await expect(orderBook.connect(otherAccount1).cancelIncreaseOrder(0n, otherAccount1.address))
                .changeEtherBalances([orderBook, otherAccount1], ["-3000", "3000"])
                .changeTokenBalances(USDC, [orderBook, otherAccount1], ["-100", "100"])
                .to.emit(orderBook, "IncreaseOrderCancelled")
                .withArgs(0n, otherAccount1.address);
        });
    });

    describe("#executeIncreaseOrder", async () => {
        it("should revert with 'Forbidden' if caller is not order executor", async () => {
            const {owner, orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1000n, true, 1100n, {
                        value: 3000,
                    })
            );
            await expect(orderBook.executeIncreaseOrder(0n, owner.address)).to.revertedWithCustomError(
                orderBook,
                "Forbidden"
            );
        });

        it("should revert if price is not met", async () => {
            const {owner, orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            // 1900n for long, 1800n for short
            expect(await pool.setMarketPriceX96(1900n, 1800n));

            // short: use min price
            // triggerAbove: true
            // triggerPrice: 1850
            // should not trigger as 1800 < 1850
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_SHORT, 100n, 100n, 1850n, true, 1850n, {
                        value: 3000,
                    })
            );
            expect(await orderBook.updateOrderExecutor(owner.address, true));

            await expect(orderBook.executeIncreaseOrder(0n, owner.address))
                .to.revertedWithCustomError(orderBook, "InvalidMarketPriceToTrigger")
                .withArgs(1800n, 1850n);

            // long: use max price
            // triggerAbove: false
            // triggerPrice: 1850
            // should not trigger as 1900 > 1850
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1850n, false, 1850n, {
                        value: 3000,
                    })
            );
            await expect(orderBook.executeIncreaseOrder(1n, owner.address))
                .to.revertedWithCustomError(orderBook, "InvalidMarketPriceToTrigger")
                .withArgs(1900n, 1850n);
        });

        it("should revert if trade price is not met", async () => {
            const {owner, orderBook, pool, otherAccount1, router} = await loadFixture(deployFixture);
            expect(await orderBook.updateOrderExecutor(owner.address, true));
            // short when price is higher
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_SHORT, 100n, 100n, 1850n, true, 1840n, {
                        value: 3000,
                    })
            );
            expect(await pool.setMarketPriceX96(1849n, 1851n));
            expect(await router.setTradePriceX96(1830n));
            await expect(orderBook.executeIncreaseOrder(0n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidTradePrice")
                .withArgs(1830n, 1840n);

            // long when price is lower
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1850n, false, 1860n, {
                        value: 3000,
                    })
            );
            expect(await router.setTradePriceX96(1870n));
            await expect(orderBook.executeIncreaseOrder(1n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidTradePrice")
                .withArgs(1870n, 1860n);
        });

        it("should revert if pool is malformed and will drain all sent gas", async () => {
            const {owner, pool, otherAccount1, orderBookWithBadRouter} = await loadFixture(deployFixture);
            expect(await orderBookWithBadRouter.updateOrderExecutor(owner.address, true));
            expect(await pool.setMarketPriceX96(1900n, 1800n));
            // short when price is higher
            expect(
                await orderBookWithBadRouter
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_SHORT, 100n, 100n, 1901n, false, 1920n, {
                        value: 3000,
                    })
            );
            // gas drained
            await expect(orderBookWithBadRouter.executeIncreaseOrder(0n, owner.address)).to.be.revertedWithoutReason();
        });

        it("should pass", async () => {
            const {orderBook, pool, owner, otherAccount1, USDC, router} = await loadFixture(deployFixture);
            expect(await orderBook.updateOrderExecutor(owner.address, true));
            expect(await pool.setMarketPriceX96(1900n, 1800n));

            // long: use max price(1900)
            // triggerAbove: false
            // triggerPrice: 1901
            // acceptableTradePrice: 1920
            // should trigger
            // expect pass
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createIncreaseOrder(pool.address, SIDE_LONG, 100n, 100n, 1901n, false, 1920n, {
                        value: 3000,
                    })
            );

            expect(await router.setTradePriceX96(1910n));

            await expect(orderBook.executeIncreaseOrder(0n, owner.address))
                .to.changeTokenBalances(USDC, [orderBook, pool], ["-100", "100"])
                .to.changeEtherBalances([orderBook, owner], ["-3000", "3000"])
                .to.emit(orderBook, "IncreaseOrderExecuted")
                .withArgs(0n, 1900n, owner.address);

            let order = await orderBook.increaseOrders(0n);
            expect(order.account).eq(ethers.constants.AddressZero);
        });
    });

    describe("#createDecreaseOrder", async () => {
        it("should revert if insufficient or incorrect execution fee", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            // executionFee is insufficient
            await expect(
                orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1000n,
                        true,
                        1000n,
                        otherAccount1.address,
                        {
                            value: 2000,
                        }
                    )
            ).to.be.revertedWithCustomError(orderBook, "InsufficientExecutionFee");
        });

        it("should pass", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            let side = SIDE_LONG;
            for (let i = 0; i < 10; i++) {
                await expect(
                    orderBook
                        .connect(otherAccount1)
                        .createDecreaseOrder(
                            pool.address,
                            side,
                            100n,
                            100n,
                            1000n,
                            true,
                            1000n,
                            otherAccount1.address,
                            {
                                value: 3000,
                            }
                        )
                )
                    .to.changeEtherBalances([orderBook, otherAccount1], ["3000", "-3000"])
                    .to.emit(orderBook, "DecreaseOrderCreated")
                    .withArgs(
                        otherAccount1.address,
                        pool.address,
                        side,
                        100n,
                        100n,
                        1000n,
                        true,
                        1000n,
                        otherAccount1.address,
                        3000n,
                        i
                    );

                expect(await orderBook.decreaseOrdersIndexNext()).to.eq(i + 1);
                expect(await orderBook.decreaseOrders(i)).to.deep.eq([
                    otherAccount1.address,
                    pool.address,
                    side,
                    100n,
                    100n,
                    1000n,
                    true,
                    1000n,
                    otherAccount1.address,
                    3000n,
                ]);
                side = (side % 2) + 1;
            }
            expect(await orderBook.decreaseOrdersIndexNext()).eq(10);
        });
    });

    describe("#updateDecreaseOrder", async () => {
        it("should revert with 'Forbidden' if sender is not request owner", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1000n,
                        true,
                        1000n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            await expect(orderBook.updateDecreaseOrder(0n, 2000n, 300n)).to.be.revertedWithCustomError(
                orderBook,
                "Forbidden"
            );
        });

        it("should pass", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1000n,
                        true,
                        1000n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            await expect(orderBook.connect(otherAccount1).updateDecreaseOrder(0n, 2000n, 3000n))
                .to.emit(orderBook, "DecreaseOrderUpdated")
                .withArgs(0n, 2000n, 3000n);
            let order = await orderBook.decreaseOrders(0n);
            expect(order.triggerMarketPriceX96).eq(2000n);
            expect(order.acceptableTradePriceX96).eq(3000n);
        });
    });

    describe("#cancelDecreaseOrder", async () => {
        it("should revert with 'Forbidden' if caller is not request owner nor order executor", async () => {
            const {orderBook, pool, otherAccount1, otherAccount2} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1000n,
                        true,
                        1000n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            await expect(
                orderBook.connect(otherAccount2).cancelDecreaseOrder(0n, otherAccount2.address)
            ).to.be.revertedWithCustomError(orderBook, "Forbidden");
        });

        it("should revert if order not exists", async () => {
            const {orderBook, otherAccount1} = await loadFixture(deployFixture);
            await expect(orderBook.cancelDecreaseOrder(0n, otherAccount1.address))
                .to.be.revertedWithCustomError(orderBook, "OrderNotExists")
                .withArgs(0n);
        });

        it("should pass", async () => {
            const {orderBook, pool, otherAccount1, owner} = await loadFixture(deployFixture);
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1000n,
                        true,
                        1000n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            await expect(orderBook.connect(otherAccount1).cancelDecreaseOrder(0n, otherAccount1.address))
                .changeEtherBalances([orderBook, otherAccount1], ["-3000", "3000"])
                .to.emit(orderBook, "DecreaseOrderCancelled")
                .withArgs(0n, otherAccount1.address);
            let order = await orderBook.decreaseOrders(0n);
            expect(order.account).to.eq(ethers.constants.AddressZero);

            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1000n,
                        true,
                        1000n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            // executor is now able to cancel orders
            expect(await orderBook.updateOrderExecutor(owner.address, true));

            await expect(orderBook.cancelDecreaseOrder(1n, owner.address))
                .changeEtherBalances([orderBook, owner], ["-3000", "3000"])
                .to.emit(orderBook, "DecreaseOrderCancelled")
                .withArgs(1n, owner.address);
            order = await orderBook.decreaseOrders(1n);
            expect(order.account).to.eq(ethers.constants.AddressZero);
        });
    });

    describe("#executeDecreaseOrder", async () => {
        it("should revert if trigger price is not met", async () => {
            const {orderBook, pool, owner, otherAccount1} = await loadFixture(deployFixture);
            expect(await orderBook.updateOrderExecutor(owner.address, true));
            // 1. long, take-profit order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1950n,
                        true,
                        1950n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            // expect not trigger since 1900n < 1950n
            expect(await pool.setMarketPriceX96(2000n, 1900n));
            await expect(orderBook.executeDecreaseOrder(0n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidMarketPriceToTrigger")
                .withArgs(1900n, 1950n);

            // 2. long, stop-loss order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1850n,
                        false,
                        1850n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            expect(await pool.setMarketPriceX96(2000n, 1900n));
            await expect(orderBook.executeDecreaseOrder(1n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidMarketPriceToTrigger")
                .withArgs(1900n, 1850n);

            // 3. short, take-profit order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_SHORT,
                        100n,
                        100n,
                        1950n,
                        false,
                        1950n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            expect(await pool.setMarketPriceX96(2000n, 1900n));
            // expect not trigger since 2000n > 1950n
            await expect(orderBook.executeDecreaseOrder(2n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidMarketPriceToTrigger")
                .withArgs(2000n, 1950n);

            // 4. short, stop-loss order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_SHORT,
                        100n,
                        100n,
                        2200n,
                        true,
                        2200n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            // 1930n < 2200n, should not trigger
            await pool.setMarketPriceX96(1930n, 1920n);
            await expect(orderBook.executeDecreaseOrder(3n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidMarketPriceToTrigger")
                .withArgs(1930n, 2200n);
        });

        it("should revert if trade price is not met", async () => {
            const {orderBook, pool, owner, otherAccount1, router} = await loadFixture(deployFixture);
            expect(await orderBook.updateOrderExecutor(owner.address, true));
            // 1. long, take-profit order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1950n,
                        true,
                        1940n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            // 1960 > 1950, trigger
            expect(await pool.setMarketPriceX96(1980n, 1960n));
            // Minimum acceptable trade price is 1940, but actual is 1930, should revert
            expect(await router.setTradePriceX96(1930n));
            await expect(orderBook.executeDecreaseOrder(0n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidTradePrice")
                .withArgs(1930n, 1940n);
            expect(await router.setTradePriceX96(1945n));
            await expect(orderBook.executeDecreaseOrder(0n, owner.address))
                .to.changeEtherBalances([orderBook, owner], ["-3000", "3000"])
                .to.emit(orderBook, "DecreaseOrderExecuted")
                .withArgs(0n, 1960n, owner.address);

            // 2. long, stop-loss order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_LONG,
                        100n,
                        100n,
                        1850n,
                        false,
                        1840n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            // 1840 < 1850, trigger
            expect(await pool.setMarketPriceX96(2000n, 1840n));
            // Minimum acceptable trade price is 1840, but actual is 1830, revert
            expect(await router.setTradePriceX96(1830n));
            await expect(orderBook.executeDecreaseOrder(1n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidTradePrice")
                .withArgs(1830n, 1840n);
            expect(await router.setTradePriceX96(1845n));
            await expect(orderBook.executeDecreaseOrder(1n, owner.address))
                .to.changeEtherBalances([orderBook, owner], ["-3000", "3000"])
                .to.emit(orderBook, "DecreaseOrderExecuted")
                .withArgs(1n, 1840n, owner.address);

            // 3. short, take-profit order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_SHORT,
                        100n,
                        100n,
                        1950n,
                        false,
                        1960n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            // 1940 < 1950, trigger
            expect(await pool.setMarketPriceX96(1940n, 1930n));
            expect(await router.setTradePriceX96(1970n));
            await expect(orderBook.executeDecreaseOrder(2n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidTradePrice")
                .withArgs(1970n, 1960n);

            expect(await router.setTradePriceX96(1955n));
            await expect(orderBook.executeDecreaseOrder(2n, owner.address))
                .to.changeEtherBalances([orderBook, owner], ["-3000", "3000"])
                .to.emit(orderBook, "DecreaseOrderExecuted")
                .withArgs(2n, 1940n, owner.address);

            // 4. short, stop-loss order
            expect(
                await orderBook
                    .connect(otherAccount1)
                    .createDecreaseOrder(
                        pool.address,
                        SIDE_SHORT,
                        100n,
                        100n,
                        2200n,
                        true,
                        2250n,
                        otherAccount1.address,
                        {
                            value: 3000,
                        }
                    )
            );
            // 2300 > 2200, trigger
            await pool.setMarketPriceX96(2300n, 2000n);
            await router.setTradePriceX96(2300n);
            await expect(orderBook.executeDecreaseOrder(3n, owner.address))
                .to.be.revertedWithCustomError(orderBook, "InvalidTradePrice")
                .withArgs(2300n, 2250n);

            expect(await router.setTradePriceX96(2240n));
            await expect(orderBook.executeDecreaseOrder(3n, owner.address))
                .to.changeEtherBalances([orderBook, owner], ["-3000", "3000"])
                .to.emit(orderBook, "DecreaseOrderExecuted")
                .withArgs(3n, 2300n, owner.address);
        });
    });

    describe("#createTakeProfitAndStopLossOrders", async () => {
        it("should revert if execution fee is invalid", async () => {
            const {orderBook, pool, owner} = await loadFixture(deployFixture);
            // fee0 is insufficient
            await expect(
                orderBook.createTakeProfitAndStopLossOrders(
                    pool.address,
                    SIDE_LONG,
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    owner.address,
                    {value: 5000n}
                )
            )
                .to.be.revertedWithCustomError(orderBook, "InsufficientExecutionFee")
                .withArgs(2500n, 3000n);

            await expect(
                orderBook.createTakeProfitAndStopLossOrders(
                    pool.address,
                    SIDE_LONG,
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    owner.address,
                    {value: 5001n}
                )
            )
                .to.be.revertedWithCustomError(orderBook, "InsufficientExecutionFee")
                .withArgs(2500n, 3000n);

            await expect(
                orderBook.createTakeProfitAndStopLossOrders(
                    pool.address,
                    SIDE_LONG,
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    owner.address,
                    {value: 5003n}
                )
            )
                .to.be.revertedWithCustomError(orderBook, "InsufficientExecutionFee")
                .withArgs(2501n, 3000n);
            await expect(
                orderBook.createTakeProfitAndStopLossOrders(
                    pool.address,
                    SIDE_LONG,
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    [2000n, 2000n],
                    owner.address,
                    {value: 1n}
                )
            )
                .to.be.revertedWithCustomError(orderBook, "InsufficientExecutionFee")
                .withArgs(0n, 3000n);
        });

        it("should pass", async () => {
            const {orderBook, pool, otherAccount1} = await loadFixture(deployFixture);

            for (let i = 0; i < 10; i++) {
                await expect(
                    orderBook
                        .connect(otherAccount1)
                        .createTakeProfitAndStopLossOrders(
                            pool.address,
                            SIDE_LONG,
                            [2000n, 2500n],
                            [2000n, 2500n],
                            [2000n, 2500n],
                            [2000n, 2500n],
                            otherAccount1.address,
                            {value: 6000n}
                        )
                )
                    .to.changeEtherBalances([orderBook, otherAccount1], ["6000", "-6000"])
                    .to.emit(orderBook, "DecreaseOrderCreated")
                    .withArgs(
                        otherAccount1.address,
                        pool.address,
                        SIDE_LONG,
                        2000n,
                        2000n,
                        2000n,
                        true,
                        2000n,
                        otherAccount1.address,
                        3000n,
                        2 * i
                    )
                    .to.emit(orderBook, "DecreaseOrderCreated")
                    .withArgs(
                        otherAccount1.address,
                        pool.address,
                        SIDE_LONG,
                        2500n,
                        2500n,
                        2500n,
                        false,
                        2500n,
                        otherAccount1.address,
                        3000n,
                        2 * i + 1
                    );

                expect(await orderBook.decreaseOrdersIndexNext()).to.eq(2 * i + 2);

                expect(await orderBook.decreaseOrders(2 * i)).to.deep.eq([
                    otherAccount1.address,
                    pool.address,
                    SIDE_LONG,
                    2000n,
                    2000n,
                    2000n,
                    true,
                    2000n,
                    otherAccount1.address,
                    3000n,
                ]);

                expect(await orderBook.decreaseOrders(2 * i + 1)).to.deep.eq([
                    otherAccount1.address,
                    pool.address,
                    SIDE_LONG,
                    2500n,
                    2500n,
                    2500n,
                    false,
                    2500n,
                    otherAccount1.address,
                    3000n,
                ]);
            }

            expect(await orderBook.decreaseOrdersIndexNext()).eq(20n);
        });
    });
});
