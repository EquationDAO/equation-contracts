// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../governance/Governable.sol";
import "./interfaces/IPluginManager.sol";

abstract contract PluginManager is IPluginManager, Governable {
    /// @inheritdoc IPluginManager
    mapping(address => bool) public override registeredPlugins;
    mapping(address => bool) private registeredLiquidators;
    mapping(address => mapping(address => bool)) private pluginApprovals;

    /// @inheritdoc IPluginManager
    function registerPlugin(address _plugin) external override onlyGov {
        if (registeredPlugins[_plugin]) revert PluginAlreadyRegistered(_plugin);

        registeredPlugins[_plugin] = true;

        emit PluginRegistered(_plugin);
    }

    /// @inheritdoc IPluginManager
    function approvePlugin(address _plugin) external override {
        if (pluginApprovals[msg.sender][_plugin]) revert PluginAlreadyApproved(msg.sender, _plugin);

        if (!registeredPlugins[_plugin]) revert PluginNotRegistered(_plugin);

        pluginApprovals[msg.sender][_plugin] = true;
        emit PluginApproved(msg.sender, _plugin);
    }

    /// @inheritdoc IPluginManager
    function revokePlugin(address _plugin) external {
        if (!pluginApprovals[msg.sender][_plugin]) revert PluginNotApproved(msg.sender, _plugin);

        delete pluginApprovals[msg.sender][_plugin];
        emit PluginRevoked(msg.sender, _plugin);
    }

    /// @inheritdoc IPluginManager
    function isPluginApproved(address _account, address _plugin) public view override returns (bool) {
        return pluginApprovals[_account][_plugin];
    }

    /// @inheritdoc IPluginManager
    function registerLiquidator(address _liquidator) external override onlyGov {
        if (registeredLiquidators[_liquidator]) revert LiquidatorAlreadyRegistered(_liquidator);

        registeredLiquidators[_liquidator] = true;

        emit LiquidatorRegistered(_liquidator);
    }

    /// @inheritdoc IPluginManager
    function isRegisteredLiquidator(address _liquidator) public view override returns (bool) {
        return registeredLiquidators[_liquidator];
    }
}
