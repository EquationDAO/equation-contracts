// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./interfaces/IEFCGovernor.sol";
import "./interfaces/IEQUGovernor.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

contract EFCGovernor is
    IEFCGovernor,
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    mapping(uint256 => bool) private isRoutineProposal;
    IEQUGovernor public immutable EQUGovernor;

    constructor(
        IVotes _token,
        IEQUGovernor _EQUGovernor,
        TimelockController _timelock
    )
        Governor("EFCGovernor")
        GovernorSettings(1 /* 1 block */, 50400 /* 1 week */, 10000e18) //TODO: to be updated
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(5) //TODO: to be updated
        GovernorTimelockControl(_timelock)
    {
        EQUGovernor = _EQUGovernor;
    }

    /// @notice Create a new proposal in the current contract. Simultaneously, a matching proposal will be created in
    /// the `EFCGovernor` contract.
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
        uint256 proposalId = super.propose(targets, values, calldatas, description);
        if (_msgSender() != address(EQUGovernor)) {
            uint256 EQUGovernorProposalId = EQUGovernor.propose(targets, values, calldatas, description);
            if (EQUGovernorProposalId != proposalId) revert HashProposalNotTheSame();
        }
        return proposalId;
    }

    /// @notice Create a new proposal in the current contract.
    /// @param targets An array of target addresses to which the proposal calls will be made.
    /// @param values An array of values to be sent in the proposal calls.
    /// @param calldatas An array of calldatas containing the encoded function calls and arguments for the
    /// proposal calls.
    /// @param description A string describing the purpose or details of the proposal.
    /// @return The ID of the newly created proposal.
    function routinePropose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        uint256 proposalId = super.propose(targets, values, calldatas, description);
        isRoutineProposal[proposalId] = true;
        return proposalId;
    }

    /// @notice Queue a proposal that has been approved by the governance participants.
    /// @param targets An array of target addresses of the proposal calls.
    /// @param values An array of values to be sent in the proposal calls.
    /// @param calldatas An array of calldatas containing the encoded function calls and arguments for the
    /// proposal calls.
    /// @param descriptionHash The hash of the description associated with the proposal (used for verification).
    /// @return The ID of the queued proposal.
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual override returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        if (!_isRoutineProposal(proposalId) && EQUGovernor.state(proposalId) != ProposalState.Succeeded) {
            revert EQUProposalNotSucceeded();
        }
        return super.queue(targets, values, calldatas, descriptionHash);
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
        uint256 proposalId = super.cancel(targets, values, calldatas, descriptionHash);
        if (!_isRoutineProposal(proposalId) && _msgSender() != address(EQUGovernor)) {
            uint256 EQUGovernorProposeId = EQUGovernor.cancel(targets, values, calldatas, descriptionHash);
            if (proposalId != EQUGovernorProposeId) revert HashProposalNotTheSame();
        }
        return proposalId;
    }

    /// @notice Get the number of votes required in order for a voter to become a proposer
    /// @return The number of votes required in order for a voter to become a proposer
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        if (_msgSender() == address(EQUGovernor)) {
            return 0;
        }
        return super.proposalThreshold();
    }

    /// @inheritdoc IEFCGovernor
    function executor() public view override returns (address) {
        return _executor();
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

    function state(
        uint256 proposalId
    ) public view override(Governor, IGovernor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(Governor, IERC165, GovernorTimelockControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        if (!_isRoutineProposal(proposalId) && EQUGovernor.state(proposalId) != ProposalState.Succeeded) {
            revert EQUProposalNotSucceeded();
        }
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Hook before execution is triggered.
     */
    function _beforeExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override {
        if (!_isRoutineProposal(proposalId)) {
            EQUGovernor.beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        }
        super._beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Hook after execution is triggered.
     */
    function _afterExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override {
        if (!_isRoutineProposal(proposalId)) {
            EQUGovernor.afterExecute(proposalId, targets, values, calldatas, descriptionHash);
        }
        super._afterExecute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function _isRoutineProposal(uint256 _proposalId) internal view returns (bool) {
        return isRoutineProposal[_proposalId];
    }

    function _isValidDescriptionForProposer(
        address proposer,
        string memory description
    ) internal view virtual override returns (bool) {
        if (_msgSender() == address(EQUGovernor)) {
            return true;
        }
        return super._isValidDescriptionForProposer(proposer, description);
    }
}
