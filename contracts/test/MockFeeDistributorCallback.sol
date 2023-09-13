// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../staking/interfaces/IFeeDistributorCallback.sol";

contract MockFeeDistributorCallback is IFeeDistributorCallback {
    uint256 public tokenID;

    function onMintArchitect(uint256 _tokenID) external override {
        tokenID = _tokenID;
    }
}
