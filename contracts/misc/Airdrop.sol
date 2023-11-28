// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../types/PackedValue.sol";
import "../governance/Governable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Airdrop
/// @dev This contract handles the distribution of tokens to multiple addresses in a single transaction
contract Airdrop is Governable {
    /// @notice The maximum batch size for the airdrop
    uint256 public maxBatchSize = 200;

    /// @notice Invalid token
    error InvalidToken();
    /// @notice Error thrown when a zero address is provided
    /// @param index The index of the zero address
    error ZeroAddress(uint256 index);
    /// @notice Error thrown when the length exceeds the maximum batch size
    /// @param length The length of the batch
    /// @param maxBatchSize The maximum allowed batch size
    error InvalidBatchSize(uint256 length, uint256 maxBatchSize);
    ///@notice Error thrown when the amount is zero
    /// @param index The index of the zero amount
    error ZeroAmount(uint256 index);
    /// @notice Error thrown when the sender has insufficient balance
    /// @param total The total amount required
    error InsufficientBalance(uint256 total);

    /// @notice Sets the maximum batch size for the airdrop
    /// @param _maxBatchSize The maximum batch size
    function setMaxBatchSize(uint256 _maxBatchSize) external onlyGov {
        maxBatchSize = _maxBatchSize;
    }

    /// @notice Transfers tokens to multiple accounts with corresponding amounts
    /// @param _token The ERC20 token contract
    /// @param _packedAccountAmounts An array of packed values representing the accounts and corresponding amounts to transfer
    function multiTransfer(IERC20 _token, PackedValue[] memory _packedAccountAmounts) external {
        if (address(_token) == address(0)) revert InvalidToken();
        uint256 len = _packedAccountAmounts.length;
        if (len > maxBatchSize) revert InvalidBatchSize(len, maxBatchSize);
        uint256 total = 0;
        address[] memory accounts = new address[](len);
        uint96[] memory amounts = new uint96[](len);
        PackedValue packedAccountValue;
        for (uint256 i = 0; i < len; ) {
            packedAccountValue = _packedAccountAmounts[i];
            uint96 amount = packedAccountValue.unpackUint96(0);
            if (amount == 0) revert ZeroAmount(i);
            address account = packedAccountValue.unpackAddress(96);
            if (account == address(0)) revert ZeroAddress(i);
            accounts[i] = account;
            amounts[i] = amount;
            total += amount;
            unchecked {
                ++i;
            }
        }
        if (_token.balanceOf(msg.sender) < total) revert InsufficientBalance(total);
        for (uint256 i = 0; i < len; ) {
            _token.transferFrom(msg.sender, accounts[i], amounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}
