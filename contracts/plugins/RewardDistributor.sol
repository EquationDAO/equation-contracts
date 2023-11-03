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

    /// @notice Struct to store the pool total reward for an account
    struct PoolTotalReward {
        /// @notice The address of the pool
        address pool;
        /// @notice The total reward amount of the account in the pool
        uint256 totalReward;
    }

    /// @notice The address of the signer
    address public immutable signer;
    /// @notice The address of the token
    IERC20 public immutable token;
    /// @notice The collectors
    mapping(address => bool) public collectors;
    /// @notice The nonces for each account
    mapping(address => uint32) public nonces;
    /// @notice Mapping of pool accounts to their claimed rewards
    /// pool => account => claimedReward
    mapping(address => mapping(address => uint256)) public claimedRewards;

    /// @dev Event emitted when a claim is made
    /// @param pool The pool from which to claim the reward
    /// @param account The account that claimed the reward for
    /// @param nonce The nonce of the sender for the claim
    /// @param receiver The address that received the reward
    /// @param amount The amount of the reward claimed
    event Claimed(
        address indexed pool,
        address indexed account,
        uint32 indexed nonce,
        address receiver,
        uint256 amount
    );

    /// @notice Error thrown when the caller is not authorized
    /// @param caller The caller address
    error CallerUnauthorized(address caller);
    /// @notice Error thrown when a zero address is provided
    error ZeroAddress();
    /// @notice Error thrown when the nonce is invalid
    /// @param nonce The invalid nonce
    error InvalidNonce(uint32 nonce);
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
    /// @param _nonce The nonce of the sender for the claim
    /// @param _poolTotalRewards The pool total reward amount of the account
    /// @param _signature The signature of the signer to verify
    /// @param _receiver The receiver of the claim
    function claim(
        uint32 _nonce,
        PoolTotalReward[] calldata _poolTotalRewards,
        bytes memory _signature,
        address _receiver
    ) external {
        if (_receiver == address(0)) _receiver = msg.sender;
        _claim(msg.sender, _nonce, _poolTotalRewards, _signature, _receiver);
    }

    /// @notice Claims a reward for a specific account
    /// @param _account The account to claim for
    /// @param _nonce The nonce of the sender for the claim
    /// @param _poolTotalRewards The pool total reward amount of the account
    /// @param _signature The signature for the claim
    /// @param _receiver The receiver of the claim
    function claimByCollector(
        address _account,
        uint32 _nonce,
        PoolTotalReward[] calldata _poolTotalRewards,
        bytes memory _signature,
        address _receiver
    ) external onlyCollector {
        if (_receiver == address(0)) _receiver = msg.sender;
        _claim(_account, _nonce, _poolTotalRewards, _signature, _receiver);
    }

    function _claim(
        address _account,
        uint32 _nonce,
        PoolTotalReward[] calldata _poolTotalRewards,
        bytes memory _signature,
        address _receiver
    ) private {
        if (_nonce != nonces[_account] + 1) revert InvalidNonce(_nonce);
        address _signer = keccak256(abi.encode(_account, _nonce, _poolTotalRewards)).toEthSignedMessageHash().recover(
            _signature
        );
        if (_signer != signer) revert InvalidSignature();

        uint256 amount = 0;
        for (uint i = 0; i < _poolTotalRewards.length; i++) {
            (address pool, uint256 totalReward) = (_poolTotalRewards[i].pool, _poolTotalRewards[i].totalReward);
            uint256 claimableReward = totalReward - claimedRewards[pool][_account];
            emit Claimed(pool, _account, _nonce, _receiver, claimableReward);
            claimedRewards[pool][_account] += claimableReward;
            amount += claimableReward;
        }
        nonces[_account] = _nonce;
        Address.functionCall(address(token), abi.encodeWithSignature("mint(address,uint256)", _receiver, amount));
    }
}
