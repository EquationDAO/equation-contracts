// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../core/PoolIndexer.sol";
import "../core/interfaces/IPool.sol";
import "../governance/Governable.sol";
import "../types/PackedValue.sol";
import "../libraries/SafeCast.sol";
import "./PositionFarmRewardDistributor.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract FarmRewardDistributorV2 is Governable {
    using SafeCast for *;
    using ECDSA for bytes32;

    uint16 public constant REWARD_TYPE_POSITION = 1;
    uint16 public constant REWARD_TYPE_LIQUIDITY = 2;
    uint16 public constant REWARD_TYPE_RISK_BUFFER_FUND = 3;

    /// @notice The address of the signer
    address public immutable signer;
    /// @notice The address of the token to be distributed
    IERC20 public immutable token;
    /// @notice The address of the distributor v1
    PositionFarmRewardDistributor public immutable distributorV1;
    PoolIndexer public immutable poolIndexer;

    /// @notice The collectors
    mapping(address => bool) public collectors;

    /// @notice The nonces for each account
    mapping(address => uint32) public nonces;
    /// @notice Mapping of reward types to their description.
    /// e.g. 1 => "Position", 2 => "Liquidity", 3 => "RiskBufferFund"
    mapping(uint16 => string) public rewardTypesDescriptions;
    /// @notice Mapping of accounts to their collected rewards for corresponding pools and reward types
    mapping(address => mapping(IPool => mapping(uint16 => uint216))) public collectedRewards;

    /// @notice Event emitted when the reward type description is set
    event RewardTypeDescriptionSet(uint16 indexed rewardType, string description);
    /// @notice Event emitted when the collector is enabled or disabled
    /// @param collector The address of the collector
    /// @param enabled Whether the collector is enabled or disabled
    event CollectorUpdated(address indexed collector, bool enabled);
    /// @notice Event emitted when the reward is collected
    /// @param pool The pool from which to collect the reward
    /// @param account The account that collect the reward for
    /// @param rewardType The reward type
    /// @param nonce The nonce of the account
    /// @param receiver The address that received the reward
    /// @param amount The amount of the reward collected
    event RewardCollected(
        IPool indexed pool,
        address indexed account,
        uint16 indexed rewardType,
        uint32 nonce,
        address receiver,
        uint216 amount
    );

    /// @notice Error thrown when the reward type is invalid
    error InvalidRewardType(uint16 rewardType);

    modifier onlyCollector() {
        if (!collectors[msg.sender]) revert Forbidden();
        _;
    }

    constructor(address _signer, PositionFarmRewardDistributor _distributorV1, PoolIndexer _poolIndexer) {
        signer = _signer;
        distributorV1 = _distributorV1;
        token = _distributorV1.token();
        poolIndexer = _poolIndexer;

        _setRewardType(REWARD_TYPE_POSITION, "Position");
        _setRewardType(REWARD_TYPE_LIQUIDITY, "Liquidity");
        _setRewardType(REWARD_TYPE_RISK_BUFFER_FUND, "RiskBufferFund");
    }

    /// @notice Set whether the address of the reward collector is enabled or disabled
    /// @param _collector Address to set
    /// @param _enabled Whether the address is enabled or disabled
    function setCollector(address _collector, bool _enabled) external onlyGov {
        collectors[_collector] = _enabled;
        emit CollectorUpdated(_collector, _enabled);
    }

    /// @notice Set the reward type description
    /// @param _rewardType The reward type to set
    /// @param _description The description to set
    function setRewardType(uint16 _rewardType, string calldata _description) external onlyGov {
        _setRewardType(_rewardType, _description);
    }

    /// @notice Collect the farm reward by the collector
    /// @param _account The account that collect the reward for
    /// @param _nonce The nonce of the account
    /// @param _packedValues The packed values of the pool index, reward type, and amount: bit 0-23 represent
    /// the pool index, bit 24-39 represent the reward type, and bit 40-255 represent the amount
    /// @param _signature The signature of the parameters to verify
    /// @param _receiver The address that received the reward
    function collectBatch(
        address _account,
        uint32 _nonce,
        PackedValue[] calldata _packedValues,
        bytes calldata _signature,
        address _receiver
    ) external onlyCollector {
        if (_receiver == address(0)) _receiver = msg.sender;

        if (_nonce != _nonceFor(_account) + 1) revert PositionFarmRewardDistributor.InvalidNonce(_nonce);

        address _signer = keccak256(abi.encode(_account, _nonce, _packedValues)).toEthSignedMessageHash().recover(
            _signature
        );
        if (_signer != signer) revert PositionFarmRewardDistributor.InvalidSignature();

        uint256 totalCollectableReward;
        IPool pool;
        PackedValue packedValue;
        uint256 len = _packedValues.length;
        for (uint256 i; i < len; ) {
            packedValue = _packedValues[i];
            pool = poolIndexer.indexPools(packedValue.unpackUint24(0));
            if (address(pool) == address(0)) revert PoolIndexer.InvalidPool(pool);

            uint16 rewardType = packedValue.unpackUint16(24);
            if (bytes(rewardTypesDescriptions[rewardType]).length == 0) revert InvalidRewardType(rewardType);

            uint216 amount = packedValue.unpackUint216(40);
            uint216 collectableReward = amount - _collectedRewardFor(_account, pool, rewardType);
            emit RewardCollected(pool, _account, rewardType, _nonce, _receiver, collectableReward);

            collectedRewards[_account][pool][rewardType] = amount;
            totalCollectableReward += collectableReward;

            // prettier-ignore
            unchecked { ++i; }
        }

        nonces[_account] = _nonce;
        Address.functionCall(
            address(token),
            abi.encodeWithSignature("mint(address,uint256)", address(this), totalCollectableReward)
        );

        // TODO: burn the token after the reward is distributed
    }

    function _nonceFor(address _account) internal view returns (uint32 nonce) {
        nonce = nonces[_account];
        if (nonce == 0) nonce = distributorV1.nonces(_account);
    }

    function _collectedRewardFor(
        address _account,
        IPool _pool,
        uint16 _rewardType
    ) internal view returns (uint216 collectedReward) {
        collectedReward = collectedRewards[_account][_pool][_rewardType];
        if (collectedReward == 0 && _rewardType == REWARD_TYPE_POSITION)
            collectedReward = distributorV1.collectedRewards(address(_pool), _account).toUint216();
    }

    function _setRewardType(uint16 _rewardType, string memory _description) internal virtual {
        require(bytes(_description).length <= 32);

        rewardTypesDescriptions[_rewardType] = _description;
        emit RewardTypeDescriptionSet(_rewardType, _description);
    }
}
