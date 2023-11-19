// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./interfaces/IPoolFactory.sol";

/// @notice The contract is used for assigning pool and token indexes.
/// Using an index instead of an address can effectively reduce the gas cost of the transaction.
/// @custom:since v0.0.3
contract PoolIndexer {
    IPoolFactory public immutable poolFactory;

    uint24 public poolIndex;
    /// @notice Mapping of pools to their indexes
    mapping(IPool => uint24) public poolIndexes;
    /// @notice Mapping of indexes to their pools
    mapping(uint24 => IPool) public indexPools;

    /// @notice Emitted when a index is assigned to a pool and token
    /// @param pool The address of the pool
    /// @param token The ERC20 token used in the pool
    /// @param index The index assigned to the pool and token
    event PoolIndexAssigned(IPool indexed pool, IERC20 indexed token, uint24 indexed index);

    /// @notice Error thrown when the pool index is already assigned
    error PoolIndexAlreadyAssigned(IPool pool);
    /// @notice Error thrown when the pool is invalid
    error InvalidPool(IPool pool);

    constructor(IPoolFactory _poolFactory) {
        poolFactory = _poolFactory;
    }

    /// @notice Assign a pool index to a pool
    function assignPoolIndex(IPool _pool) external returns (uint24 index) {
        if (poolIndexes[_pool] != 0) revert PoolIndexAlreadyAssigned(_pool);

        if (!poolFactory.isPool(address(_pool))) revert InvalidPool(_pool);

        index = ++poolIndex;
        poolIndexes[_pool] = index;
        indexPools[index] = _pool;

        emit PoolIndexAssigned(_pool, _pool.token(), index);
    }

    /// @notice Get the index of a token
    /// @param _token The ERC20 token used in the pool
    /// @return index The index assigned to the token, 0 if not exists
    function tokenIndexes(IERC20 _token) external view returns (uint24 index) {
        index = poolIndexes[poolFactory.pools(_token)];
    }

    /// @notice Get the token of an index
    /// @param _index The index assigned to the token
    /// @return token The ERC20 token used in the pool, address(0) if not exists
    function indexToken(uint24 _index) external view returns (IERC20 token) {
        IPool pool = indexPools[_index];
        token = address(pool) == address(0) ? IERC20(address(0)) : pool.token();
    }
}
