// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFeeDistributor {
    /// @notice Emitted when EQU tokens are staked
    /// @param sender The address to apply for staking
    /// @param account Which address to stake to
    /// @param id Index of EQU tokens staking information
    /// @param amount The amount of EQU tokens that already staked
    /// @param period Lockup period
    event Staked(address indexed sender, address indexed account, uint256 indexed id, uint256 amount, uint16 period);

    /// @notice Emitted when Uniswap V3 positions NFTs are staked
    /// @param sender The address to apply for staking
    /// @param account Which address to stake to
    /// @param id Index of Uniswap V3 positions NFTs staking information
    /// @param amount The amount of Uniswap V3 positions NFT converted into EQU tokens that already staked
    /// @param period Lockup period
    event V3PosStaked(
        address indexed sender,
        address indexed account,
        uint256 indexed id,
        uint256 amount,
        uint16 period
    );

    /// @notice Emitted when EQU tokens are unstaked
    /// @param owner The address to apply for unstaking
    /// @param receiver The address used to receive the stake tokens
    /// @param id Index of EQU tokens staking information
    /// @param amount0 The amount of EQU tokens that already unstaked
    /// @param amount1 The amount of staking rewards received
    event Unstaked(
        address indexed owner,
        address indexed receiver,
        uint256 indexed id,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when Uniswap V3 positions NFTs are unstaked
    /// @param owner The address to apply for unstaking
    /// @param receiver The address used to receive the Uniswap V3 positions NFT
    /// @param id Index of Uniswap V3 positions NFTs staking information
    /// @param amount0 The amount of Uniswap V3 positions NFT converted into EQU tokens that already unstaked
    /// @param amount1 The amount of staking rewards received
    event V3PosUnstaked(
        address indexed owner,
        address indexed receiver,
        uint256 indexed id,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when claiming stake rewards
    /// @param owner The address to apply for claiming staking rewards
    /// @param receiver The address used to receive staking rewards
    /// @param id Index of EQU tokens staking information
    /// @param amount The amount of staking rewards received
    event Collected(address indexed owner, address indexed receiver, uint256 indexed id, uint256 amount);

    /// @notice Emitted when claiming stake rewards
    /// @param owner The address to apply for claiming staking rewards
    /// @param receiver The address used to receive staking rewards
    /// @param id Index of Uniswap V3 positions NFTs staking information
    /// @param amount The amount of staking rewards received
    event V3PosCollected(address indexed owner, address indexed receiver, uint256 indexed id, uint256 amount);

    /// @notice Emitted when claiming Architect-type NFT rewards
    /// @param receiver The address used to receive rewards
    /// @param tokenID The ID of the Architect-type NFT
    /// @param amount The amount of rewards received
    event ArchitectCollected(address indexed receiver, uint256 indexed tokenID, uint256 amount);

    /// @notice Emitted when deposit staking reward tokens
    /// @param amount The amount of staking reward tokens deposited
    /// @param equFeeAmount The amount of reward tokens allocated to the EQU
    /// @param architectFeeAmount The amount of reward tokens allocated to the Architect-type NFT pool
    /// @param perShareGrowthAfterX64 The adjusted `perShareGrowthX64`, as a Q96.64
    /// @param architectPerShareGrowthAfterX64 The adjusted `architectPerShareGrowthX64`, as a Q96.64
    event FeeDeposited(
        uint256 amount,
        uint256 equFeeAmount,
        uint256 architectFeeAmount,
        uint160 perShareGrowthAfterX64,
        uint160 architectPerShareGrowthAfterX64
    );

    /// @notice Emitted when the lockup periods and lockup multipliers are set
    /// @param lockupRewardMultiplierParameters The list of LockupRewardMultiplierParameter
    event LockupRewardMultipliersSet(LockupRewardMultiplierParameter[] lockupRewardMultiplierParameters);

    /// @notice The number of Architect-type NFT that has been mined is 0
    /// or the EQU tokens that Uniswap V3 positions NFTs converted into total staked amount is 0.
    error DepositConditionNotMet();
    /// @notice Invalid caller
    error InvalidCaller(address caller);
    /// @notice Invalid NFT owner
    error InvalidNFTOwner(address owner, uint256 tokenID);
    /// @notice Invalid lockup period
    error InvalidLockupPeriod(uint16 period);
    /// @notice Invalid StakeID
    error InvalidStakeID(uint256 id);
    /// @notice Not yet reached the unlocking time
    error NotYetReachedTheUnlockingTime(uint256 id);
    /// @notice Deposit amount is greater than the transfer amount
    error DepositAmountIsGreaterThanTheTransfer(uint256 depositAmount, uint256 balance);
    /// @notice The NFT is not part of the EQU-WETH pool
    error InvalidUniswapV3PositionNFT(address token0, address token1);
    /// @notice The exchangeable amount of EQU is 0
    error ExchangeableEQUAmountIsZero();
    /// @notice Invalid Uniswap V3 fee
    error InvalidUniswapV3Fee(uint24 fee);
    /// @notice The price range of the Uniswap V3 position is not full range
    error RequireFullRangePosition(int24 tickLower, int24 tickUpper, int24 tickSpacing);

    struct StakeInfo {
        uint256 amount;
        uint64 lockupStartTime;
        uint16 multiplier;
        uint16 period;
        uint160 perShareGrowthX64;
    }

    struct LockupRewardMultiplierParameter {
        uint16 period;
        uint16 multiplier;
    }

    /// @notice Get the fee token balance
    /// @return balance The balance of the fee token
    function feeBalance() external view returns (uint96 balance);

    /// @notice Get the fee token
    /// @return token The fee token
    function feeToken() external view returns (IERC20 token);

    /// @notice Get the total amount with multiplier of staked EQU tokens
    /// @return amount The total amount with multiplier of staked EQU tokens
    function totalStakedWithMultiplier() external view returns (uint256 amount);

    /// @notice Get the accumulated staking rewards growth per share
    /// @return perShareGrowthX64 The accumulated staking rewards growth per share, as a Q96.64
    function perShareGrowthX64() external view returns (uint160 perShareGrowthX64);

    /// @notice Get EQU staking information
    /// @param account The staker of EQU tokens
    /// @param stakeID Index of EQU tokens staking information
    /// @return amount The amount of EQU tokens that already staked
    /// @return lockupStartTime Lockup start time
    /// @return multiplier Lockup reward multiplier
    /// @return period Lockup period
    /// @return perShareGrowthX64 The accumulated staking rewards growth per share, as a Q96.64
    function stakeInfos(
        address account,
        uint256 stakeID
    )
        external
        view
        returns (uint256 amount, uint64 lockupStartTime, uint16 multiplier, uint16 period, uint160 perShareGrowthX64);

    /// @notice Get Uniswap V3 positions NFTs staking information
    /// @param account The staker of Uniswap V3 positions NFTs
    /// @param stakeID Index of Uniswap V3 positions NFTs staking information
    /// @return amount The amount of EQU tokens that Uniswap V3 positions NFTs converted into that already staked
    /// @return lockupStartTime Lockup start time
    /// @return multiplier Lockup reward multiplier
    /// @return period Lockup period
    /// @return perShareGrowthX64 The accumulated staking rewards growth per share, as a Q96.64
    function v3PosStakeInfos(
        address account,
        uint256 stakeID
    )
        external
        view
        returns (uint256 amount, uint64 lockupStartTime, uint16 multiplier, uint16 period, uint160 perShareGrowthX64);

    /// @notice Get withdrawal time period
    /// @return period Withdrawal time period
    function withdrawalPeriod() external view returns (uint16 period);

    /// @notice Get lockup multiplier based on lockup period
    /// @param period Lockup period
    /// @return multiplier Lockup multiplier
    function lockupRewardMultipliers(uint16 period) external view returns (uint16 multiplier);

    /// @notice The number of Architect-type NFTs minted
    /// @return quantity The number of Architect-type NFTs minted
    function mintedArchitects() external view returns (uint16 quantity);

    /// @notice Get the accumulated reward growth for each Architect-type NFT
    /// @return perShareGrowthX64 The accumulated reward growth for each Architect-type NFT, as a Q96.64
    function architectPerShareGrowthX64() external view returns (uint160 perShareGrowthX64);

    /// @notice Get the accumulated reward growth for each Architect-type NFT
    /// @param tokenID The ID of the Architect-type NFT
    /// @return perShareGrowthX64 The accumulated reward growth for each Architect-type NFT, as a Q96.64
    function architectPerShareGrowthX64s(uint256 tokenID) external view returns (uint160 perShareGrowthX64);

    /// @notice Set lockup reward multiplier
    /// @param lockupRewardMultiplierParameters The list of LockupRewardMultiplierParameter
    function setLockupRewardMultipliers(
        LockupRewardMultiplierParameter[] calldata lockupRewardMultiplierParameters
    ) external;

    /// @notice Deposite staking reward tokens
    /// @param amount The amount of reward tokens deposited
    function depositFee(uint256 amount) external;

    /// @notice Stake EQU
    /// @param amount The amount of EQU tokens that need to be staked
    /// @param account Which address to stake to
    /// @param period Lockup period
    function stake(uint256 amount, address account, uint16 period) external;

    /// @notice Stake Uniswap V3 positions NFT
    /// @param id The ID of the Uniswap V3 positions NFT
    /// @param account Which address to stake to
    /// @param period Lockup period
    function stakeV3Pos(uint256 id, address account, uint16 period) external;

    /// @notice Unstake EQU
    /// @param ids Indexs of EQU tokens staking information that need to be unstaked
    /// @param receiver The address used to receive the staked tokens
    /// @return rewardAmount The amount of staking reward tokens received
    function unstake(uint256[] calldata ids, address receiver) external returns (uint256 rewardAmount);

    /// @notice Unstake Uniswap V3 positions NFT
    /// @param ids Indexs of Uniswap V3 positions NFTs staking information that need to be unstaked
    /// @param receiver The address used to receive the Uniswap V3 positions NFTs
    /// @return rewardAmount The amount of staking reward tokens received
    function unstakeV3Pos(uint256[] calldata ids, address receiver) external returns (uint256 rewardAmount);

    /// @notice Collect EQU staking rewards through router
    /// @param owner The Staker
    /// @param receiver The address used to receive staking rewards
    /// @param ids Index of EQU tokens staking information that need to be collected
    /// @return rewardAmount The amount of staking reward tokens received
    function collectBatchByRouter(
        address owner,
        address receiver,
        uint256[] calldata ids
    ) external returns (uint256 rewardAmount);

    /// @notice Collect Uniswap V3 positions NFT staking rewards through router
    /// @param owner The Staker
    /// @param receiver The address used to receive staking reward tokens
    /// @param ids Index of Uniswap V3 positions NFTs staking information that need to be collected
    /// @return rewardAmount The amount of staking reward tokens received
    function collectV3PosBatchByRouter(
        address owner,
        address receiver,
        uint256[] calldata ids
    ) external returns (uint256 rewardAmount);

    /// @notice Collect rewards for architect-type NFTs through router
    /// @param receiver The address used to receive staking reward tokens
    /// @param tokenIDs The IDs of the Architect-type NFT
    /// @return rewardAmount The amount of staking reward tokens received
    function collectArchitectBatchByRouter(
        address receiver,
        uint256[] calldata tokenIDs
    ) external returns (uint256 rewardAmount);

    /// @notice Collect EQU staking rewards
    /// @param receiver The address used to receive staking reward tokens
    /// @param ids Index of EQU tokens staking information that need to be collected
    /// @return rewardAmount The amount of staking reward tokens received
    function collectBatch(address receiver, uint256[] calldata ids) external returns (uint256 rewardAmount);

    /// @notice Collect Uniswap V3 positions NFT staking rewards
    /// @param receiver The address used to receive staking reward tokens
    /// @param ids Index of Uniswap V3 positions NFTs staking information that need to be collected
    /// @return rewardAmount The amount of staking reward tokens received
    function collectV3PosBatch(address receiver, uint256[] calldata ids) external returns (uint256 rewardAmount);

    /// @notice Collect rewards for architect-type NFTs
    /// @param receiver The address used to receive rewards
    /// @param tokenIDs The IDs of the Architect-type NFT
    /// @return rewardAmount The amount of staking reward tokens received
    function collectArchitectBatch(
        address receiver,
        uint256[] calldata tokenIDs
    ) external returns (uint256 rewardAmount);
}
