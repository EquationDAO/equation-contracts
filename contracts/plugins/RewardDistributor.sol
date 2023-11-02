// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title RewardDistributor
/// @dev The contract allows users to claim rewards from the distributor
contract RewardDistributor is Ownable2Step {
    using ECDSA for bytes32;

    /// @notice The address of the signer
    address public immutable signer;
    /// @notice The address of the token
    IERC20 public immutable token;
    /// @notice The collectors
    mapping(address => bool) public collectors;
    /// @notice Nonces for each account
    mapping(address => uint16) public nonces;
    /// @notice The claimed amount for each account
    mapping(address => uint256) public claimedRewards;

    /// @dev Event emitted when a claim is made
    /// @param receiver The address that received the reward
    /// @param account The account that claimed the reward for
    /// @param nonce The nonce of the claim
    /// @param amount The amount of the reward claimed
    event Claimed(address indexed receiver, address indexed account, uint16 indexed nonce, uint256 amount);

    /// @notice Error thrown when the caller is not authorized
    /// @param caller The caller address
    error CallerUnauthorized(address caller);
    /// @notice Error thrown when a zero address is provided
    error ZeroAddress();
    /// @notice Error thrown when the nonce is invalid
    /// @param nonce The invalid nonce
    error InvalidNonce(uint16 nonce);
    /// @notice Error thrown when the signature is invalid
    error InvalidSignature();

    /// @dev Modifier to restrict access to only the collector address.
    modifier onlyCollector() {
        if (!collectors[msg.sender]) revert CallerUnauthorized(msg.sender);
        _;
    }

    /// @notice Constructs a new RewardDistributor contract
    /// @param _signer The address of the signer
    /// @param _token The address of the token
    constructor(address _signer, IERC20 _token) {
        if (_signer == address(0) || address(_token) == address(0)) revert ZeroAddress();
        signer = _signer;
        token = _token;
    }

    /// @notice Sets the address of the reward collector and enables or disables it
    /// @param _collector The address of the reward collector
    /// @param _enabled A boolean indicating whether the reward collector is enabled or disabled
    function setCollector(address _collector, bool _enabled) external onlyOwner {
        collectors[_collector] = _enabled;
    }

    /// @notice Allows a user to claim their reward by providing a valid signature
    /// @dev The account and the receiver are the sender
    /// @param _nonce The nonce for the claim
    /// @param _totalReward The total reward amount of the sender
    /// @param _signature The signature of the signer to verify
    /// @param _receiver The receiver of the claim
    function claim(uint16 _nonce, uint256 _totalReward, bytes memory _signature, address _receiver) external {
        if (_receiver == address(0)) _receiver = msg.sender;
        _claim(msg.sender, _nonce, _totalReward, _signature, _receiver);
    }

    /// @notice Claims a reward for a specific account
    /// @param _account The account to claim for
    /// @param _nonce The nonce for the claim
    /// @param _totalReward The total reward amount of the account
    /// @param _signature The signature for the claim
    /// @param _receiver The receiver of the claim
    function claim(
        address _account,
        uint16 _nonce,
        uint256 _totalReward,
        bytes memory _signature,
        address _receiver
    ) external onlyCollector {
        if (_receiver == address(0)) _receiver = msg.sender;
        _claim(_account, _nonce, _totalReward, _signature, _receiver);
    }

    function _claim(
        address _account,
        uint16 _nonce,
        uint256 _totalReward,
        bytes memory _signature,
        address _receiver
    ) private {
        if (_nonce != nonces[_account] + 1) revert InvalidNonce(_nonce);
        address _signer = keccak256(abi.encode(_account, _nonce, _totalReward)).toEthSignedMessageHash().recover(
            _signature
        );
        if (_signer != signer) revert InvalidSignature();
        uint256 claimableReward = _totalReward - claimedRewards[_account];
        emit Claimed(_receiver, _account, _nonce, claimableReward);
        nonces[_account] = _nonce;
        claimedRewards[_account] += claimableReward;
        Address.functionCall(
            address(token),
            abi.encodeWithSignature("mint(address,uint256)", _receiver, claimableReward)
        );
    }
}
