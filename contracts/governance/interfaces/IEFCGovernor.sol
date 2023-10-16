// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/IGovernor.sol";

abstract contract IEFCGovernor is IGovernor {
    /// @notice The return value of `hashProposal()` is not the same as value that `EQUGovernor.hashProposal()` return
    error HashProposalNotTheSame();

    /// @notice The state of EQU governor proposal is not `Succeeded`
    error EQUProposalNotSucceeded();

    /// @notice Address through which the governor executes action.
    /// @return The address of the executor
    function executor() public view virtual returns (address);
}
