// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../governance/Governable.sol";

contract GovernableTest is Governable {
    function onlyGovTest() external view onlyGov {
        // solhint-disable-next-line no-empty-blocks
    }
}
