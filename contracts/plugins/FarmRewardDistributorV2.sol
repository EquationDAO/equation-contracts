// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../core/PoolIndexer.sol";
import "../core/interfaces/IPool.sol";
import "../governance/Governable.sol";
import "../types/PackedValue.sol";
import "../libraries/SafeCast.sol";
import "../libraries/Constants.sol";
import "./PositionFarmRewardDistributor.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract FarmRewardDistributorV2 is Governable {
    using SafeCast for *;
    using ECDSA for bytes32;

    struct LockupFreeRateParameter {
        /// @notice The lockup period
        uint16 period;
        /// @notice The lockup free rate, denominated in ten thousandths of a bip (i.e. 1e-8)
        uint32 lockupFreeRate;
    }

    uint16 public constant REWARD_TYPE_POSITION = 1;
    uint16 public constant REWARD_TYPE_LIQUIDITY = 2;
    uint16 public constant REWARD_TYPE_RISK_BUFFER_FUND = 3;

    /// @notice The address of the signer
    address public immutable signer;
    /// @notice The address of the token to be distributed
    IERC20 public immutable token;
    /// @notice The address of the distributor v1
    PositionFarmRewardDistributor public immutable distributorV1;
    /// @notice The address of the fee distributor
    IFeeDistributor public immutable feeDistributor;
    /// @notice The address of the pool indexer
    PoolIndexer public immutable poolIndexer;

    /// @notice The collectors
    mapping(address => bool) public collectors;

    /// @notice Mapping of reward types to their description.
    /// e.g. 1 => "Position", 2 => "Liquidity", 3 => "RiskBufferFund"
    mapping(uint16 => string) public rewardTypesDescriptions;
    /// @notice Mapping of lockup period to their lockup free rate
    mapping(uint16 => uint32) public lockupFreeRates;

    /// @notice The nonces for each account
    mapping(address => uint32) public nonces;
    /// @notice Mapping of accounts to their collected rewards for corresponding pools and reward types
    mapping(address => mapping(IPool => mapping(uint16 => uint216))) public collectedRewards;

    /// @notice Event emitted when the reward type description is set
    event RewardTypeDescriptionSet(uint16 indexed rewardType, string description);
    /// @notice Event emitted when the collector is enabled or disabled
    /// @param collector The address of the collector
    /// @param enabled Whether the collector is enabled or disabled
    event CollectorUpdated(address indexed collector, bool enabled);
    /// @notice Event emitted when the lockup free rate is set
    /// @param period The lockup period
    /// @param lockupFreeRate The lockup free rate, denominated in ten thousandths of a bip (i.e. 1e-8)
    event LockupFreeRateSet(uint16 indexed period, uint32 lockupFreeRate);
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
    /// @notice Error thrown when the lockup free rate is invalid
    error InvalidLockupFreeRate(uint32 lockupFreeRate);

    modifier onlyCollector() {
        if (!collectors[msg.sender]) revert Forbidden();
        _;
    }

    constructor(
        address _signer,
        PositionFarmRewardDistributor _distributorV1,
        IFeeDistributor _feeDistributor,
        PoolIndexer _poolIndexer
    ) {
        signer = _signer;
        distributorV1 = _distributorV1;
        token = _distributorV1.token();
        feeDistributor = _feeDistributor;
        poolIndexer = _poolIndexer;

        _setRewardType(REWARD_TYPE_POSITION, "Position");
        _setRewardType(REWARD_TYPE_LIQUIDITY, "Liquidity");
        _setRewardType(REWARD_TYPE_RISK_BUFFER_FUND, "RiskBufferFund");

        _setLockupFreeRate(LockupFreeRateParameter({period: 0, lockupFreeRate: 25_000_000})); // 25%
        _setLockupFreeRate(LockupFreeRateParameter({period: 30, lockupFreeRate: 50_000_000})); // 50%
        _setLockupFreeRate(LockupFreeRateParameter({period: 60, lockupFreeRate: 75_000_000})); // 75%
        _setLockupFreeRate(LockupFreeRateParameter({period: 90, lockupFreeRate: 100_000_000})); // 100%
    }

    /// @notice Set whether the address of the reward collector is enabled or disabled
    /// @param _collector Address to set
    /// @param _enabled Whether the address is enabled or disabled
    function setCollector(address _collector, bool _enabled) external virtual onlyGov {
        collectors[_collector] = _enabled;
        emit CollectorUpdated(_collector, _enabled);
    }

    /// @notice Set the reward type description
    /// @param _rewardType The reward type to set
    /// @param _description The description to set
    function setRewardType(uint16 _rewardType, string calldata _description) external virtual onlyGov {
        _setRewardType(_rewardType, _description);
    }

    /// @notice Set lockup free rates for multiple periods
    /// @param _parameters The parameters to set
    function setLockupFreeRates(LockupFreeRateParameter[] calldata _parameters) external virtual onlyGov {
        uint256 len = _parameters.length;
        for (uint256 i; i < len; ) {
            _setLockupFreeRate(_parameters[i]);
            // prettier-ignore
            unchecked { ++i; }
        }
    }

    /// @notice Collect the farm reward by the collector
    /// @param _account The account that collect the reward for
    /// @param _nonceAndLockupPeriod The packed values of the nonce and lockup period: bit 0-31 represent the nonce,
    /// bit 32-47 represent the lockup period
    /// @param _packedPoolRewardValues The packed values of the pool index, reward type, and amount: bit 0-23 represent
    /// the pool index, bit 24-39 represent the reward type, and bit 40-255 represent the amount
    /// @param _signature The signature of the parameters to verify
    /// @param _receiver The address that received the reward
    function collectBatch(
        address _account,
        PackedValue _nonceAndLockupPeriod,
        PackedValue[] calldata _packedPoolRewardValues,
        bytes calldata _signature,
        address _receiver
    ) external virtual onlyCollector {
        if (_receiver == address(0)) _receiver = msg.sender;

        // check nonce
        uint32 nonce = _nonceAndLockupPeriod.unpackUint32(0);
        if (nonce != _nonceFor(_account) + 1) revert PositionFarmRewardDistributor.InvalidNonce(nonce);

        // check lockup period
        uint16 lockupPeriod = _nonceAndLockupPeriod.unpackUint16(32);
        uint32 lockupFreeRate = lockupFreeRates[lockupPeriod];
        if (lockupFreeRate == 0) revert IFeeDistributor.InvalidLockupPeriod(lockupPeriod);

        // check signature
        address _signer = keccak256(abi.encode(_account, _nonceAndLockupPeriod, _packedPoolRewardValues))
            .toEthSignedMessageHash()
            .recover(_signature);
        if (_signer != signer) revert PositionFarmRewardDistributor.InvalidSignature();

        uint256 totalCollectableReward;
        IPool pool;
        PackedValue packedPoolRewardValue;
        uint256 len = _packedPoolRewardValues.length;
        for (uint256 i; i < len; ) {
            packedPoolRewardValue = _packedPoolRewardValues[i];
            pool = poolIndexer.indexPools(packedPoolRewardValue.unpackUint24(0));
            if (address(pool) == address(0)) revert PoolIndexer.InvalidPool(pool);

            uint16 rewardType = packedPoolRewardValue.unpackUint16(24);
            if (bytes(rewardTypesDescriptions[rewardType]).length == 0) revert InvalidRewardType(rewardType);

            uint216 amount = packedPoolRewardValue.unpackUint216(40);
            uint216 collectableReward = amount - _collectedRewardFor(_account, pool, rewardType);
            emit RewardCollected(pool, _account, rewardType, nonce, _receiver, collectableReward);

            collectedRewards[_account][pool][rewardType] = amount;
            totalCollectableReward += collectableReward;

            // prettier-ignore
            unchecked { ++i; }
        }

        nonces[_account] = nonce;
        Address.functionCall(
            address(token),
            abi.encodeWithSignature("mint(address,uint256)", address(this), totalCollectableReward)
        );

        // TODO: burn the token after the reward is distributed
    }

    function _nonceFor(address _account) internal view virtual returns (uint32 nonce) {
        nonce = nonces[_account];
        if (nonce == 0) nonce = distributorV1.nonces(_account);
    }

    function _collectedRewardFor(
        address _account,
        IPool _pool,
        uint16 _rewardType
    ) internal view virtual returns (uint216 collectedReward) {
        collectedReward = collectedRewards[_account][_pool][_rewardType];
        if (collectedReward == 0 && _rewardType == REWARD_TYPE_POSITION)
            collectedReward = distributorV1.collectedRewards(address(_pool), _account).toUint216();
    }

    function _setRewardType(uint16 _rewardType, string memory _description) internal virtual {
        require(bytes(_description).length <= 32);

        rewardTypesDescriptions[_rewardType] = _description;
        emit RewardTypeDescriptionSet(_rewardType, _description);
    }

    function _setLockupFreeRate(LockupFreeRateParameter memory _parameter) internal virtual {
        if (_parameter.lockupFreeRate > Constants.BASIS_POINTS_DIVISOR)
            revert InvalidLockupFreeRate(_parameter.lockupFreeRate);

        if (_parameter.period > 0)
            if (feeDistributor.lockupRewardMultipliers(_parameter.period) == 0)
                revert IFeeDistributor.InvalidLockupPeriod(_parameter.period);

        lockupFreeRates[_parameter.period] = _parameter.lockupFreeRate;
        emit LockupFreeRateSet(_parameter.period, _parameter.lockupFreeRate);
    }
}
