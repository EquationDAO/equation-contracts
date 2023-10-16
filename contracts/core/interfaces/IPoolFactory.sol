// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IConfigurable.sol";
import "../../plugins/Router.sol";
import "../../oracle/interfaces/IPriceFeed.sol";
import "../../farming/interfaces/IRewardFarmCallback.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title Pool Factory Interface
/// @notice This interface defines the functions for creating pools
interface IPoolFactory is IConfigurable, IAccessControl {
    /// @notice Emitted when a new pool is created
    /// @param pool The address of the created pool
    /// @param token The ERC20 token used in the pool
    /// @param usd The ERC20 token representing the USD stablecoin used in the pool
    event PoolCreated(IPool indexed pool, IERC20 indexed token, IERC20 indexed usd);

    /// @notice Pool factory is not initialized
    error NotInitialized();

    /// @notice Pool already exists
    error PoolAlreadyExists(IPool pool);

    /// @notice Get the address of the governor
    /// @return The address of the governor
    function gov() external view returns (address);

    /// @notice Retrieve the price feed contract used for fetching token prices
    function priceFeed() external view returns (IPriceFeed);

    /// @notice Retrieve the deployment parameters for a pool
    /// @return token The ERC20 token used in the pool
    /// @return usd The ERC20 token representing the USD stablecoin used in the pool
    /// @return router The router contract used in the pool
    /// @return feeDistributor The fee distributor contract used for distributing fees
    /// @return EFC The EFC contract used for referral program
    /// @return callback The reward farm callback contract used for distributing rewards
    function deployParameters()
        external
        view
        returns (
            IERC20 token,
            IERC20 usd,
            Router router,
            IFeeDistributor feeDistributor,
            IEFC EFC,
            IRewardFarmCallback callback
        );

    /// @notice Get the pool associated with a token and USD stablecoin
    /// @param token The ERC20 token used in the pool
    /// @return pool The address of the created pool (address(0) if not exists)
    function pools(IERC20 token) external view returns (IPool pool);

    /// @notice Check if a pool exist
    /// @param pool The address of the pool
    /// @return True if the pool exist
    function isPool(address pool) external view returns (bool);

    /// @notice Create a new pool
    /// @dev The call will fail if any of the following conditions are not met:
    /// - The caller is the governor
    /// - The pool does not already exist
    /// - The token is enabled
    /// @param token The ERC20 token used in the pool
    /// @return pool The address of the created pool
    function createPool(IERC20 token) external returns (IPool pool);
}
