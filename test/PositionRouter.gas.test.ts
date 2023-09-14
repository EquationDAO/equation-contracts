import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";
import {ethers} from "hardhat";

import {SIDE_LONG, SIDE_SHORT} from "./shared/Constants";
import {expectSnapshotGasCost} from "./shared/snapshotGasCost";

describe("PositionRouter gas tests", function () {
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

        // router can transfer owner's USDC
        await USDC.connect(otherAccount1).approve(router.address, 100_000_000n);

        const PositionRouter = await ethers.getContractFactory("PositionRouter");
        const positionRouter = await PositionRouter.deploy(USDC.address, router.address, defaultMinExecutionFee);
        await positionRouter.deployed();

        return {
            owner,
            otherAccount1,
            otherAccount2,
            router,
            positionRouter,
            USDC,
            ETH,
            pool,
        };
    }

    it("createIncreasePosition", async () => {
        const {positionRouter, pool, otherAccount1} = await loadFixture(deployFixture);
        await expectSnapshotGasCost(
            positionRouter.connect(otherAccount1).createIncreasePosition(pool.address, SIDE_LONG, 100n, 100n, 100n, {
                value: 3000,
            })
        );
    });

    it("executeIncreasePosition", async () => {
        const {positionRouter, pool, otherAccount1, router} = await loadFixture(deployFixture);
        await positionRouter.updateDelayValues(0n, 0n, 600n);
        await positionRouter
            .connect(otherAccount1)
            .createIncreasePosition(pool.address, SIDE_SHORT, 100n, 100n, 1790n, {
                value: 3000,
            });
        await router.setTradePriceX96(1795n);
        await expectSnapshotGasCost(
            positionRouter.connect(otherAccount1).executeIncreasePosition(0n, otherAccount1.address)
        );
    });
});
