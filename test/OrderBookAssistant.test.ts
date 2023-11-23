import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {ethers} from "hardhat";
import {expect} from "chai";
import {SIDE_LONG, SIDE_SHORT} from "./shared/Constants";

describe("OrderBookAssistant", () => {
    const POOL = "0x0000000000000000000000000000000000000001";

    async function deployFixture() {
        const [gov, executor] = await ethers.getSigners();

        const ERC20Test = await ethers.getContractFactory("ERC20Test");
        const USDC = await ERC20Test.connect(executor).deploy("USDC", "USDC", 6, 100_000_000n);
        await USDC.deployed();

        const Router = await ethers.getContractFactory("Router");
        const router = await Router.deploy(
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero
        );
        await router.deployed();

        const OrderBook = await ethers.getContractFactory("OrderBook");
        const orderBook = await OrderBook.deploy(USDC.address, router.address, 20000n);
        await orderBook.deployed();

        await router.registerPlugin(orderBook.address);
        await router.connect(executor).approvePlugin(orderBook.address);
        await USDC.connect(executor).approve(router.address, ethers.constants.MaxUint256);

        const OrderBookAssistant = await ethers.getContractFactory("OrderBookAssistant");
        const orderBookAssistant = await OrderBookAssistant.deploy(orderBook.address);
        await orderBookAssistant.deployed();

        await orderBook.updateOrderExecutor(orderBookAssistant.address, true);

        return {
            gov,
            executor,
            USDC,
            orderBook,
            orderBookAssistant,
        };
    }

    describe("#cancelIncreaseOrderBatch", () => {
        it("should revert if order not exists", async () => {
            const {executor, orderBookAssistant} = await loadFixture(deployFixture);

            await expect(
                orderBookAssistant.connect(executor).cancelIncreaseOrderBatch([1])
            ).to.be.revertedWithCustomError(orderBookAssistant, "Forbidden");
        });

        it("should revert if order not exists (batch)", async () => {
            const {executor, orderBook, orderBookAssistant} = await loadFixture(deployFixture);

            await orderBook.connect(executor).createIncreaseOrder(POOL, SIDE_LONG, 1000n, 1n, 1n, true, 1n, {
                value: 20000n,
            });
            await orderBook.connect(executor).createIncreaseOrder(POOL, SIDE_SHORT, 1000n, 1n, 1n, true, 1n, {
                value: 20000n,
            });

            await expect(
                orderBookAssistant.connect(executor).cancelIncreaseOrderBatch([0, 2, 1])
            ).to.be.revertedWithCustomError(orderBookAssistant, "Forbidden");
        });

        it("should pass", async () => {
            const {executor, orderBook, orderBookAssistant} = await loadFixture(deployFixture);

            await orderBook.connect(executor).createIncreaseOrder(POOL, SIDE_LONG, 1000n, 1n, 1n, true, 1n, {
                value: 20000n,
            });
            await orderBook.connect(executor).createIncreaseOrder(POOL, SIDE_SHORT, 1000n, 1n, 1n, true, 1n, {
                value: 20000n,
            });

            await orderBookAssistant.connect(executor).cancelIncreaseOrderBatch([0, 1]);

            await expect(orderBookAssistant.connect(executor).cancelIncreaseOrderBatch([0])).to.revertedWithCustomError(
                orderBookAssistant,
                "Forbidden"
            );
            await expect(orderBookAssistant.connect(executor).cancelIncreaseOrderBatch([1])).to.revertedWithCustomError(
                orderBookAssistant,
                "Forbidden"
            );
        });
    });

    describe("#cancelDecreaseOrderBatch", () => {
        it("should revert if order not exists", async () => {
            const {executor, orderBookAssistant} = await loadFixture(deployFixture);

            await expect(
                orderBookAssistant.connect(executor).cancelDecreaseOrderBatch([1])
            ).to.be.revertedWithCustomError(orderBookAssistant, "Forbidden");
        });

        it("should revert if order not exists (batch)", async () => {
            const {executor, orderBook, orderBookAssistant} = await loadFixture(deployFixture);

            await orderBook
                .connect(executor)
                .createDecreaseOrder(POOL, SIDE_LONG, 1000n, 1n, 1n, true, 1n, executor.address, {
                    value: 20000n,
                });
            await orderBook
                .connect(executor)
                .createDecreaseOrder(POOL, SIDE_SHORT, 1000n, 1n, 1n, true, 1n, executor.address, {
                    value: 20000n,
                });

            await expect(
                orderBookAssistant.connect(executor).cancelDecreaseOrderBatch([0, 2, 1])
            ).to.be.revertedWithCustomError(orderBookAssistant, "Forbidden");
        });

        it("should pass", async () => {
            const {executor, orderBook, orderBookAssistant} = await loadFixture(deployFixture);

            await orderBook
                .connect(executor)
                .createDecreaseOrder(POOL, SIDE_LONG, 1000n, 1n, 1n, true, 1n, executor.address, {
                    value: 20000n,
                });
            await orderBook
                .connect(executor)
                .createDecreaseOrder(POOL, SIDE_SHORT, 1000n, 1n, 1n, true, 1n, executor.address, {
                    value: 20000n,
                });

            await orderBookAssistant.connect(executor).cancelDecreaseOrderBatch([0, 1]);

            await expect(orderBookAssistant.connect(executor).cancelDecreaseOrderBatch([0])).to.revertedWithCustomError(
                orderBookAssistant,
                "Forbidden"
            );
            await expect(orderBookAssistant.connect(executor).cancelDecreaseOrderBatch([1])).to.revertedWithCustomError(
                orderBookAssistant,
                "Forbidden"
            );
        });
    });
});
