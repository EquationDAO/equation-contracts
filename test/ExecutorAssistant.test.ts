import {ethers} from "hardhat";
import {expect} from "chai";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {SIDE_LONG} from "./shared/Constants";

describe("ExecutorAssistant", () => {
    async function deployFixture() {
        const ERC20 = await ethers.getContractFactory("ERC20Test");
        const usd = await ERC20.deploy("USDC", "USDC", 6, 100000000n * 10n ** 6n);
        await usd.deployed();

        const Router = await ethers.getContractFactory("Router");
        const router = await Router.deploy(
            ethers.constants.AddressZero,
            ethers.constants.AddressZero,
            ethers.constants.AddressZero
        );
        await router.deployed();

        const PositionRouter = await ethers.getContractFactory("PositionRouter");
        const positionRouter = await PositionRouter.deploy(usd.address, router.address, 0);
        await positionRouter.deployed();

        const ExecutorAssistant = await ethers.getContractFactory("ExecutorAssistant");
        const executorAssistant = await ExecutorAssistant.deploy(positionRouter.address);
        await executorAssistant.deployed();

        await usd.approve(router.address, 100000000n * 10n ** 6n);
        await router.registerPlugin(positionRouter.address);
        await router.approvePlugin(positionRouter.address);
        return {
            usd,
            router,
            positionRouter,
            executorAssistant,
        };
    }

    describe("#calculateNextMulticall", () => {
        it("should return -1 if the index is equal to index next", async () => {
            const {executorAssistant} = await loadFixture(deployFixture);
            const {pools, indexPerOperations} = await executorAssistant.calculateNextMulticall(10);
            expect(pools.length).to.eq(0);
            expect(indexPerOperations.length).to.eq(7);
            for (let item of indexPerOperations) {
                expect(item.index).to.eq(0);
                expect(item.indexNext).to.eq(0);
                expect(item.indexEnd).to.eq(0);
            }
        });

        it("should return the correct result if the index is not equal to index next", async () => {
            const {positionRouter, executorAssistant} = await loadFixture(deployFixture);
            await positionRouter.createOpenLiquidityPosition("0x1111111111111111111111111111111111111111", 1e10, 1e10);
            await positionRouter.createOpenLiquidityPosition("0x1111111111111111111111111111111111111112", 1e10, 1e10);
            await positionRouter.createOpenLiquidityPosition("0x1111111111111111111111111111111111111111", 1e10, 1e10);

            await positionRouter.createDecreasePosition(
                "0x1111111111111111111111111111111111111113",
                SIDE_LONG,
                1e10,
                1e10,
                0n,
                ethers.constants.AddressZero
            );
            await positionRouter.createDecreasePosition(
                "0x1111111111111111111111111111111111111111",
                SIDE_LONG,
                1e10,
                1e10,
                0n,
                ethers.constants.AddressZero
            );
            await positionRouter.createDecreasePosition(
                "0x1111111111111111111111111111111111111112",
                SIDE_LONG,
                1e10,
                1e10,
                0n,
                ethers.constants.AddressZero
            );
            await positionRouter.createDecreasePosition(
                "0x1111111111111111111111111111111111111114",
                SIDE_LONG,
                1e10,
                1e10,
                0n,
                ethers.constants.AddressZero
            );

            const {pools, indexPerOperations} = await executorAssistant.calculateNextMulticall(3);
            expect(pools.length).to.eq(6);
            expect(pools.slice(0, 6)).to.deep.eq([
                "0x1111111111111111111111111111111111111111",
                "0x1111111111111111111111111111111111111112",
                "0x1111111111111111111111111111111111111111",
                "0x1111111111111111111111111111111111111113",
                "0x1111111111111111111111111111111111111111",
                "0x1111111111111111111111111111111111111112",
            ]);
            expect(indexPerOperations.length).to.eq(7);
            expect(indexPerOperations.map((ipo) => ipo.index)).to.deep.eq([0, 0, 0, 0, 0, 0, 0]);
            expect(indexPerOperations.map((ipo) => ipo.indexNext)).to.deep.eq([3, 0, 0, 0, 0, 0, 4]);
            expect(indexPerOperations.map((ipo) => ipo.indexEnd)).to.deep.eq([3, 0, 0, 0, 0, 0, 3]);
        });
    });
});
