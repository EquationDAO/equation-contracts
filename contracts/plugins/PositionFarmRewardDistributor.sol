// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../governance/Governable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title PositionFarmRewardDistributor
/// @dev The contract allows users to collect position farm rewards
contract PositionFarmRewardDistributor is Governable {
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
    /// @notice Mapping of pool accounts to their collected rewards
    /// pool => account => collectedReward
    mapping(address => mapping(address => uint256)) public collectedRewards;

    /// @dev Event emitted when the position farm reward is collected
    /// @param pool The pool from which to collect the reward
    /// @param account The account that collect the reward for
    /// @param nonce The nonce of the sender
    /// @param receiver The address that received the reward
    /// @param amount The amount of the reward collected
    event PositionFarmRewardCollected(
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

    /// @notice Constructs a new PositionFarmRewardDistributor contract
    /// @param _signer The address of the signer
    /// @param _token The address of the token
    constructor(address _signer, IERC20 _token) {
        if (_signer == address(0) || address(_token) == address(0)) revert ZeroAddress();
        signer = _signer;
        token = _token;
    }

    /// @notice Set whether the address of the reward collector is enabled or disabled
    /// @param _collector Address to set
    /// @param _enabled Whether the address is enabled or disabled
    function setCollector(address _collector, bool _enabled) external onlyGov {
        collectors[_collector] = _enabled;
    }

    /// @notice Collect position farm reward by the sender
    /// @param _nonce The nonce of the account
    /// @param _poolTotalRewards The pool total reward amount of the account
    /// @param _signature The signature of the signer to verify
    /// @param _receiver The address that received the reward
    function collectPositionFarmRewardBatch(
        uint32 _nonce,
        PoolTotalReward[] calldata _poolTotalRewards,
        bytes memory _signature,
        address _receiver
    ) external {
        if (_receiver == address(0)) _receiver = msg.sender;
        _collectPositionFarmRewardBatch(msg.sender, _nonce, _poolTotalRewards, _signature, _receiver);
    }

    /// @notice Collect position farm reward for a specific account by the collector
    /// @param _account The account to collect the reward for
    /// @param _nonce The nonce of the account
    /// @param _poolTotalRewards The pool total reward amount of the account
    /// @param _signature The signature of the signer to verify
    /// @param _receiver The address that received the reward
    function collectPositionFarmRewardBatchByCollector(
        address _account,
        uint32 _nonce,
        PoolTotalReward[] calldata _poolTotalRewards,
        bytes memory _signature,
        address _receiver
    ) external onlyCollector {
        if (_receiver == address(0)) _receiver = msg.sender;
        _collectPositionFarmRewardBatch(_account, _nonce, _poolTotalRewards, _signature, _receiver);
    }

    function _collectPositionFarmRewardBatch(
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
        uint256 len = _poolTotalRewards.length;
        for (uint256 i = 0; i < len; ) {
            (address pool, uint256 totalReward) = (_poolTotalRewards[i].pool, _poolTotalRewards[i].totalReward);
            uint256 collectableReward = totalReward - collectedRewards[pool][_account];
            emit PositionFarmRewardCollected(pool, _account, _nonce, _receiver, collectableReward);
            collectedRewards[pool][_account] = totalReward;
            amount += collectableReward;
            unchecked {
                ++i;
            }
        }
        nonces[_account] = _nonce;
        Address.functionCall(address(token), abi.encodeWithSignature("mint(address,uint256)", _receiver, amount));
    }
}
