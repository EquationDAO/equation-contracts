// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../libraries/SafeCast.sol";
import "../libraries/Constants.sol";
import "../libraries/ReentrancyGuard.sol";
import {M as Math} from "../libraries/Math.sol";
import "../core/interfaces/IPoolFactory.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract RewardFarm is IRewardFarm, IRewardFarmCallback, Governable, ReentrancyGuard {
    using SafeCast for uint256;

    struct SearchBitmapStep {
        IPool pool;
        address referee;
        uint256 oldReferralToken;
        uint256 oldReferralParentToken;
        uint256 newReferralToken;
        uint256 newReferralParentToken;
        bool alreadyBoundReferralToken;
    }

    uint256 private constant REFERRAL_TOKEN_START_ID = 10000;

    IERC20 public immutable EQU;
    IPoolFactory public immutable poolFactory;
    IEFC public immutable EFC;
    Router public immutable router;
    /// @dev The referral multiplier after binding the referralToken.
    /// When calculating liquidity reward, if a referral code is bound, the liquidity is multiplied by this value.
    /// This value is calculated by multiplying the actual value with `Constants.BASIS_POINTS_DIVISOR`,
    /// For example, 110000000 represents a multiplier of 1.1.
    uint32 public immutable referralMultiplier;
    uint64 public immutable mintTime;

    /// @dev rewards already minted
    uint128 public mintedReward;
    /// @dev EQU token maximum supply
    uint128 public rewardCap = 10_000_000e18;

    /// @inheritdoc IRewardFarm
    Config public override config;
    /// @inheritdoc IRewardFarm
    mapping(IPool => PoolReward) public override poolRewards;

    /// @dev Mapping of referral token to referral reward information
    mapping(uint256 => ReferralReward) public referralRewards;
    /// @dev Mapping of account to risk buffer fund reward information
    mapping(address => RiskBufferFundReward) public riskBufferFundRewards;
    /// @dev Mapping of account to bound referral code
    mapping(address => bool) public alreadyBoundReferralTokens;
    /// @dev Mapping of account to liquidity reward information
    mapping(address => LiquidityReward) public liquidityRewards;
    /// @dev Mapping of account to position information
    mapping(address => Position) public positions;

    uint256 public poolIndexNext;
    mapping(IPool => uint256) public poolIndexes;
    mapping(uint256 => IPool) public indexPools;

    modifier onlyRouter() {
        if (msg.sender != address(router)) revert InvalidCaller(msg.sender);
        _;
    }

    modifier onlyReferral() {
        if (msg.sender != address(EFC)) revert InvalidCaller(msg.sender);
        _;
    }

    modifier onlyPool() {
        if (!poolFactory.isPool(msg.sender)) revert InvalidCaller(msg.sender);
        _;
    }

    constructor(
        IPoolFactory _poolFactory,
        Router _router,
        IEFC _EFC,
        IERC20 _EQU,
        uint64 _mintTime,
        uint32 _referralMultiplier
    ) {
        if (_mintTime < block.timestamp) revert InvalidMintTime(_mintTime);
        poolFactory = _poolFactory;
        router = _router;
        EFC = _EFC;
        EQU = _EQU;
        mintTime = _mintTime;
        referralMultiplier = _referralMultiplier;
    }

    /// @inheritdoc IRewardFarmCallback
    function onLiquidityPositionChanged(
        address _account,
        int256 _liquidityDelta
    ) external override onlyPool nonReentrant {
        IPool pool = IPool(msg.sender);
        uint256 _poolIndex = _getOrRegisterPool(pool);
        if (_poolIndex == 0) return; // If the pool is not in the reward list, the reward will not be distributed

        PoolReward storage poolReward = _updateRewardGrowth(pool);

        LiquidityReward storage liquidityReward = liquidityRewards[_account];
        bool alreadyBoundReferralToken = alreadyBoundReferralTokens[_account];

        // Update pool liquidity
        if (alreadyBoundReferralToken)
            poolReward.referralLiquidity = _calculateLiquidity(poolReward.referralLiquidity, _liquidityDelta);
        else poolReward.liquidity = _calculateLiquidity(poolReward.liquidity, _liquidityDelta);

        Reward storage reward = liquidityReward.rewards[pool];
        _updateLiquidityRewardDebt(
            pool,
            _account,
            reward,
            alreadyBoundReferralToken,
            poolReward.liquidityRewardGrowthX64
        );

        uint128 liquidityBefore = reward.liquidity;
        uint128 liquidityAfter = _calculateLiquidity(liquidityBefore, _liquidityDelta);
        reward.liquidity = liquidityAfter;

        if ((liquidityBefore == 0 && liquidityAfter != 0) || (liquidityBefore != 0 && liquidityAfter == 0))
            liquidityReward.bitmap = liquidityReward.bitmap.flip(_unmaskPoolIndex(_poolIndex)); // flip the bit

        if (alreadyBoundReferralToken) {
            (uint256 referralToken, uint256 referralParentToken) = EFC.referrerTokens(_account);
            _updateReferralReward(pool, referralToken, poolReward.referralTokenRewardGrowthX64, _liquidityDelta);
            _updateReferralReward(
                pool,
                referralParentToken,
                poolReward.referralParentTokenRewardGrowthX64,
                _liquidityDelta
            );
        }
    }

    /// @inheritdoc IRewardFarmCallback
    function onRiskBufferFundPositionChanged(address _account, uint256 _liquidityAfter) external onlyPool nonReentrant {
        IPool pool = IPool(msg.sender);
        uint256 _poolIndex = _getOrRegisterPool(pool);
        if (_poolIndex == 0) return; // If the pool is not in the reward list, the reward will not be distributed

        PoolReward storage poolReward = _updateRewardGrowth(pool);
        RiskBufferFundReward storage riskBufferFundReward = riskBufferFundRewards[_account];
        Reward storage reward = riskBufferFundReward.rewards[pool];

        uint128 liquidityBefore = reward.liquidity;
        uint128 rewardGrowthAfterX64 = poolReward.riskBufferFundRewardGrowthX64;
        uint256 rewardDebtDelta = _calculateRewardDebt(rewardGrowthAfterX64, reward.rewardGrowthX64, liquidityBefore);
        reward.rewardGrowthX64 = rewardGrowthAfterX64;
        reward.liquidity = _liquidityAfter.toUint128();
        emit RiskBufferFundRewardDebtChanged(pool, _account, rewardDebtDelta);

        // prettier-ignore
        unchecked { riskBufferFundReward.rewardDebt += rewardDebtDelta; } // overflow is desired

        poolReward.riskBufferFundLiquidity = (
            (uint256(poolReward.riskBufferFundLiquidity) + _liquidityAfter - liquidityBefore)
        ).toUint128();
    }

    /// @inheritdoc IRewardFarmCallback
    function onPositionChanged(
        address _account,
        Side _side,
        uint128 _sizeAfter,
        uint160 _entryPriceAfterX96
    ) external override onlyPool nonReentrant {
        IPool pool = IPool(msg.sender);
        uint256 _poolIndex = _getOrRegisterPool(pool);
        if (_poolIndex == 0) return; // If the pool is not in the reward list, the reward will not be distributed

        Position storage position = positions[_account];
        SidePosition storage sidePosition = position.sidePositions[pool];
        SidePosition memory sidePositionCache = sidePosition;

        uint128 positionBefore;
        uint128 positionAfter = Math.mulDiv(_sizeAfter, _entryPriceAfterX96, Constants.Q96).toUint128();
        uint128 beforeMasked = sidePositionCache.long | sidePositionCache.short;
        uint128 afterMasked;
        if (_side.isLong()) {
            positionBefore = sidePositionCache.long;
            afterMasked = positionAfter | sidePositionCache.short;

            sidePosition.long = positionAfter;
        } else {
            positionBefore = sidePositionCache.short;
            afterMasked = positionAfter | sidePositionCache.long;

            sidePosition.short = positionAfter;
        }

        // Using bitwise operations can efficiently check the exists of either long or short positions.
        if ((beforeMasked == 0 && afterMasked != 0) || (beforeMasked != 0 && afterMasked == 0))
            position.bitmap = position.bitmap.flip(_unmaskPoolIndex(_poolIndex)); // flip the bit

        // To save gas, the subsequent calculations will only be executed when binding the referral code
        if (!alreadyBoundReferralTokens[_account]) return;

        PoolReward storage poolReward = _updateRewardGrowth(pool);
        poolReward.referralPosition = poolReward.referralPosition - positionBefore + positionAfter;

        (uint256 referralToken, uint256 referralParentToken) = EFC.referrerTokens(_account);
        _updateReferralPositionReward(
            pool,
            referralToken,
            poolReward.referralTokenPositionRewardGrowthX64,
            positionBefore,
            positionAfter
        );
        _updateReferralPositionReward(
            pool,
            referralParentToken,
            poolReward.referralParentTokenPositionRewardGrowthX64,
            positionBefore,
            positionAfter
        );
    }

    /// @inheritdoc IRewardFarmCallback
    function onChangeReferralToken(
        address _referee,
        uint256 _oldReferralToken,
        uint256 _oldReferralParentToken,
        uint256 _newReferralToken,
        uint256 _newReferralParentToken
    ) external override onlyReferral nonReentrant {
        SearchBitmapStep memory step = SearchBitmapStep({
            pool: IPool(address(0)),
            referee: _referee,
            oldReferralToken: _oldReferralToken,
            oldReferralParentToken: _oldReferralParentToken,
            newReferralToken: _newReferralToken,
            newReferralParentToken: _newReferralParentToken,
            alreadyBoundReferralToken: alreadyBoundReferralTokens[_referee]
        });

        _searchBitmap(liquidityRewards[_referee].bitmap, step, _changeReferralTokenForLiquidity);
        _searchBitmap(positions[_referee].bitmap, step, _changeReferralTokenForPosition);

        alreadyBoundReferralTokens[_referee] = true;
    }

    /// @inheritdoc IRewardFarm
    function collectLiquidityRewardBatch(
        IPool[] calldata _pools,
        address _account,
        address _receiver
    ) external override onlyRouter nonReentrant returns (uint256 rewardDebt) {
        LiquidityReward storage liquidityReward = liquidityRewards[_account];

        bool alreadyBoundReferralToken = alreadyBoundReferralTokens[_account];
        IPool pool;
        PoolReward storage poolReward;
        for (uint256 i; i < _pools.length; ++i) {
            pool = _pools[i];
            poolReward = _updateRewardGrowth(pool);

            _updateLiquidityRewardDebt(
                pool,
                _account,
                liquidityReward.rewards[pool],
                alreadyBoundReferralToken,
                poolReward.liquidityRewardGrowthX64
            );
        }

        rewardDebt = liquidityReward.rewardDebt;
        liquidityReward.rewardDebt = 0; // reset reward debt

        _mintEQU(_receiver, rewardDebt);
        emit LiquidityRewardCollected(_pools, _account, _receiver, rewardDebt);
    }

    /// @inheritdoc IRewardFarm
    function collectRiskBufferFundRewardBatch(
        IPool[] calldata _pools,
        address _account,
        address _receiver
    ) external override onlyRouter nonReentrant returns (uint256 rewardDebt) {
        RiskBufferFundReward storage riskBufferFundReward = riskBufferFundRewards[_account];

        IPool pool;
        Reward storage reward;
        PoolReward storage poolReward;
        uint256 rewardDebtDelta;
        uint128 rewardGrowthAfterX64;
        for (uint256 i; i < _pools.length; ++i) {
            pool = _pools[i];
            poolReward = _updateRewardGrowth(pool);
            rewardGrowthAfterX64 = poolReward.riskBufferFundRewardGrowthX64;

            reward = riskBufferFundReward.rewards[pool];
            rewardDebtDelta = _calculateRewardDebt(rewardGrowthAfterX64, reward.rewardGrowthX64, reward.liquidity);
            reward.rewardGrowthX64 = rewardGrowthAfterX64;
            emit RiskBufferFundRewardDebtChanged(pool, _account, rewardDebtDelta);

            rewardDebt += rewardDebtDelta;
        }

        rewardDebt += riskBufferFundReward.rewardDebt;
        riskBufferFundReward.rewardDebt = 0;

        _mintEQU(_receiver, rewardDebt);
        emit RiskBufferFundRewardCollected(_pools, _account, _receiver, rewardDebt);
    }

    /// @inheritdoc IRewardFarm
    function collectReferralRewardBatch(
        IPool[] calldata _pools,
        uint256[] calldata _referralTokens,
        address _receiver
    ) external override onlyRouter nonReentrant returns (uint256 rewardDebt) {
        IPool pool;
        PoolReward storage poolReward;
        uint256 referralToken;
        uint128 rewardGrowthX64;
        uint128 positionRewardGrowthX64;
        for (uint256 i; i < _pools.length; ++i) {
            pool = _pools[i];
            poolReward = _updateRewardGrowth(pool);

            for (uint256 j; j < _referralTokens.length; ++j) {
                referralToken = _referralTokens[j];
                if (_isReferralParentToken(referralToken)) {
                    rewardGrowthX64 = poolReward.referralParentTokenRewardGrowthX64;
                    positionRewardGrowthX64 = poolReward.referralParentTokenPositionRewardGrowthX64;
                } else {
                    rewardGrowthX64 = poolReward.referralTokenRewardGrowthX64;
                    positionRewardGrowthX64 = poolReward.referralTokenPositionRewardGrowthX64;
                }

                _updateReferralReward(pool, referralToken, rewardGrowthX64, 0);

                _updateReferralPositionReward(pool, referralToken, positionRewardGrowthX64, 0, 0);

                rewardDebt += referralRewards[referralToken].rewardDebt;
                referralRewards[referralToken].rewardDebt = 0;
            }
        }

        _mintEQU(_receiver, rewardDebt);
        emit ReferralRewardCollected(_pools, _referralTokens, _receiver, rewardDebt);
    }

    /// @inheritdoc IRewardFarm
    function setPoolsReward(
        IPool[] calldata _pools,
        uint128[] calldata _rewardsPerSecond
    ) external override onlyGov nonReentrant {
        if (_pools.length != _rewardsPerSecond.length) revert InvalidArgument();

        uint128 lastMintTimeAfter = Math.max(block.timestamp, mintTime).toUint128();
        for (uint256 i; i < _pools.length; ++i) {
            IPool pool = _pools[i];
            PoolReward storage poolReward = poolRewards[pool];
            if (poolReward.rewardPerSecond != 0) {
                _updateRewardGrowth(pool);
                poolReward.rewardPerSecond = _rewardsPerSecond[i];
            } else {
                if (!poolFactory.isPool(address(pool))) revert InvalidPool(pool);

                if (_rewardsPerSecond[i] != 0) {
                    uint256 _poolIndex = _getOrRegisterPool(pool);

                    if (_poolIndex == 0) revert TooManyPools();

                    poolReward.rewardPerSecond = _rewardsPerSecond[i];
                    poolReward.lastMintTime = lastMintTimeAfter;
                }
            }
            emit PoolRewardUpdated(pool, _rewardsPerSecond[i]);
        }
    }

    /// @inheritdoc IRewardFarm
    function setConfig(Config memory _config) external override onlyGov nonReentrant {
        _validateConfig(_config);

        _updateAllPoolReward();

        config = _config;
        emit ConfigChanged(_config);
    }

    /// @inheritdoc IRewardFarm
    function setRewardCap(uint128 _rewardCap) external override onlyGov nonReentrant {
        _updateAllPoolReward();

        if (mintedReward > _rewardCap) revert InvalidRewardCap();

        rewardCap = _rewardCap;
        emit RewardCapChanged(_rewardCap);
    }

    /// @notice Get the referral reward information associated with a pool
    /// @param _referralToken The ID of the referral token
    /// @param _pool The address of the pool
    /// @return liquidity The total liquidity of all referees
    /// @return rewardGrowthX64 The snapshot of
    /// `PoolReward.referralTokenRewardGrowthX64` or `PoolReward.referralParentTokenRewardGrowthX64`
    /// @return position The total position value of all referees
    /// @return positionRewardGrowthX64 The snapshot of
    /// `PoolReward.referralTokenPositionRewardGrowthX64` or `PoolReward.referralParentTokenPositionRewardGrowthX64`
    function referralRewardsWithPool(
        uint256 _referralToken,
        IPool _pool
    )
        external
        view
        returns (uint128 liquidity, uint128 rewardGrowthX64, uint128 position, uint128 positionRewardGrowthX64)
    {
        RewardWithPosition memory reward = referralRewards[_referralToken].rewards[_pool];
        return (reward.liquidity, reward.rewardGrowthX64, reward.position, reward.positionRewardGrowthX64);
    }

    /// @notice Get the reward information of the risk buffer fund associated with a pool
    /// @param _account The owner of the risk buffer fund reward
    /// @param _pool The address of the pool
    /// @return liquidity The liquidity of risk buffer fund position
    /// @return rewardGrowthX64 The snapshot of `PoolReward.riskBufferFundRewardGrowthX64`
    function riskBufferFundRewardsWithPool(
        address _account,
        IPool _pool
    ) external view returns (uint128 liquidity, uint128 rewardGrowthX64) {
        Reward memory reward = riskBufferFundRewards[_account].rewards[_pool];
        return (reward.liquidity, reward.rewardGrowthX64);
    }

    /// @notice Get the liquidity reward information associated with a pool
    /// @param _account The owner of the liquidity reward
    /// @param _pool The address of the pool
    /// @return liquidity The liquidity of LP position
    /// @return rewardGrowthX64 The snapshot of `PoolReward.liquidityRewardGrowthX64`
    function liquidityRewardsWithPool(
        address _account,
        IPool _pool
    ) external view returns (uint128 liquidity, uint128 rewardGrowthX64) {
        Reward memory reward = liquidityRewards[_account].rewards[_pool];
        return (reward.liquidity, reward.rewardGrowthX64);
    }

    /// @notice Get the position information associated with a pool
    /// @param _account The owner of the position
    /// @param _pool The address of the pool
    /// @return long The position value of a long position
    /// @return short The position value of a short position
    function positionsWithPool(address _account, IPool _pool) external view returns (uint128 long, uint128 short) {
        SidePosition memory position = positions[_account].sidePositions[_pool];
        return (position.long, position.short);
    }

    function _updateAllPoolReward() private {
        for (uint256 i; i < poolIndexNext; ++i) {
            IPool pool = indexPools[_maskPoolIndex(i)];
            if (poolRewards[pool].rewardPerSecond != 0) _updateRewardGrowth(pool);
        }
    }

    function _getOrRegisterPool(IPool _pool) private returns (uint256 _poolIndex) {
        _poolIndex = poolIndexes[_pool];
        if (_poolIndex == 0) {
            _poolIndex = poolIndexNext;
            if (_poolIndex > type(uint8).max) return 0;

            // prettier-ignore
            unchecked { poolIndexNext = _poolIndex + 1; } // increase pool index

            _poolIndex = _maskPoolIndex(_poolIndex);
            poolIndexes[_pool] = _poolIndex;
            indexPools[_poolIndex] = _pool;
        }
    }

    function _maskPoolIndex(uint256 _poolIndex) private pure returns (uint256) {
        return _poolIndex | (1 << 8);
    }

    function _unmaskPoolIndex(uint256 _poolIndex) private pure returns (uint8) {
        return uint8(_poolIndex);
    }

    /// @notice Calculate per share growth of liquidity
    /// @param _amount The amount of the reward
    /// @param _totalLiquidity The total liquidity
    function _calculatePerShareGrowthX64(
        uint256 _amount,
        uint256 _totalLiquidity
    ) private pure returns (uint128 perShareGrowthX64) {
        if (_totalLiquidity != 0) perShareGrowthX64 = Math.mulDiv(_amount, Constants.Q64, _totalLiquidity).toUint128();
    }

    function _searchBitmap(
        Bitmap _bitmap,
        SearchBitmapStep memory _step,
        function(SearchBitmapStep memory, PoolReward storage) internal _op
    ) private {
        uint256 startInclusive;
        uint8 next;
        bool found;
        PoolReward storage poolReward;
        while (startInclusive <= type(uint8).max) {
            (next, found) = _bitmap.searchNextPosition(uint8(startInclusive));

            if (!found) break;

            _step.pool = indexPools[_maskPoolIndex(next)];

            poolReward = _updateRewardGrowth(_step.pool);

            _op(_step, poolReward);

            // prettier-ignore
            unchecked { startInclusive = next + 1; } // search next pool
        }
    }

    function _changeReferralTokenForLiquidity(SearchBitmapStep memory _step, PoolReward storage _poolReward) internal {
        LiquidityReward storage liquidityReward = liquidityRewards[_step.referee];
        Reward storage reward = liquidityReward.rewards[_step.pool];

        _updateLiquidityRewardDebt(
            _step.pool,
            _step.referee,
            reward,
            _step.alreadyBoundReferralToken,
            _poolReward.liquidityRewardGrowthX64
        );

        int256 liquidityDelta = int256(uint256(reward.liquidity));
        uint128 tokenRewardGrowthX64 = _poolReward.referralTokenRewardGrowthX64;
        uint128 parentTokenRewardGrowthAfterX64 = _poolReward.referralParentTokenRewardGrowthX64;
        if (_step.oldReferralToken != 0) {
            _updateReferralReward(_step.pool, _step.oldReferralToken, tokenRewardGrowthX64, -liquidityDelta);
            _updateReferralReward(
                _step.pool,
                _step.oldReferralParentToken,
                parentTokenRewardGrowthAfterX64,
                -liquidityDelta
            );
        } else {
            _poolReward.liquidity -= uint128(uint256(liquidityDelta));
            _poolReward.referralLiquidity += uint128(uint256(liquidityDelta));
        }

        _updateReferralReward(_step.pool, _step.newReferralToken, tokenRewardGrowthX64, liquidityDelta);
        _updateReferralReward(
            _step.pool,
            _step.newReferralParentToken,
            parentTokenRewardGrowthAfterX64,
            liquidityDelta
        );
    }

    function _changeReferralTokenForPosition(SearchBitmapStep memory _step, PoolReward storage _poolReward) internal {
        SidePosition memory sidePositionCache = positions[_step.referee].sidePositions[_step.pool];

        uint128 totalPosition = sidePositionCache.long + sidePositionCache.short;
        uint128 tokenRewardGrowthX64 = _poolReward.referralTokenPositionRewardGrowthX64;
        uint128 parentTokenRewardGrowthX64 = _poolReward.referralParentTokenPositionRewardGrowthX64;
        if (_step.oldReferralToken != 0) {
            _updateReferralPositionReward(_step.pool, _step.oldReferralToken, tokenRewardGrowthX64, totalPosition, 0);
            _updateReferralPositionReward(
                _step.pool,
                _step.oldReferralParentToken,
                parentTokenRewardGrowthX64,
                totalPosition,
                0
            );
        } else {
            _poolReward.referralPosition += totalPosition;
        }

        _updateReferralPositionReward(_step.pool, _step.newReferralToken, tokenRewardGrowthX64, 0, totalPosition);
        _updateReferralPositionReward(
            _step.pool,
            _step.newReferralParentToken,
            parentTokenRewardGrowthX64,
            0,
            totalPosition
        );
    }

    /// @notice Update pool reward growth
    /// @param _pool The address of the pool
    function _updateRewardGrowth(IPool _pool) private returns (PoolReward storage poolReward) {
        poolReward = poolRewards[_pool];
        uint128 rewardPerSecond = poolReward.rewardPerSecond;

        if (rewardPerSecond == 0) return poolReward;

        uint128 blockTimestamp = block.timestamp.toUint128();
        uint256 totalReward = _calculateReward(blockTimestamp, poolReward.lastMintTime, rewardPerSecond);
        if (totalReward == 0) return poolReward;

        uint256 totalRewardUsed;

        (uint128 liquidity, uint128 referralLiquidity) = (poolReward.liquidity, poolReward.referralLiquidity);
        if ((liquidity | referralLiquidity) != 0) {
            uint256 liquidityRewardUsed = _splitReward(totalReward, config.liquidityRate);
            uint256 referralLiquidityWithMultiplier = Math.mulDivUp(
                referralLiquidity,
                referralMultiplier,
                Constants.BASIS_POINTS_DIVISOR
            );
            poolReward.liquidityRewardGrowthX64 += _calculatePerShareGrowthX64(
                liquidityRewardUsed,
                liquidity + referralLiquidityWithMultiplier
            );
            emit PoolLiquidityRewardGrowthIncreased(_pool, liquidityRewardUsed, poolReward.liquidityRewardGrowthX64);

            totalRewardUsed = liquidityRewardUsed;
        }

        uint128 referralPosition = poolReward.referralPosition;
        uint256 totalReferralLiquidity = referralLiquidity + referralPosition;
        if (totalReferralLiquidity != 0 && config.referralTokenRate > 0) {
            uint256 rewardUsed = _splitReward(totalReward, config.referralTokenRate);
            uint256 liquidityRewardUsed = Math.mulDiv(rewardUsed, referralLiquidity, totalReferralLiquidity);
            uint128 growthDeltaX64 = _calculatePerShareGrowthX64(liquidityRewardUsed, referralLiquidity);
            poolReward.referralTokenRewardGrowthX64 += growthDeltaX64;

            uint256 positionRewardUsed = rewardUsed - liquidityRewardUsed;
            growthDeltaX64 = _calculatePerShareGrowthX64(positionRewardUsed, referralPosition);
            poolReward.referralTokenPositionRewardGrowthX64 += growthDeltaX64;

            emit PoolReferralTokenRewardGrowthIncreased(
                _pool,
                liquidityRewardUsed,
                poolReward.referralTokenRewardGrowthX64,
                positionRewardUsed,
                poolReward.referralTokenPositionRewardGrowthX64
            );

            // prettier-ignore
            unchecked { totalRewardUsed += rewardUsed; }
        }

        if (totalReferralLiquidity != 0 && config.referralParentTokenRate > 0) {
            uint256 rewardUsed = _splitReward(totalReward, config.referralParentTokenRate);
            uint256 liquidityRewardUsed = Math.mulDiv(rewardUsed, referralLiquidity, totalReferralLiquidity);
            uint128 growthDeltaX64 = _calculatePerShareGrowthX64(liquidityRewardUsed, referralLiquidity);
            poolReward.referralParentTokenRewardGrowthX64 += growthDeltaX64;

            uint256 positionRewardUsed = rewardUsed - liquidityRewardUsed;
            growthDeltaX64 = _calculatePerShareGrowthX64(positionRewardUsed, referralPosition);
            poolReward.referralParentTokenPositionRewardGrowthX64 += growthDeltaX64;

            emit PoolReferralParentTokenRewardGrowthIncreased(
                _pool,
                liquidityRewardUsed,
                poolReward.referralParentTokenRewardGrowthX64,
                positionRewardUsed,
                poolReward.referralParentTokenPositionRewardGrowthX64
            );

            // prettier-ignore
            unchecked { totalRewardUsed += rewardUsed; }
        }

        uint128 riskBufferFundLiquidity = poolReward.riskBufferFundLiquidity;
        if (riskBufferFundLiquidity != 0) {
            uint256 rewardUsed = _splitReward(totalReward, config.riskBufferFundLiquidityRate);
            uint128 growthDeltaX64 = _calculatePerShareGrowthX64(rewardUsed, riskBufferFundLiquidity);
            poolReward.riskBufferFundRewardGrowthX64 += growthDeltaX64;

            emit PoolRiskBufferFundRewardGrowthIncreased(_pool, rewardUsed, poolReward.riskBufferFundRewardGrowthX64);

            // prettier-ignore
            unchecked { totalRewardUsed += rewardUsed; }
        }

        // prettier-ignore
        unchecked { mintedReward += uint128(totalRewardUsed); }
        poolReward.lastMintTime = blockTimestamp;
    }

    function _calculateReward(
        uint256 _blockTimestamp,
        uint256 _lastMinTime,
        uint128 _rewardPerSecond
    ) private view returns (uint256 amount) {
        uint128 _mintedReward = mintedReward;
        uint128 _rewardCap = rewardCap;
        if (_blockTimestamp > _lastMinTime && _rewardCap > _mintedReward) {
            amount = (_blockTimestamp - _lastMinTime) * _rewardPerSecond;
            // prettier-ignore
            unchecked { amount = Math.min(amount, _rewardCap - _mintedReward); }
        }
    }

    function _updateLiquidityRewardDebt(
        IPool _pool,
        address _account,
        Reward storage _reward,
        bool _alreadyBoundReferralToken,
        uint128 _poolRewardGrowthX64
    ) private {
        uint256 liquidity = _alreadyBoundReferralToken
            ? Math.mulDiv(_reward.liquidity, referralMultiplier, Constants.BASIS_POINTS_DIVISOR)
            : _reward.liquidity;
        uint256 rewardDebtDelta = _calculateRewardDebt(_poolRewardGrowthX64, _reward.rewardGrowthX64, liquidity);

        _reward.rewardGrowthX64 = _poolRewardGrowthX64;

        // prettier-ignore
        unchecked { liquidityRewards[_account].rewardDebt += rewardDebtDelta; } // overflow is desired

        emit LiquidityRewardDebtChanged(_pool, _account, rewardDebtDelta);
    }

    function _updateReferralReward(
        IPool _pool,
        uint256 _referralToken,
        uint128 _poolRewardGrowthX64,
        int256 _liquidityDelta
    ) private {
        ReferralReward storage referralReward = referralRewards[_referralToken];
        RewardWithPosition storage reward = referralReward.rewards[_pool];

        uint128 liquidity = reward.liquidity;
        uint256 rewardDebtDelta = _calculateRewardDebt(_poolRewardGrowthX64, reward.rewardGrowthX64, liquidity);

        reward.rewardGrowthX64 = _poolRewardGrowthX64;
        if (_liquidityDelta != 0) reward.liquidity = _calculateLiquidity(liquidity, _liquidityDelta);

        // prettier-ignore
        unchecked { referralReward.rewardDebt += rewardDebtDelta; } // overflow is desired

        emit ReferralLiquidityRewardDebtChanged(_pool, _referralToken, rewardDebtDelta);
    }

    function _updateReferralPositionReward(
        IPool _pool,
        uint256 _referralToken,
        uint128 _poolRewardGrowthX64,
        uint128 _positionBefore,
        uint128 _positionAfter
    ) private {
        ReferralReward storage referralReward = referralRewards[_referralToken];
        RewardWithPosition storage reward = referralReward.rewards[_pool];

        uint128 position = reward.position;
        uint256 rewardDebtDelta = _calculateRewardDebt(_poolRewardGrowthX64, reward.positionRewardGrowthX64, position);

        reward.positionRewardGrowthX64 = _poolRewardGrowthX64;
        if ((_positionBefore | _positionAfter) != 0) reward.position = position - _positionBefore + _positionAfter;

        // prettier-ignore
        unchecked { referralReward.rewardDebt += rewardDebtDelta; } // overflow is desired

        emit ReferralPositionRewardDebtChanged(_pool, _referralToken, rewardDebtDelta);
    }

    function _splitReward(uint256 _reward, uint32 _rate) private pure returns (uint256 amount) {
        amount = Math.mulDiv(_reward, _rate, Constants.BASIS_POINTS_DIVISOR);
    }

    function _calculateLiquidity(
        uint128 _liquidity,
        int256 _liquidityDelta
    ) private pure returns (uint128 liquidityAfter) {
        // Since the maximum value of IPoolLiquidityPosition.GlobalLiquidityPosition.liquidity is type(uint128).max,
        // there will be no overflow here.
        unchecked {
            // The liquidityDelta is at most -type(uint128).max, so -liquidityDelta will not overflow here
            if (_liquidityDelta < 0) liquidityAfter = uint128(_liquidity - uint256(-_liquidityDelta));
            else liquidityAfter = uint128(_liquidity + uint256(_liquidityDelta));
        }
    }

    function _calculateRewardDebt(
        uint256 _globalRewardGrowthX64,
        uint256 _rewardGrowthX64,
        uint256 _liquidity
    ) private pure returns (uint256 rewardDebt) {
        // prettier-ignore
        unchecked { rewardDebt = Math.mulDiv(_globalRewardGrowthX64 - _rewardGrowthX64, _liquidity, Constants.Q64); }
    }

    function _mintEQU(address _to, uint256 _amount) internal {
        Address.functionCall(address(EQU), abi.encodeWithSignature("mint(address,uint256)", _to, _amount));
    }

    function _validateConfig(Config memory _newCfg) private pure {
        uint256 totalRate = uint256(_newCfg.liquidityRate) + _newCfg.riskBufferFundLiquidityRate;
        totalRate += _newCfg.referralTokenRate + _newCfg.referralParentTokenRate;
        if (totalRate != Constants.BASIS_POINTS_DIVISOR) revert InvalidMiningRate(totalRate);
    }

    function _isReferralParentToken(uint256 _referralToken) private pure returns (bool) {
        return _referralToken < REFERRAL_TOKEN_START_ID;
    }
}
