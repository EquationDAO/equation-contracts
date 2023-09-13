import {ethers} from "hardhat";
import {loadFixture, mine, time} from "@nomicfoundation/hardhat-network-helpers";
import {expect} from "chai";
import {ERC20Test} from "../../typechain-types";
import {VoteType, ProposalState} from "./constants";

describe("Governor", () => {
    async function deployFixture() {
        const [s0, s1, s2] = await ethers.getSigners();
        const veToken = (await ethers.deployContract("ERC20Test", [
            "veTOKEN",
            "veTOKEN",
            18,
            100n * 10n ** 18n,
        ])) as ERC20Test;
        const TimelockController = await ethers.getContractFactory("EquationTimelockController");
        const timelockController = await TimelockController.deploy(
            time.duration.days(2),
            [],
            [ethers.constants.AddressZero],
            s0.address
        );

        const nonce = await s0.getTransactionCount();
        const equGovernorAddress = ethers.utils.getContractAddress({from: s0.address, nonce: nonce + 1});
        const EFCGovernor = await ethers.getContractFactory("EFCGovernor");
        const EQUGovernor = await ethers.getContractFactory("EQUGovernor");
        const efcGovernor = await EFCGovernor.deploy(veToken.address, equGovernorAddress, timelockController.address);
        const equGovernor = await EQUGovernor.deploy(veToken.address, efcGovernor.address);

        await timelockController.grantRole(timelockController.PROPOSER_ROLE(), efcGovernor.address);
        await timelockController.grantRole(timelockController.CANCELLER_ROLE(), efcGovernor.address);
        await timelockController.revokeRole(timelockController.TIMELOCK_ADMIN_ROLE(), efcGovernor.address);

        await veToken.delegate(s0.address);
        await veToken.mint(s0.address, 10_000n * 10n ** 18n);
        return {s0, s1, s2, veToken, timelockController, efcGovernor, equGovernor};
    }

    async function deployFixtureWithSetVotingDelay(efcVotingDelay: number, equVotingDelay: number) {
        let {s0, s1, s2, veToken, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
        const targets = [efcGovernor.address, equGovernor.address];
        const values = [0n, 0n];
        const calldatas = [
            efcGovernor.interface.encodeFunctionData("setVotingDelay", [efcVotingDelay]),
            equGovernor.interface.encodeFunctionData("setVotingDelay", [equVotingDelay]),
        ];
        const description = "";
        const descriptionHash = ethers.utils.id(description);
        await equGovernor.propose(targets, values, calldatas, description);
        await mine();
        const proposalId = await equGovernor.hashProposal(targets, values, calldatas, descriptionHash);
        await equGovernor.castVote(proposalId, VoteType.For);
        await efcGovernor.castVote(proposalId, VoteType.For);
        await mine(await efcGovernor.votingPeriod());
        await efcGovernor.queue(targets, values, calldatas, descriptionHash);
        await time.increase(await timelockController.getMinDelay());
        await efcGovernor.execute(targets, values, calldatas, descriptionHash);
        return {s0, s1, s2, veToken, timelockController, efcGovernor, equGovernor};
    }

    describe("#constructor", () => {
        it("should have the right state", async () => {
            const {veToken, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            await expect(await efcGovernor.name()).to.equal("EFCGovernor");
            await expect(await efcGovernor.votingDelay()).to.equal(1);
            await expect(await efcGovernor.votingPeriod()).to.equal(50_400n);
            await expect(await efcGovernor.proposalThreshold()).to.equal(10_000n * 10n ** 18n);
            await expect(await efcGovernor["quorumNumerator()"]()).to.equal(5);
            await expect(await efcGovernor["quorumDenominator"]()).to.equal(100);
            await expect(await efcGovernor.token()).to.equal(veToken.address);
            await expect(await efcGovernor.timelock()).to.equal(timelockController.address);

            await expect(await equGovernor.name()).to.equal("EQUGovernor");
            await expect(await equGovernor.votingDelay()).to.equal(1);
            await expect(await equGovernor.votingPeriod()).to.equal(50_400n);
            await expect(await equGovernor.proposalThreshold()).to.equal(10_000n * 10n ** 18n);
            await expect(await equGovernor["quorumNumerator()"]()).to.equal(5);
            await expect(await equGovernor["quorumDenominator"]()).to.equal(100);
            await expect(await equGovernor.token()).to.equal(veToken.address);
        });
    });

    describe("#quorum", () => {
        it("should return the right value", async () => {
            const {veToken, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            const latestBlock = BigInt(await time.latestBlock());
            const totalSupply = (await veToken.totalSupply()).toBigInt();
            const efcQuorumNumerator = (await efcGovernor["quorumNumerator(uint256)"](latestBlock)).toBigInt();
            const efcQuorumDenominator = (await efcGovernor["quorumDenominator"]()).toBigInt();

            const equQuorumNumerator = (await equGovernor["quorumNumerator(uint256)"](latestBlock)).toBigInt();
            const equQuorumDenominator = (await equGovernor["quorumDenominator"]()).toBigInt();
            await mine();
            await expect(await efcGovernor.quorum(latestBlock)).to.equal(
                (totalSupply * efcQuorumNumerator) / efcQuorumDenominator
            );
            await expect(await equGovernor.quorum(latestBlock)).to.equal(
                (totalSupply * equQuorumNumerator) / equQuorumDenominator
            );
        });

        it("should return the right value if the totalSupply is changed", async () => {
            const {s0, veToken, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            await veToken.mint(s0.address, 10_000n * 10n ** 18n);
            const latestBlock = BigInt(await time.latestBlock());
            const totalSupply = (await veToken.totalSupply()).toBigInt();
            const efcQuorumNumerator = (await efcGovernor["quorumNumerator(uint256)"](latestBlock)).toBigInt();
            const efcQuorumDenominator = (await efcGovernor["quorumDenominator"]()).toBigInt();
            const equQuorumNumerator = (await equGovernor["quorumNumerator(uint256)"](latestBlock)).toBigInt();
            const equQuorumDenominator = (await equGovernor["quorumDenominator"]()).toBigInt();
            await mine();
            await expect(await efcGovernor.quorum(latestBlock)).to.equal(
                (totalSupply * efcQuorumNumerator) / efcQuorumDenominator
            );
            await expect(await equGovernor.quorum(latestBlock)).to.equal(
                (totalSupply * equQuorumNumerator) / equQuorumDenominator
            );
        });

        it("should return the right value if the quorumNumerator is changed", async () => {
            const {veToken, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            const targets = [efcGovernor.address, equGovernor.address];
            const values = [0n, 0n];
            const calldatas = [
                efcGovernor.interface.encodeFunctionData("updateQuorumNumerator", [10]),
                equGovernor.interface.encodeFunctionData("updateQuorumNumerator", [10]),
            ];
            const description = "update quorum numerator";
            const descriptionHash = ethers.utils.id(description);
            await efcGovernor.propose(targets, values, calldatas, description);
            const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
            await mine();
            await efcGovernor.castVote(proposalId, VoteType.For);
            await equGovernor.castVote(proposalId, VoteType.For);
            await mine(await efcGovernor.votingPeriod());
            await efcGovernor.queue(targets, values, calldatas, descriptionHash);
            await time.increase(await timelockController.getMinDelay());
            await efcGovernor.execute(targets, values, calldatas, descriptionHash);

            await expect(await efcGovernor["quorumNumerator()"]()).to.equal(10);
            await expect(await equGovernor["quorumNumerator()"]()).to.equal(10);
            const latestBlock = BigInt(await time.latestBlock());
            await expect(await efcGovernor["quorumNumerator(uint256)"](latestBlock)).to.equal(10);
            await expect(await equGovernor["quorumNumerator(uint256)"](latestBlock)).to.equal(10);
            const totalSupply = (await veToken.totalSupply()).toBigInt();
            const efcQuorumNumerator = (await efcGovernor["quorumNumerator(uint256)"](latestBlock)).toBigInt();
            const efcQuorumDenominator = (await efcGovernor["quorumDenominator"]()).toBigInt();
            const equQuorumNumerator = (await equGovernor["quorumNumerator(uint256)"](latestBlock)).toBigInt();
            const equQuorumDenominator = (await equGovernor["quorumDenominator"]()).toBigInt();
            await mine();
            await expect(await efcGovernor.quorum(latestBlock)).to.equal(
                (totalSupply * efcQuorumNumerator) / efcQuorumDenominator
            );
            await expect(await equGovernor.quorum(latestBlock)).to.equal(
                (totalSupply * equQuorumNumerator) / equQuorumDenominator
            );
        });
    });

    describe("#propose", () => {
        it("should revert with the right error if the proposal threshold is not met", async () => {
            const {s2, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            const targets = [s2.address];
            const values = [0n];
            const calldatas = ["0x"];
            const description = "";
            await expect(efcGovernor.connect(s2).propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: proposer votes below proposal threshold"
            );
            await expect(
                efcGovernor.connect(s2).routinePropose(targets, values, calldatas, description)
            ).to.be.revertedWith("Governor: proposer votes below proposal threshold");
            await expect(equGovernor.connect(s2).propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: proposer votes below proposal threshold"
            );
        });

        it("should revert with the right error if the length of targets is not equal to the length of values", async () => {
            const {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            const targets = [s1.address];
            const values = [0n, 0n];
            const calldatas = ["0x"];
            const description = "";
            await expect(efcGovernor.propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: invalid proposal length"
            );
            await expect(efcGovernor.routinePropose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: invalid proposal length"
            );
            await expect(equGovernor.propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: invalid proposal length"
            );
        });

        it("should revert with the right error if the length of targets is not equal to the length of calldatas", async () => {
            const {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            const targets = [s1.address];
            const values = [0n, 0n];
            const calldatas = ["0x", "0x"];
            const description = "";
            await expect(efcGovernor.propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: invalid proposal length"
            );
            await expect(efcGovernor.routinePropose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: invalid proposal length"
            );
            await expect(equGovernor.propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: invalid proposal length"
            );
        });

        it("should revert with the right error if the length of targets is zero", async () => {
            const {efcGovernor, equGovernor} = await loadFixture(deployFixture);
            await expect(efcGovernor.propose([], [], [], "")).to.be.revertedWith("Governor: empty proposal");
            await expect(efcGovernor.routinePropose([], [], [], "")).to.be.revertedWith("Governor: empty proposal");
            await expect(equGovernor.propose([], [], [], "")).to.be.revertedWith("Governor: empty proposal");
        });

        it("should revert with the right error if the proposal already exists", async () => {
            const {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            const targets = [s1.address];
            const values = [0n];
            const calldatas = ["0x"];
            const description = "transfer 100 ECT to s1";
            await efcGovernor.propose(targets, values, calldatas, description);
            await expect(efcGovernor.propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: proposal already exists"
            );
            await expect(efcGovernor.routinePropose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: proposal already exists"
            );
            await expect(equGovernor.propose(targets, values, calldatas, description)).to.be.revertedWith(
                "Governor: proposal already exists"
            );
        });

        it("should emit the right event after successfully create a proposal", async () => {
            const {s0, efcGovernor, equGovernor} = await loadFixture(deployFixture);
            const targets = [s0.address];
            const values = [0n];
            const calldatas = ["0x"];
            const description = "";
            const descriptionHash = ethers.utils.id(description);
            const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
            const latestBlock = BigInt(await time.latestBlock());
            const votingDelay = (await efcGovernor.votingDelay()).toBigInt();
            const votingPeriod = (await efcGovernor.votingPeriod()).toBigInt();
            const snapshot = latestBlock + 1n + votingDelay;
            const deadline = snapshot + votingPeriod;
            await expect(efcGovernor.propose(targets, values, calldatas, description))
                .to.emit(efcGovernor, "ProposalCreated")
                .withArgs(proposalId, s0.address, targets, values, [""], calldatas, snapshot, deadline, description)
                .to.emit(equGovernor, "ProposalCreated")
                .withArgs(
                    proposalId,
                    efcGovernor.address,
                    targets,
                    values,
                    [""],
                    calldatas,
                    snapshot,
                    deadline,
                    description
                );
        });

        describe("#state", () => {
            it("should return the right intermediate state on the way to a successful execution", async () => {
                let {s1, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s1.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Pending);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Pending);
                await mine();
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Pending);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Pending);
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);
                await mine(await efcGovernor.votingDelay());
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Active);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Active);
                await mine(await efcGovernor.votingPeriod());
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Queued);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
                await time.increase(await timelockController.getMinDelay());
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Queued);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
                await efcGovernor.execute(targets, values, calldatas, descriptionHash);
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Executed);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
            });

            it("should return the right state if the efc governor proposal is canceled by the proposer", async () => {
                let {s0, efcGovernor, equGovernor} = await deployFixtureWithSetVotingDelay(50, 50);
                const targets = [s0.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);

                const proposalId = await equGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await efcGovernor.propose(targets, values, calldatas, description);
                await expect(equGovernor.cancel(targets, values, calldatas, descriptionHash)).to.be.revertedWith(
                    "Governor: only proposer can cancel"
                );
                await efcGovernor.cancel(targets, values, calldatas, descriptionHash);
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Canceled);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Canceled);
            });

            it("should return the right state if the equ governor proposal is canceled by the proposer", async () => {
                let {s0, efcGovernor, equGovernor} = await deployFixtureWithSetVotingDelay(50, 50);
                const targets = [s0.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                const proposalId = await equGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await equGovernor.propose(targets, values, calldatas, description);
                await expect(efcGovernor.cancel(targets, values, calldatas, descriptionHash)).to.be.revertedWith(
                    "Governor: only proposer can cancel"
                );
                await equGovernor.cancel(targets, values, calldatas, descriptionHash);
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Canceled);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Canceled);
            });

            it("should return the right state if the efc governor proposal is canceled by the timelock", async () => {
                let {s0, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s0.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);
                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);
                const id = await timelockController.hashOperationBatch(
                    targets,
                    values,
                    calldatas,
                    ethers.utils.formatBytes32String(""),
                    descriptionHash
                );
                await timelockController.grantRole(timelockController.CANCELLER_ROLE(), s0.address);
                await timelockController.cancel(id);
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Canceled);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
            });

            it("should return the right state if the equ governor proposal is canncelled by the timelock", async () => {
                let {s0, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s0.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                await equGovernor.propose(targets, values, calldatas, description);
                const proposalId = await equGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await equGovernor.castVote(proposalId, VoteType.For);
                await efcGovernor.castVote(proposalId, VoteType.For);
                await mine(await equGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);
                const id = await timelockController.hashOperationBatch(
                    targets,
                    values,
                    calldatas,
                    ethers.utils.formatBytes32String(""),
                    descriptionHash
                );
                await timelockController.grantRole(timelockController.CANCELLER_ROLE(), s0.address);
                await timelockController.cancel(id);
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Canceled);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
            });

            it("should return the right state if the proposal is defeated", async () => {
                let {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s1.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.Against);
                await equGovernor.castVote(proposalId, VoteType.Against);
                await mine(await efcGovernor.votingPeriod());
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Defeated);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Defeated);
            });

            it("should return the right state if the equ proposal is defeated", async () => {
                let {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s1.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.Against);
                await mine(await efcGovernor.votingPeriod());
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Defeated);
            });

            it("should return the right state if the efc proposal is defeated", async () => {
                let {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s1.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await equGovernor.castVote(proposalId, VoteType.For);
                await efcGovernor.castVote(proposalId, VoteType.Against);
                await mine(await efcGovernor.votingPeriod());
                await expect(await efcGovernor.state(proposalId)).to.equal(ProposalState.Defeated);
                await expect(await equGovernor.state(proposalId)).to.equal(ProposalState.Succeeded);
            });
        });

        describe("proposals", () => {
            it("should not find proposal in equ governor if routine proposal is proposed", async () => {
                const {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s1.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await efcGovernor.routinePropose(targets, values, calldatas, description);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.Against);
                await expect(equGovernor.castVote(proposalId, VoteType.Against)).to.revertedWith(
                    "Governor: unknown proposal id"
                );
            });

            it("should revert with the right error if the proposal is not successful", async () => {
                const {s1, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [s1.address];
                const values = [0n];
                const calldatas = ["0x"];
                const description = "";
                const descriptionHash = ethers.utils.id(description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await efcGovernor.propose(targets, values, calldatas, description);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.Against);
                await equGovernor.castVote(proposalId, VoteType.Against);
                await expect(
                    efcGovernor.queue(targets, values, calldatas, descriptionHash)
                ).to.be.revertedWithCustomError(efcGovernor, "EQUProposalNotSucceeded");
            });

            it("setVotingDelay", async () => {
                const {timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [efcGovernor.address, equGovernor.address];
                const values = [0n, 0n];
                const calldatas = [
                    efcGovernor.interface.encodeFunctionData("setVotingDelay", [100]),
                    equGovernor.interface.encodeFunctionData("setVotingDelay", [100]),
                ];
                const description = "set voting delay to 100";
                const descriptionHash = ethers.utils.id(description);
                await equGovernor.propose(targets, values, calldatas, description);
                const proposalId = await equGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await equGovernor.castVote(proposalId, VoteType.For);
                await efcGovernor.castVote(proposalId, VoteType.For);

                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);

                await time.increase(await timelockController.getMinDelay());
                await expect(efcGovernor.execute(targets, values, calldatas, descriptionHash))
                    .to.emit(efcGovernor, "VotingDelaySet")
                    .withArgs(1, 100)
                    .emit(equGovernor, "VotingDelaySet")
                    .withArgs(1, 100);
                await expect(await efcGovernor.votingDelay()).to.equal(100);
                await expect(await equGovernor.votingDelay()).to.equal(100);
            });

            it("setVotingPeriod", async () => {
                const {timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [efcGovernor.address, equGovernor.address];
                const values = [0n, 0n];
                const calldatas = [
                    efcGovernor.interface.encodeFunctionData("setVotingPeriod", [100800]),
                    equGovernor.interface.encodeFunctionData("setVotingPeriod", [100800]),
                ];
                const description = "set voting period to 100800";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);

                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);

                await time.increase(await timelockController.getMinDelay());
                await expect(efcGovernor.execute(targets, values, calldatas, descriptionHash))
                    .to.emit(efcGovernor, "VotingPeriodSet")
                    .withArgs(50400, 100800)
                    .emit(equGovernor, "VotingPeriodSet")
                    .withArgs(50400, 100800);
                await expect(await efcGovernor.votingPeriod()).to.equal(100800);
                await expect(await equGovernor.votingPeriod()).to.equal(100800);
            });

            it("setProposalThreshold", async () => {
                const {timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [efcGovernor.address, equGovernor.address];
                const values = [0n, 0n];
                const calldatas = [
                    efcGovernor.interface.encodeFunctionData("setProposalThreshold", [1000n * 10n ** 18n]),
                    equGovernor.interface.encodeFunctionData("setProposalThreshold", [1000n * 10n ** 18n]),
                ];
                const description = "set proposal threshold to 1000 veToken";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);
                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);
                await time.increase(await timelockController.getMinDelay());
                await expect(efcGovernor.execute(targets, values, calldatas, descriptionHash))
                    .to.emit(efcGovernor, "ProposalThresholdSet")
                    .withArgs(10_000n * 10n ** 18n, 1000n * 10n ** 18n)
                    .emit(equGovernor, "ProposalThresholdSet")
                    .withArgs(10_000n * 10n ** 18n, 1000n * 10n ** 18n);
                await expect(await efcGovernor.proposalThreshold()).to.equal(1000n * 10n ** 18n);
                await expect(await equGovernor.proposalThreshold()).to.equal(1000n * 10n ** 18n);
            });

            it("updateTimelock", async () => {
                const {s0, s1, s2, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const newTimelockController = await ethers.deployContract("TimelockController", [
                    time.duration.days(1),
                    [efcGovernor.address],
                    [s1.address],
                    s0.address,
                ]);
                const proposerRole = await newTimelockController.PROPOSER_ROLE();
                await expect(await newTimelockController.hasRole(proposerRole, efcGovernor.address)).to.be.true;
                const executorRole = await newTimelockController.EXECUTOR_ROLE();
                await expect(await newTimelockController.hasRole(executorRole, s1.address)).to.be.true;
                await expect(await newTimelockController.hasRole(executorRole, s2.address)).to.be.false;

                const targets = [efcGovernor.address];
                const values = [0n];
                const calldatas = [
                    efcGovernor.interface.encodeFunctionData("updateTimelock", [newTimelockController.address]),
                ];
                const description = "update timelock controller";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);

                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);

                await time.increase(await timelockController.getMinDelay());
                await expect(efcGovernor.execute(targets, values, calldatas, descriptionHash))
                    .to.emit(efcGovernor, "TimelockChange")
                    .withArgs(timelockController.address, newTimelockController.address);
                await expect(await efcGovernor.timelock()).to.equal(newTimelockController.address);
            });

            it("updateDelay", async () => {
                const {timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [timelockController.address];
                const values = [0n];
                const calldatas = [
                    timelockController.interface.encodeFunctionData("updateDelay", [time.duration.days(1)]),
                ];
                const description = "update delay to 1 day";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);

                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);

                await time.increase(await timelockController.getMinDelay());
                await efcGovernor.execute(targets, values, calldatas, descriptionHash);
                await expect(await timelockController.getMinDelay()).to.equal(time.duration.days(1));
            });

            it("updateQuorumNumerator", async () => {
                const {timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const targets = [efcGovernor.address, equGovernor.address];
                const values = [0n, 0n];
                const calldatas = [
                    efcGovernor.interface.encodeFunctionData("updateQuorumNumerator", [8]),
                    equGovernor.interface.encodeFunctionData("updateQuorumNumerator", [8]),
                ];
                const description = "update quorum numerator to 8";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);

                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);

                await time.increase(await timelockController.getMinDelay());
                await expect(efcGovernor.execute(targets, values, calldatas, descriptionHash))
                    .to.emit(efcGovernor, "QuorumNumeratorUpdated")
                    .withArgs(5, 8)
                    .emit(equGovernor, "QuorumNumeratorUpdated")
                    .withArgs(5, 8);
                await expect(await efcGovernor["quorumNumerator()"]()).to.equal(8);
                await expect(await equGovernor["quorumNumerator()"]()).to.equal(8);
            });

            it("transfer", async () => {
                const {s0, s1, s2, timelockController, efcGovernor, equGovernor} = await loadFixture(deployFixture);
                const token = (await ethers.deployContract("ERC20Test", [
                    "TOKEN",
                    "TOKEN",
                    18,
                    100n * 10n ** 18n,
                ])) as ERC20Test;
                await token.approve(timelockController.address, 100n * 10n ** 18n);
                const targets = [token.address, token.address];
                const values = [0n, 0n];
                const calldatas = [
                    token.interface.encodeFunctionData("transferFrom", [s0.address, s1.address, 100n * 10n ** 18n]),
                    token.interface.encodeFunctionData("mint", [s2.address, 200n * 10n ** 18n]),
                ];
                const description = "transfer 100 TOKEN from s0 to s1 and mint 200 TOKEN to s2";
                const descriptionHash = ethers.utils.id(description);
                await efcGovernor.propose(targets, values, calldatas, description);
                const proposalId = await efcGovernor.hashProposal(targets, values, calldatas, descriptionHash);
                await mine();
                await efcGovernor.castVote(proposalId, VoteType.For);
                await equGovernor.castVote(proposalId, VoteType.For);

                await mine(await efcGovernor.votingPeriod());
                await efcGovernor.queue(targets, values, calldatas, descriptionHash);

                await time.increase(await timelockController.getMinDelay());
                await expect(efcGovernor.execute(targets, values, calldatas, descriptionHash)).changeTokenBalances(
                    token,
                    [s0, s1, s2],
                    [-100n * 10n ** 18n, 100n * 10n ** 18n, 200n * 10n ** 18n]
                );
            });
        });
    });
});
