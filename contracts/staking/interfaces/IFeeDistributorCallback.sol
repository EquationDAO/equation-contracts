// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IFeeDistributorCallback {
    /// @notice The callback function after the Architect-type NFT is mined.
    /// @param tokenID The ID of the Architect-type NFT
    function onMintArchitect(uint256 tokenID) external;
}
