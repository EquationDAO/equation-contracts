// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.21;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract EquationTimelockController is TimelockController {
    using Address for address;

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    function acceptGov(address target) public {
        target.functionCall(abi.encodeWithSignature("acceptGov()"));
    }
}
