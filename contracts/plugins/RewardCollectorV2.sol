// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./RewardCollector.sol";
import "../farming/PositionFarmRewardDistributor.sol";

/// @title RewardCollectorV2
/// @notice The contract extends the RewardCollector contract and implements additional functionality
/// It allows users to collect position farm rewards from the distributor
contract RewardCollectorV2 is RewardCollector {
    PositionFarmRewardDistributor public immutable distributor;

    /// @notice Constructs a new RewardCollectorV2 contract
    /// @param _router The address of the router
    /// @param _EQU The address of the EQU token
    /// @param _EFC The address of the EFC token
    /// @param _distributor The address of the position farm reward distributor
    constructor(
        Router _router,
        IERC20 _EQU,
        IEFC _EFC,
        PositionFarmRewardDistributor _distributor
    ) RewardCollector(_router, _EQU, _EFC) {
        distributor = _distributor;
    }

    /// @notice Allows a user to collect position farm rewards from the distributor
    /// @param _nonce The nonce of the sender
    /// @param _poolTotalRewards The pool total reward amount of the account
    /// @param _signature The signature to use for collecting the reward
    function collectPositionFarmRewardBatch(
        uint32 _nonce,
        PositionFarmRewardDistributor.PoolTotalReward[] calldata _poolTotalRewards,
        bytes memory _signature
    ) external {
        distributor.collectPositionFarmRewardBatchByCollector(
            msg.sender,
            _nonce,
            _poolTotalRewards,
            _signature,
            address(this)
        );
    }
}
