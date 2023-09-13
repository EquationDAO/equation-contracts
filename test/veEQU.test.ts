import {expect} from "chai";
import {ethers} from "hardhat";
import {loadFixture, mine, time} from "@nomicfoundation/hardhat-network-helpers";
import {VeEQU} from "../typechain-types";

describe("veEQU", function () {
    async function deployFixture() {
        const [s0, s1] = await ethers.getSigners();
        const veEQU = (await ethers.deployContract("veEQU")) as VeEQU;
        await veEQU.setMinter(s0.address, true);
        return {s0, s1, veEQU};
    }

    describe("#constructor", function () {
        it("should have the right state after constructor", async () => {
            const {s0, s1, veEQU} = await loadFixture(deployFixture);
            expect(await veEQU.name()).to.equal("veEQU");
            expect(await veEQU.symbol()).to.equal("veEQU");
            expect(await veEQU.decimals()).to.equal(18);
            expect(await veEQU.totalSupply()).to.equal(0);
            expect(await veEQU.balanceOf(s0.address)).to.equal(0);
            expect(await veEQU.balanceOf(s1.address)).to.equal(0);
            expect(await veEQU.minters(s0.address)).to.true;
        });
    });

    describe("#mint", async () => {
        it("should revert with the right error if the sender is not the owner", async () => {
            const {s1, veEQU} = await loadFixture(deployFixture);
            await expect(veEQU.connect(s1).mint(s1.address, 1000n * 10n ** 18n)).to.be.revertedWithCustomError(
                veEQU,
                "NotMinter"
            );
        });
        it("should mint the right amount of tokens", async () => {
            const {s0, veEQU} = await loadFixture(deployFixture);
            await veEQU.mint(s0.address, 1000n * 10n ** 18n);
            expect(await veEQU.totalSupply()).to.equal(1000n * 10n ** 18n);
            expect(await veEQU.balanceOf(s0.address)).to.equal(1000n * 10n ** 18n);
        });
        it("should emit the right event", async () => {
            const {s0, veEQU} = await loadFixture(deployFixture);
            await expect(veEQU.mint(s0.address, 1000n * 10n ** 18n))
                .to.emit(veEQU, "Transfer")
                .withArgs(ethers.constants.AddressZero, s0.address, 1000n * 10n ** 18n);
        });
        it("should have the right voting power after mint", async () => {
            const {s0, s1, veEQU} = await loadFixture(deployFixture);
            await veEQU.delegate(s0.address);
            expect(await veEQU.getVotes(s0.address)).to.equal(0);
            await expect(veEQU.mint(s0.address, 1000n * 10n ** 18n))
                .to.emit(veEQU, "DelegateVotesChanged")
                .withArgs(s0.address, 0, 1000n * 10n ** 18n);
            expect(await veEQU.getVotes(s0.address)).to.equal(1000n * 10n ** 18n);
            await mine();
            const latestBlock = await time.latestBlock();
            expect(await veEQU.getPastVotes(s0.address, latestBlock - 1)).to.equal(1000n * 10n ** 18n);
            expect(await veEQU.getPastTotalSupply(latestBlock - 1)).to.equal(1000n * 10n ** 18n);
        });
    });

    describe("#burn", async () => {
        it("should revert with the right error if the sender is not the owner", async () => {
            const {s1, veEQU} = await loadFixture(deployFixture);
            await expect(veEQU.connect(s1).burn(s1.address, 1000n * 10n ** 18n)).to.be.revertedWithCustomError(
                veEQU,
                "NotMinter"
            );
        });
        it("should burn the right amount of tokens", async () => {
            const {s0, veEQU} = await loadFixture(deployFixture);
            await veEQU.mint(s0.address, 1000n * 10n ** 18n);
            await veEQU.burn(s0.address, 1000n * 10n ** 18n);
            expect(await veEQU.totalSupply()).to.equal(0);
            expect(await veEQU.balanceOf(s0.address)).to.equal(0);
        });
        it("should emit the right event", async () => {
            const {s0, veEQU} = await loadFixture(deployFixture);
            await veEQU.mint(s0.address, 1000n * 10n ** 18n);
            await expect(veEQU.burn(s0.address, 1000n * 10n ** 18n))
                .to.emit(veEQU, "Transfer")
                .withArgs(s0.address, ethers.constants.AddressZero, 1000n * 10n ** 18n);
        });
        it("should have the right voting power after burn", async () => {
            const {s0, veEQU} = await loadFixture(deployFixture);
            await veEQU.mint(s0.address, 1000n * 10n ** 18n);
            await veEQU.delegate(s0.address);
            expect(await veEQU.getVotes(s0.address)).to.equal(1000n * 10n ** 18n);
            await expect(veEQU.burn(s0.address, 1000n * 10n ** 18n))
                .to.emit(veEQU, "DelegateVotesChanged")
                .withArgs(s0.address, 1000n * 10n ** 18n, 0);
            expect(await veEQU.getVotes(s0.address)).to.equal(0);
            await mine();
            const latestBlock = await time.latestBlock();
            expect(await veEQU.getPastVotes(s0.address, latestBlock - 1)).to.equal(0);
            expect(await veEQU.getPastTotalSupply(latestBlock - 1)).to.equal(0);
        });
    });

    describe("#transfer", async () => {
        it("should revert with the right error", async () => {
            const {s0, veEQU} = await loadFixture(deployFixture);
            await expect(veEQU.connect(s0).transfer(s0.address, 1000n * 10n ** 18n)).to.be.revertedWithCustomError(
                veEQU,
                "Unsupported"
            );
        });
    });

    describe("#transferFrom", async () => {
        it("should revert with the right error", async () => {
            const {s0, veEQU} = await loadFixture(deployFixture);
            await expect(
                veEQU.connect(s0).transferFrom(s0.address, s0.address, 1000n * 10n ** 18n)
            ).to.be.revertedWithCustomError(veEQU, "Unsupported");
        });
    });
});
