import {ethers} from "hardhat";
import {time, mine} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {VoteType} from "./constants";
import {VeEQU} from "../../typechain-types";

describe("EquationTimelockController", () => {
    async function deployFixture() {
        const [s0, s1, s2] = await ethers.getSigners();

        const Governable = await ethers.getContractFactory("GovernableTest");
        const governable = await Governable.deploy();

        const veEQU = (await ethers.deployContract("veEQU")) as VeEQU;
        await veEQU.setMinter(s0.address, true);
        await veEQU.delegate(s0.address);
        await veEQU.mint(s0.address, 10_000n * 10n ** 18n);

        const EquationTimelockController = await ethers.getContractFactory("EquationTimelockController");
        const timelockController = await EquationTimelockController.deploy(
            time.duration.days(2),
            [],
            [s1.address],
            s0.address
        );

        const nonce = await s0.getTransactionCount();
        const equGovernorAddress = ethers.utils.getContractAddress({from: s0.address, nonce: nonce + 1});
        const EFCGovernor = await ethers.getContractFactory("EFCGovernor");
        const EQUGovernor = await ethers.getContractFactory("EQUGovernor");
        const efcGovernor = await EFCGovernor.deploy(veEQU.address, equGovernorAddress, timelockController.address);
        const equGovernor = await EQUGovernor.deploy(veEQU.address, efcGovernor.address);

        await timelockController.grantRole(timelockController.PROPOSER_ROLE(), efcGovernor.address);
        await timelockController.grantRole(timelockController.CANCELLER_ROLE(), efcGovernor.address);
        await timelockController.revokeRole(timelockController.TIMELOCK_ADMIN_ROLE(), efcGovernor.address);

        return {s0, s1, s2, governable, timelockController, efcGovernor, equGovernor};
    }

    it("should revert with the right error if the sender is not gov", async () => {
        const {s0, s1, governable} = await deployFixture();
        expect(await governable.gov()).to.equal(s0.address);
        await expect(governable.connect(s1).onlyGovTest()).to.be.revertedWithCustomError(governable, "Forbidden");
    });

    it("should successfully call the function if the sender accept gov", async () => {
        const {s1, governable} = await deployFixture();
        await governable.changeGov(s1.address);
        await governable.connect(s1).acceptGov();
        await expect(governable.connect(s1).onlyGovTest()).not.to.be.reverted;
    });

    it("should successfully execute the proposal which requires gov to execute if the timelock controller accepts gov", async () => {
        const {s1, governable, timelockController, efcGovernor, equGovernor} = await deployFixture();
        await governable.changeGov(timelockController.address);
        await timelockController.acceptGov(governable.address);
        expect(await governable.gov()).to.equal(timelockController.address);

        const targets = [governable.address];
        const values = [0];
        const calldatas = [governable.interface.encodeFunctionData("onlyGovTest")];
        const description = "only gov test";
        const descriptionHash = ethers.utils.id(description);
        await efcGovernor.propose(targets, values, calldatas, description);
        const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
        await mine();
        await efcGovernor.castVote(proposalId, VoteType.For);
        await equGovernor.castVote(proposalId, VoteType.For);

        await mine(await equGovernor.votingPeriod());
        await efcGovernor.queue(targets, values, calldatas, descriptionHash);

        await time.increase(await timelockController.getMinDelay());
        const predecessor = ethers.utils.formatBytes32String("");
        await expect(
            timelockController.connect(s1).executeBatch(targets, values, calldatas, predecessor, descriptionHash)
        ).not.to.be.reverted;
    });
});
