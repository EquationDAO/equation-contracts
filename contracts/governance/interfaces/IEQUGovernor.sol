// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/IGovernor.sol";

abstract contract IEQUGovernor is IGovernor {
    /// @notice The return value of `hashProposal()` is not the same as value that `EFCGovernor.hashProposal()` return
    error HashProposalNotTheSame();

    /// @notice The caller is not EFC Governor
    error CallerIsNotEFCGovernor();

    /// @notice Hook before execution is triggered. EFCGovernor is the only caller.
    function beforeExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual;

    /// @notice Hook after execution is triggered. EFCGovernor is the only caller.
    function afterExecute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public virtual;
}
