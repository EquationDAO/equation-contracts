// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../core/interfaces/IPool.sol";

contract MockPoolFactory {
    mapping(IPool => bool) private createdPools;

    function isPool(address _pool) external view returns (bool) {
        return createdPools[IPool(_pool)];
    }

    function createPool(address _account) external {
        createdPools[IPool(_account)] = true;
    }
}
