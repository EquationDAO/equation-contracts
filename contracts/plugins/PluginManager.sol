// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.21;

import "../governance/Governable.sol";
import "./interfaces/IPluginManager.sol";

abstract contract PluginManager is IPluginManager, Governable {
    mapping(address => bool) public override registeredPlugins;
    mapping(address => mapping(address => bool)) private pluginApprovals;

    function registerPlugin(address plugin) external override onlyGov {
        if (registeredPlugins[plugin]) revert PluginAlreadyRegistered();

        registeredPlugins[plugin] = true;
    }

    /// @inheritdoc IPluginManager
    function approvePlugin(address _plugin) external override {
        if (pluginApprovals[msg.sender][_plugin]) revert PluginAlreadyApproved();

        if (!registeredPlugins[_plugin]) revert PluginNotRegistered();

        pluginApprovals[msg.sender][_plugin] = true;
        emit PluginApproved(msg.sender, _plugin);
    }

    /// @inheritdoc IPluginManager
    function revokePlugin(address _plugin) external {
        if (!pluginApprovals[msg.sender][_plugin]) revert PluginNotApproved();

        delete pluginApprovals[msg.sender][_plugin];
        emit PluginRevoked(msg.sender, _plugin);
    }

    /// @inheritdoc IPluginManager
    function isPluginApproved(address _account, address _plugin) public view override returns (bool) {
        return pluginApprovals[_account][_plugin];
    }
}
