// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../core/interfaces/IPool.sol";
import {Bitmap} from "../../types/Bitmap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardFarm {
    /// @notice Emitted when the reward debt is changed
    /// @param pool The address of the pool
    /// @param account The owner of the liquidity reward
    /// @param rewardDebtDelta The change in reward debt for the account
    event LiquidityRewardDebtChanged(IPool indexed pool, address indexed account, uint256 rewardDebtDelta);

    /// @notice Emitted when the liquidity reward is collected
    /// @param pools The pool addresses
    /// @param account The owner of the liquidity reward
    /// @param receiver The address to receive the liquidity reward
    /// @param rewardDebt The amount of liquidity reward received
    event LiquidityRewardCollected(
        IPool[] pools,
        address indexed account,
        address indexed receiver,
        uint256 rewardDebt
    );

    /// @notice Emitted when the risk buffer fund reward debt is changed
    /// @param pool The address of the pool
    /// @param account The owner of the risk buffer fund reward
    /// @param rewardDebtDelta The change in reward debt for the account
    event RiskBufferFundRewardDebtChanged(IPool indexed pool, address indexed account, uint256 rewardDebtDelta);

    /// @notice Emitted when the risk buffer fund reward is collected
    /// @param pools The pool addresses
    /// @param account The owner of the risk buffer fund reward
    /// @param receiver The address to receive the liquidity reward
    /// @param rewardDebt The amount of risk buffer fund reward received
    event RiskBufferFundRewardCollected(
        IPool[] pools,
        address indexed account,
        address indexed receiver,
        uint256 rewardDebt
    );

    /// @notice Emitted when the liquidity reward growth is increased
    /// @param pool The address of the pool
    /// @param rewardDelta The change in liquidity reward for the pool
    /// @param rewardGrowthAfterX64 The adjusted `PoolReward.liquidityRewardGrowthX64`, as a Q64.64
    event PoolLiquidityRewardGrowthIncreased(IPool indexed pool, uint256 rewardDelta, uint128 rewardGrowthAfterX64);

    /// @notice Emitted when the referral token reward growth is increased
    /// @param pool The address of the pool
    /// @param rewardDelta The change in referral token reward for the pool
    /// @param rewardGrowthAfterX64 The adjusted `PoolReward.referralTokenRewardGrowthX64`, as a Q64.64
    /// @param positionRewardDelta The change in referral token position reward for the pool
    /// @param positionRewardGrowthAfterX64 The adjusted
    /// `PoolReward.referralTokenPositionRewardGrowthX64`, as a Q64.64
    event PoolReferralTokenRewardGrowthIncreased(
        IPool indexed pool,
        uint256 rewardDelta,
        uint128 rewardGrowthAfterX64,
        uint256 positionRewardDelta,
        uint128 positionRewardGrowthAfterX64
    );

    /// @notice Emitted when the referral token reward growth is increased
    /// @param pool The address of the pool
    /// @param rewardDelta The change in referral parent token reward for the pool
    /// @param rewardGrowthAfterX64 The adjusted `PoolReward.referralParentTokenRewardGrowthX64`, as a Q64.64
    /// @param positionRewardDelta The change in referral parent token position reward for the pool
    /// @param positionRewardGrowthAfterX64 The adjusted
    /// `PoolReward.referralParentTokenPositionRewardGrowthX64`, as a Q64.64
    event PoolReferralParentTokenRewardGrowthIncreased(
        IPool indexed pool,
        uint256 rewardDelta,
        uint128 rewardGrowthAfterX64,
        uint256 positionRewardDelta,
        uint128 positionRewardGrowthAfterX64
    );

    /// @notice Emitted when the risk buffer fund reward growth is increased
    /// @param pool The address of the pool
    /// @param rewardDelta The change in risk buffer fund reward for the pool
    /// @param rewardGrowthAfterX64 The adjusted `PoolReward.riskBufferFundRewardGrowthX64`, as a Q64.64
    event PoolRiskBufferFundRewardGrowthIncreased(
        IPool indexed pool,
        uint256 rewardDelta,
        uint128 rewardGrowthAfterX64
    );

    /// @notice Emitted when the pool reward updated
    /// @param pool The address of the pool
    /// @param rewardPerSecond The amount minted per second
    event PoolRewardUpdated(IPool indexed pool, uint160 rewardPerSecond);

    /// @notice Emitted when the referral liquidity reward debt is changed
    /// @param pool The address of the pool
    /// @param referralToken The ID of the referral token
    /// @param rewardDebtDelta The change in reward debt for the referral token
    event ReferralLiquidityRewardDebtChanged(
        IPool indexed pool,
        uint256 indexed referralToken,
        uint256 rewardDebtDelta
    );

    /// @notice Emitted when the referral position reward debt is changed
    /// @param pool The address of the pool
    /// @param referralToken The ID of the referral token
    /// @param rewardDebtDelta The change in reward debt for the referral token
    event ReferralPositionRewardDebtChanged(IPool indexed pool, uint256 indexed referralToken, uint256 rewardDebtDelta);

    /// @notice Emitted when the referral reward is collected
    /// @param pools The pool addresses
    /// @param referralTokens The IDs of the referral tokens
    /// @param receiver The address to receive the referral reward
    /// @param rewardDebt The amount of the referral reward received
    event ReferralRewardCollected(
        IPool[] pools,
        uint256[] referralTokens,
        address indexed receiver,
        uint256 rewardDebt
    );

    /// @notice Emitted when configuration is changed
    /// @param newConfig The new configuration
    event ConfigChanged(Config newConfig);

    /// @notice Emitted when the reward cap is changed
    /// @param rewardCapAfter The reward cap after change
    event RewardCapChanged(uint128 rewardCapAfter);

    /// @notice Invalid caller
    error InvalidCaller(address caller);
    /// @notice Invalid argument
    error InvalidArgument();
    /// @notice Invalid pool
    error InvalidPool(IPool pool);
    /// @notice Invalid mint time
    /// @param mintTime The time of starting minting
    error InvalidMintTime(uint64 mintTime);
    /// @notice Invalid mining rate
    /// @param rate The rate of mining
    error InvalidMiningRate(uint256 rate);
    /// @notice Too many pools
    error TooManyPools();
    /// @notice Invalid reward cap
    error InvalidRewardCap();

    struct Config {
        uint32 liquidityRate;
        uint32 riskBufferFundLiquidityRate;
        uint32 referralTokenRate;
        uint32 referralParentTokenRate;
    }

    struct PoolReward {
        uint128 liquidity;
        uint128 liquidityRewardGrowthX64;
        uint128 referralLiquidity;
        uint128 referralTokenRewardGrowthX64;
        uint128 referralParentTokenRewardGrowthX64;
        uint128 referralPosition;
        uint128 referralTokenPositionRewardGrowthX64;
        uint128 referralParentTokenPositionRewardGrowthX64;
        uint128 riskBufferFundLiquidity;
        uint128 riskBufferFundRewardGrowthX64;
        uint128 rewardPerSecond;
        uint128 lastMintTime;
    }

    struct Reward {
        /// @dev The liquidity of risk buffer fund position or LP position
        uint128 liquidity;
        /// @dev The snapshot of `PoolReward.riskBufferFundRewardGrowthX64` or `PoolReward.liquidityRewardGrowthX64`
        uint128 rewardGrowthX64;
    }

    struct RewardWithPosition {
        /// @dev The total liquidity of all referees
        uint128 liquidity;
        /// @dev The snapshot of
        /// `PoolReward.referralTokenRewardGrowthX64` or `PoolReward.referralParentTokenRewardGrowthX64`
        uint128 rewardGrowthX64;
        /// @dev The total position value of all referees
        uint128 position;
        /// @dev The snapshot of
        /// `PoolReward.referralTokenPositionRewardGrowthX64` or `PoolReward.referralParentTokenPositionRewardGrowthX64`
        uint128 positionRewardGrowthX64;
    }

    struct ReferralReward {
        /// @dev Unclaimed reward amount
        uint256 rewardDebt;
        /// @dev Mapping of pool to referral reward
        mapping(IPool => RewardWithPosition) rewards;
    }

    struct RiskBufferFundReward {
        /// @dev Unclaimed reward amount
        uint256 rewardDebt;
        /// @dev Mapping of pool to risk buffer fund reward
        mapping(IPool => Reward) rewards;
    }

    struct LiquidityReward {
        /// @dev The bitwise representation of the pool index with existing LP position
        Bitmap bitmap;
        /// @dev Unclaimed reward amount
        uint256 rewardDebt;
        /// @dev Mapping of pool to liquidity reward
        mapping(IPool => Reward) rewards;
    }

    struct SidePosition {
        /// @dev Value of long position
        uint128 long;
        /// @dev Value of short position
        uint128 short;
    }

    struct Position {
        /// @dev The bitwise representation of the pool index with existing position
        Bitmap bitmap;
        /// @dev Mapping of pool to position value
        mapping(IPool => SidePosition) sidePositions;
    }

    /// @notice Get mining rate configuration
    /// @return liquidityRate The liquidity rate as a percentage of mining,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return riskBufferFundLiquidityRate The risk buffer fund liquidity rate as a percentage of mining,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return referralTokenRate The referral token rate as a percentage of mining,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// @return referralParentTokenRate The referral parent token rate as a percentage of mining,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    function config()
        external
        view
        returns (
            uint32 liquidityRate,
            uint32 riskBufferFundLiquidityRate,
            uint32 referralTokenRate,
            uint32 referralParentTokenRate
        );

    /// @notice Get the pool reward
    /// @param pool The address of the pool
    /// @return liquidity The sum of all liquidity in this pool
    /// @return liquidityRewardGrowthX64 The reward growth per unit of liquidity, as a Q64.64
    /// @return referralLiquidity The sum of all the referral liquidity
    /// @return referralTokenRewardGrowthX64 The reward growth per unit of referral token liquidity, as a Q64.64
    /// @return referralParentTokenRewardGrowthX64 The reward growth per unit of referral token parent liquidity,
    /// as a Q64.64
    /// @return referralPosition The sum of all the referral position liquidity
    /// @return referralTokenPositionRewardGrowthX64 The reward growth per unit of referral token position liquidity,
    /// as a Q64.64
    /// @return referralParentTokenPositionRewardGrowthX64 The reward growth per unit of referral token parent
    /// position, as a Q64.64
    /// @return riskBufferFundLiquidity The sum of the liquidity of all risk buffer fund
    /// @return riskBufferFundRewardGrowthX64 The reward growth per unit of risk buffer fund liquidity, as a Q64.64
    /// @return rewardPerSecond The amount minted per second
    /// @return lastMintTime The Last mint time
    function poolRewards(
        IPool pool
    )
        external
        view
        returns (
            uint128 liquidity,
            uint128 liquidityRewardGrowthX64,
            uint128 referralLiquidity,
            uint128 referralTokenRewardGrowthX64,
            uint128 referralParentTokenRewardGrowthX64,
            uint128 referralPosition,
            uint128 referralTokenPositionRewardGrowthX64,
            uint128 referralParentTokenPositionRewardGrowthX64,
            uint128 riskBufferFundLiquidity,
            uint128 riskBufferFundRewardGrowthX64,
            uint128 rewardPerSecond,
            uint128 lastMintTime
        );

    /// @notice Collect the liquidity reward
    /// @param pools The pool addresses
    /// @param account The owner of the liquidity reward
    /// @param receiver The address to receive the reward
    /// @return rewardDebt The amount of liquidity reward received
    function collectLiquidityRewardBatch(
        IPool[] calldata pools,
        address account,
        address receiver
    ) external returns (uint256 rewardDebt);

    /// @notice Collect the risk buffer fund reward
    /// @param pools The pool addresses
    /// @param account The owner of the risk buffer fund reward
    /// @param receiver The address to receive the reward
    /// @return rewardDebt The amount of risk buffer fund reward received
    function collectRiskBufferFundRewardBatch(
        IPool[] calldata pools,
        address account,
        address receiver
    ) external returns (uint256 rewardDebt);

    /// @notice Collect the referral reward
    /// @param pools The pool addresses
    /// @param referralTokens The IDs of the referral tokens
    /// @param receiver The address to receive the referral reward
    /// @return rewardDebt The amount of the referral reward
    function collectReferralRewardBatch(
        IPool[] calldata pools,
        uint256[] calldata referralTokens,
        address receiver
    ) external returns (uint256 rewardDebt);

    /// @notice Set reward data for the pool
    /// @param pools The pool addresses
    /// @param rewardsPerSecond The EQU amount minted per second for pools
    function setPoolsReward(IPool[] calldata pools, uint128[] calldata rewardsPerSecond) external;

    /// @notice Set configuration information
    /// @param config The configuration
    function setConfig(Config memory config) external;

    /// @notice Set the reward cap
    /// @param rewardCap The reward cap
    function setRewardCap(uint128 rewardCap) external;
}
