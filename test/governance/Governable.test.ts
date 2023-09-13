import {ethers} from "hardhat";
import {expect} from "chai";
import {loadFixture} from "@nomicfoundation/hardhat-network-helpers";

describe("Governable", () => {
    async function deployFixture() {
        const [owner, other] = await ethers.getSigners();

        const Governable = await ethers.getContractFactory("GovernableTest");
        const governable = await Governable.deploy();
        await governable.deployed();
        return {owner, other, governable};
    }

    describe("#constructor", () => {
        it("should set sender as gov", async () => {
            const {owner, governable} = await loadFixture(deployFixture);
            expect(await governable.gov()).to.eq(owner.address);
        });
    });

    describe("#onlyGov", () => {
        it("should revert if sender is not gov", async () => {
            const {other, governable} = await loadFixture(deployFixture);
            await expect(governable.connect(other).onlyGovTest()).to.revertedWithCustomError(governable, "Forbidden");
        });

        it("should not revert if sender is gov", async () => {
            const {governable} = await loadFixture(deployFixture);
            await expect(governable.onlyGovTest()).to.not.reverted;
        });
    });

    describe("#changeGov", () => {
        it("should revert if sender is not gov", async () => {
            const {owner, other, governable} = await loadFixture(deployFixture);
            await expect(governable.connect(other).changeGov(owner.address)).to.revertedWithCustomError(
                governable,
                "Forbidden"
            );
        });

        it("should emit ChangeGovStarted event", async () => {
            const {owner, other, governable} = await loadFixture(deployFixture);
            await expect(governable.changeGov(other.address))
                .to.emit(governable, "ChangeGovStarted")
                .withArgs(owner.address, other.address);
            await expect(governable.onlyGovTest()).to.not.reverted;
            await expect(governable.connect(other).onlyGovTest()).to.reverted;
        });
    });

    describe("#acceptGov", () => {
        it("should revert if sender is not new gov", async () => {
            const {other, governable} = await loadFixture(deployFixture);
            await expect(governable.acceptGov()).to.revertedWithCustomError(governable, "Forbidden");
            await expect(governable.connect(other).acceptGov()).to.revertedWithCustomError(governable, "Forbidden");
        });

        it("should emit GovChanged event", async () => {
            const {owner, other, governable} = await loadFixture(deployFixture);
            await governable.changeGov(other.address);
            await expect(governable.connect(other).acceptGov())
                .to.emit(governable, "GovChanged")
                .withArgs(owner.address, other.address);

            await expect(governable.onlyGovTest()).to.revertedWithCustomError(governable, "Forbidden");
            await expect(governable.connect(other).onlyGovTest()).to.not.reverted;
        });
    });

    describe("#pendingGov", () => {
        it("should set pending gov if changeGov was called", async () => {
            const {owner, other, governable} = await loadFixture(deployFixture);
            expect(await governable.pendingGov()).to.eq(ethers.constants.AddressZero);
            await governable.changeGov(other.address);
            expect(await governable.pendingGov()).to.eq(other.address);
        });

        it("should delete pending gov if acceptGov was called", async () => {
            const {owner, other, governable} = await loadFixture(deployFixture);
            expect(await governable.pendingGov()).to.eq(ethers.constants.AddressZero);
            await governable.changeGov(other.address);
            expect(await governable.pendingGov()).to.eq(other.address);
            await governable.connect(other).acceptGov();
            expect(await governable.pendingGov()).to.eq(ethers.constants.AddressZero);
        });
    });
});
