// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./interfaces/IEFCGovernor.sol";
import "./interfaces/IEQUGovernor.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

contract EQUGovernor is
    IEQUGovernor,
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    IEFCGovernor public immutable EFCGovernor;

    constructor(
        IVotes _token,
        IEFCGovernor _EFCGovernor
    )
        Governor("EQUGovernor")
        GovernorSettings(1 /* 1 block */, 50400 /* 1 week */, 10000e18) //TODO: to be updated
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(5) //TODO: to be updated
    {
        EFCGovernor = _EFCGovernor;
    }

    /// @notice Create a new proposal in the current contract. Simultaneously, a matching proposal will be created
    /// in the `EFCGovernor` contract.
    /// @param targets An array of target addresses to which the proposal calls will be made.
    /// @param values An array of values to be sent in the proposal calls.
    /// @param calldatas An array of calldatas containing the encoded function calls and arguments for the
    /// proposal calls.
    /// @param description A string describing the purpose or details of the proposal.
    /// @return The ID of the newly created proposal.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, IGovernor) returns (uint256) {
        uint256 proposeId = super.propose(targets, values, calldatas, description);
        if (_msgSender() == address(EFCGovernor)) {
            return proposeId;
        }
        uint256 EFCGovernorProposeId = EFCGovernor.propose(targets, values, calldatas, description);
        if (proposeId != EFCGovernorProposeId) revert HashProposalNotTheSame();
        return proposeId;
    }

    /// @notice Cancel a proposal that has not yet been started. Only the proposer can cancel a proposal.
    /// @param targets An array of target addresses of the proposal calls.
    /// @param values An array of values to be sent in the proposal calls.
    /// @param calldatas An array of calldatas containing the encoded function calls and arguments for the
    /// proposal calls.
    /// @param descriptionHash The hash of the description associated with the proposal (used for verification).
    /// @return The ID of the canceled proposal.
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override(Governor, IGovernor) returns (uint256) {
        uint256 proposeId = super.cancel(targets, values, calldatas, descriptionHash);
        if (_msgSender() != address(EFCGovernor)) {
            uint256 EFCGovernorProposeId = EFCGovernor.cancel(targets, values, calldatas, descriptionHash);
            if (proposeId != EFCGovernorProposeId) revert HashProposalNotTheSame();
        }
        return proposeId;
    }

    /// @notice Get the number of votes required in order for a voter to become a proposer
    /// @return The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public view virtual override(Governor, GovernorSettings) returns (uint256) {
        if (_msgSender() == address(EFCGovernor)) {
            return 0;
        }
        return super.proposalThreshold();
    }

    /// @notice Execute a proposal that has been approved. This function will make the specified calls to the
    /// target addresses.
    /// @param targets An array of target addresses of the proposal calls.
    /// @param values An array of values to be sent in the proposal calls.
    /// @param calldatas An array of calldatas containing the encoded function calls and arguments for the
    /// proposal calls.
    /// @param descriptionHash The hash of the description associated with the proposal (used for verification).
    /// @return The ID of the executed proposal.
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override(Governor, IGovernor) returns (uint256) {
        return EFCGovernor.execute{value: msg.value}(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc IEQUGovernor
    function beforeExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override {
        if (_msgSender() != address(EFCGovernor)) revert CallerIsNotEFCGovernor();
        super._beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc IEQUGovernor
    function afterExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override {
        if (_msgSender() != address(EFCGovernor)) revert CallerIsNotEFCGovernor();
        super._afterExecute(proposalId, targets, values, calldatas, descriptionHash);
        emit ProposalExecuted(proposalId);
    }

    // The following functions are overrides required by Solidity.
    function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(
        uint256 blockNumber
    ) public view override(IGovernor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId) public view virtual override(Governor, IGovernor) returns (ProposalState) {
        return super.state(proposalId);
    }

    function _isValidDescriptionForProposer(
        address proposer,
        string memory description
    ) internal view virtual override returns (bool) {
        if (_msgSender() == address(EFCGovernor)) {
            return true;
        }
        return super._isValidDescriptionForProposer(proposer, description);
    }

    function _executor() internal view override returns (address) {
        return EFCGovernor.executor();
    }
}
