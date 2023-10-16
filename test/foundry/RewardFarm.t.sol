// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import "../../contracts/core/Pool.sol";
import "../../contracts/farming/RewardFarm.sol";
import {EQU, ERC20} from "../../contracts/tokens/EQU.sol";
import {EFC} from "../../contracts/tokens/EFC.sol";
import "../../contracts/plugins/Router.sol";
import {PoolFactory} from "../../contracts/core/PoolFactory.sol";
import "../../contracts/test/MockRewardFarmCallback.sol";
import "../../contracts/test/MockFeeDistributorCallback.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/types/Bitmap.sol";
import "../../contracts/types/Side.sol";
import "../../contracts/core/interfaces/IConfigurable.sol";

contract RewardFarmTest is Test {
    using SafeCast for uint256;
    using SafeCast for int256;

    IPool pool;
    RewardFarm public rewardFarm;
    RewardFarm otherRewardFarm;
    PoolFactory poolFactory;
    EFC efc;
    Router router;
    IERC20 USDC;
    IERC20 BTC;
    IERC20 ETH;
    IPool BTCPool;
    IPool ETHPool;
    EQU equ;
    IConfigurable.TokenConfig tokenConfig;
    IConfigurable.TokenFeeRateConfig tokenFeeRateConfig;
    IConfigurable.VertexConfig[] vertexConfig;
    IConfigurable.TokenPriceConfig tokenPriceConfig;

    uint256 internal constant TOTAL_SUPPLY = 2_100 * 10_000 * 1e18;
    uint128 internal constant REWARDS_PER_SECOND = 0.1157407408 * 1e18;
    uint128 internal constant CHANGED_REWARDS_PER_SECOND = 0.1 * 1e18;
    address internal constant RECEIVER = address(8);
    address internal constant OWNER = address(9);
    address internal constant OTHER = address(10);
    address internal constant CONNECTOR_OWNER0 = address(11);
    address internal constant MEMBER_OWNER0 = address(12);
    address internal constant CONNECTOR_OWNER1 = address(13);
    address internal constant MEMBER_OWNER1 = address(14);
    uint32 internal constant LIQUIDITY_RATE = 40_000_000;
    uint32 internal constant RISK_BUFFERFUND_LIQUIDITY_RATE = 16_000_000;
    uint32 internal constant REFERRAL_TOKEN_RATE = 40_000_000;
    uint32 internal constant REFERRAL_PARENT_TOKEN_RATE = 4_000_000;
    uint32 internal constant REFERRAL_MULTIPLIER = 110_000_000;

    event LiquidityRewardDebtChanged(IPool indexed pool, address indexed account, uint256 rewardDebtDelta);
    event LiquidityRewardCollected(IPool[] pools, address indexed owner, address indexed receiver, uint256 rewardDebt);
    event RiskBufferFundRewardDebtChanged(IPool indexed pool, address indexed account, uint256 rewardDebtDelta);
    event RiskBufferFundRewardCollected(
        IPool[] pools,
        address indexed owner,
        address indexed receiver,
        uint256 rewardDebt
    );
    event PoolLiquidityRewardGrowthIncreased(IPool indexed pool, uint256 rewardDelta, uint128 rewardGrowthAfterX64);
    event PoolReferralTokenRewardGrowthIncreased(
        IPool indexed pool,
        uint256 rewardDelta,
        uint128 rewardGrowthAfterX64,
        uint256 positionRewardDelta,
        uint128 positionRewardGrowthAfterX64
    );
    event PoolReferralParentTokenRewardGrowthIncreased(
        IPool indexed pool,
        uint256 rewardDelta,
        uint128 rewardGrowthAfterX64,
        uint256 positionRewardDelta,
        uint128 positionRewardGrowthAfterX64
    );
    event PoolRiskBufferFundRewardGrowthIncreased(
        IPool indexed pool,
        uint256 rewardDelta,
        uint128 rewardGrowthAfterX64
    );
    event PoolRewardUpdated(IPool indexed pool, uint160 rewardPerSecond);
    event ReferralLiquidityRewardDebtChanged(
        IPool indexed pool,
        uint256 indexed referralToken,
        uint256 rewardDebtDelta
    );
    event ReferralPositionRewardDebtChanged(IPool indexed pool, uint256 indexed referralToken, uint256 rewardDebtDelta);
    event ReferralRewardCollected(
        IPool[] pools,
        uint256[] referralTokens,
        address indexed receiver,
        uint256 rewardDebt
    );
    event ConfigChanged(IRewardFarm.Config newConfig);
    event RewardCapChanged(uint128 rewardCapAfter);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        USDC = new ERC20("USDC TOKEN", "USDC");
        BTC = new ERC20("BTC TOKEN", "BTC");
        ETH = new ERC20("ETH TOKEN", "ETH");

        efc = new EFC(100, 100, 100, new MockRewardFarmCallback(), new MockFeeDistributorCallback());
        address[] memory connectorTo = new address[](2);
        connectorTo[0] = CONNECTOR_OWNER0;
        connectorTo[1] = CONNECTOR_OWNER1;
        efc.batchMintConnector(connectorTo);
        address[] memory member0To = new address[](1);
        member0To[0] = MEMBER_OWNER0;
        vm.prank(CONNECTOR_OWNER0);
        efc.batchMintMember(1000, member0To);
        address[] memory member1To = new address[](1);
        member1To[0] = MEMBER_OWNER1;
        vm.prank(CONNECTOR_OWNER1);
        efc.batchMintMember(1001, member1To);
        vm.prank(MEMBER_OWNER0);
        efc.registerCode(10000, "testCode10000");
        vm.prank(MEMBER_OWNER1);
        efc.registerCode(10100, "testCode10100");

        equ = new EQU();
        router = Router(address(1));
        poolFactory = new PoolFactory(
            IERC20(USDC),
            efc,
            router,
            IPriceFeed(address(0)),
            IFeeDistributor(address(0)),
            IRewardFarmCallback(address(0))
        );
        rewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);
        equ.setMinter(address(rewardFarm), true);

        // create BTC pool
        tokenConfig = IConfigurable.TokenConfig(
            10 * 10 ** 6,
            99_500_000,
            200,
            10 * 10 ** 6,
            200,
            200_000,
            600_000,
            1250,
            150_000
        );
        tokenFeeRateConfig = IConfigurable.TokenFeeRateConfig(
            50_000,
            50_000_000,
            30_000_000,
            10_000_000,
            1_000_000,
            90_000_000
        );
        vertexConfig = new IConfigurable.VertexConfig[](7);
        vertexConfig[0] = IConfigurable.VertexConfig(0, 0);
        vertexConfig[1] = IConfigurable.VertexConfig(4_000_000, 50_000);
        vertexConfig[2] = IConfigurable.VertexConfig(6_000_000, 100_000);
        vertexConfig[3] = IConfigurable.VertexConfig(8_000_000, 150_000);
        vertexConfig[4] = IConfigurable.VertexConfig(10_000_000, 200_000);
        vertexConfig[5] = IConfigurable.VertexConfig(20_000_000, 1_000_000);
        vertexConfig[6] = IConfigurable.VertexConfig(100_000_000, 10_000_000);
        tokenPriceConfig = IConfigurable.TokenPriceConfig(2_0000_0000 * 10 ** 6, 4, vertexConfig);
        poolFactory.concatPoolCreationCode(true, type(Pool).creationCode);
        poolFactory.enableToken(BTC, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
        BTCPool = poolFactory.createPool(BTC);
        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](1);
        pools[0] = BTCPool;
        rewardsPerSeconds[0] = REWARDS_PER_SECOND;
        rewardFarm.setPoolsReward(pools, rewardsPerSeconds);
        // create ETH pool
        poolFactory.enableToken(ETH, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
        ETHPool = poolFactory.createPool(ETH);
        IRewardFarm.Config memory config = IRewardFarm.Config(
            LIQUIDITY_RATE,
            RISK_BUFFERFUND_LIQUIDITY_RATE,
            REFERRAL_TOKEN_RATE,
            REFERRAL_PARENT_TOKEN_RATE
        );
        rewardFarm.setConfig(config);
    }

    /// ====== Test cases for the constructor function ======

    function test_constructor() public {
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);
        assertEqUint(otherRewardFarm.mintTime(), 1);
        assertEqUint(otherRewardFarm.referralMultiplier(), REFERRAL_MULTIPLIER);

        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidMintTime.selector, 1000));
        vm.warp(2000);
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1000, REFERRAL_MULTIPLIER);
    }

    /// ====== Test cases for the setPoolsReward function ======

    function test_setPoolsReward_RevertIf_TheCallerIsNotGov() public {
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);

        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](1);
        pools[0] = ETHPool;
        rewardsPerSeconds[0] = 1;
        vm.expectRevert(Governable.Forbidden.selector);
        vm.prank(address(0));
        otherRewardFarm.setPoolsReward(pools, rewardsPerSeconds);
    }

    function test_setPoolsReward_RevertIf_TheNumberOfPoolAndMintRewardIsNotEqual() public {
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);

        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](2);
        pools[0] = ETHPool;
        rewardsPerSeconds[0] = 1;
        rewardsPerSeconds[1] = 2;
        vm.expectRevert(IRewardFarm.InvalidArgument.selector);
        otherRewardFarm.setPoolsReward(pools, rewardsPerSeconds);
    }

    function test_setPoolsReward_RevertIf_ThePoolIsNotCreatedByPoolFactory() public {
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);

        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](1);
        pools[0] = IPool(address(0));
        rewardsPerSeconds[0] = 1;
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidPool.selector, pools[0]));
        otherRewardFarm.setPoolsReward(pools, rewardsPerSeconds);
    }

    function test_setPoolsReward_SetAndUpdateRewardPerSecond() public {
        vm.warp(100);
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 100, REFERRAL_MULTIPLIER);

        vm.warp(200);
        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](1);
        pools[0] = ETHPool;
        rewardsPerSeconds[0] = REWARDS_PER_SECOND;
        vm.expectEmit(true, false, false, true);
        emit PoolRewardUpdated(pools[0], rewardsPerSeconds[0]);
        otherRewardFarm.setPoolsReward(pools, rewardsPerSeconds);
        (, , , , , , , , , , uint128 rewardPerSecond, uint128 lastMintTime) = otherRewardFarm.poolRewards(ETHPool);
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 200);

        vm.warp(300);
        rewardsPerSeconds[0] = CHANGED_REWARDS_PER_SECOND;
        vm.expectEmit(true, false, false, true);
        emit PoolRewardUpdated(pools[0], rewardsPerSeconds[0]);
        otherRewardFarm.setPoolsReward(pools, rewardsPerSeconds);
        (, , , , , , , , , , rewardPerSecond, lastMintTime) = otherRewardFarm.poolRewards(ETHPool);
        assertEqUint(rewardPerSecond, CHANGED_REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 300);
    }

    function test_setPoolsReward_UseNewRewardsPerSecondToCalculateRewards() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        vm.warp(1);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, SHORT, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        vm.stopPrank();

        vm.warp(10001);
        vm.startPrank(address(router));
        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](1);
        pools[0] = BTCPool;
        uint256[] memory members = new uint256[](1);
        members[0] = 10000;
        uint256[] memory connectors = new uint256[](1);
        connectors[0] = 1000;
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        vm.stopPrank();
        rewardsPerSeconds[0] = CHANGED_REWARDS_PER_SECOND;
        rewardFarm.setPoolsReward(pools, rewardsPerSeconds);

        vm.warp(20001);
        vm.startPrank(address(router));
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(10000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                ),
                _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, LIQUIDITY_RATE),
                        _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                    ),
                    _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                )
        );
        assertEqUint(
            equ.balanceOf(MEMBER_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                        1000 * 1e6
                    ),
                    1000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(CONNECTOR_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                        1000 * 1e6
                    ),
                    1000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(OTHER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(10000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, CHANGED_REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                        1000 * 1e6
                    ),
                    1000 * 1e6
                )
        );
    }

    /// ====== Test cases for the setConfig function ======

    function test_setConfig() public {
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);

        IRewardFarm.Config memory rightConfig = IRewardFarm.Config(
            LIQUIDITY_RATE,
            RISK_BUFFERFUND_LIQUIDITY_RATE,
            REFERRAL_TOKEN_RATE,
            REFERRAL_PARENT_TOKEN_RATE
        );
        vm.expectRevert(Governable.Forbidden.selector);
        vm.prank(address(0));
        otherRewardFarm.setConfig(rightConfig);

        IRewardFarm.Config memory errorConfig = IRewardFarm.Config(4000, 1600, 4000, 400);
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidMiningRate.selector, 10000));
        otherRewardFarm.setConfig(errorConfig);

        vm.warp(100);
        vm.expectEmit(false, false, false, true);
        emit ConfigChanged(rightConfig);
        otherRewardFarm.setConfig(rightConfig);
        (
            uint32 liquidityRate,
            uint32 riskBufferFundLiquidityRate,
            uint32 referralTokenRate,
            uint32 referralParentTokenRate
        ) = otherRewardFarm.config();
        assertEqUint(liquidityRate, LIQUIDITY_RATE);
        assertEqUint(riskBufferFundLiquidityRate, RISK_BUFFERFUND_LIQUIDITY_RATE);
        assertEqUint(referralTokenRate, REFERRAL_TOKEN_RATE);
        assertEqUint(referralParentTokenRate, REFERRAL_PARENT_TOKEN_RATE);

        vm.warp(200);
        IRewardFarm.Config memory newConfig = IRewardFarm.Config(30_000_000, 15_000_000, 50_000_000, 5_000_000);
        vm.expectEmit(false, false, false, true);
        emit ConfigChanged(newConfig);
        otherRewardFarm.setConfig(newConfig);
        (liquidityRate, riskBufferFundLiquidityRate, referralTokenRate, referralParentTokenRate) = otherRewardFarm
            .config();
        assertEqUint(liquidityRate, 30_000_000);
        assertEqUint(riskBufferFundLiquidityRate, 15_000_000);
        assertEqUint(referralTokenRate, 50_000_000);
        assertEqUint(referralParentTokenRate, 5_000_000);
    }

    function test_setConfig_UseNewConfigToCalculateRewards() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        vm.warp(1);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, SHORT, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        vm.stopPrank();
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;

        vm.warp(10001);
        vm.startPrank(address(router));
        uint256[] memory members = new uint256[](1);
        members[0] = 10000;
        uint256[] memory connectors = new uint256[](1);
        connectors[0] = 1000;
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        vm.stopPrank();
        IRewardFarm.Config memory newConfig = IRewardFarm.Config(30_000_000, 15_000_000, 50_000_000, 5_000_000);
        rewardFarm.setConfig(newConfig);

        vm.warp(20001);
        vm.startPrank(address(router));
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(10000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                ),
                _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, 30_000_000),
                        _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                    ),
                    _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                )
        );
        assertEqUint(
            equ.balanceOf(MEMBER_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(10000, REWARDS_PER_SECOND, 50_000_000),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                        1000 * 1e6
                    ),
                    1000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, 50_000_000) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, REWARDS_PER_SECOND, 50_000_000),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(CONNECTOR_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(10000, REWARDS_PER_SECOND, 5_000_000),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                        1000 * 1e6
                    ),
                    1000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, 5_000_000) -
                            Math.mulDiv(
                                _calculateRewardDelta(10000, REWARDS_PER_SECOND, 5_000_000),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(OTHER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(10000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(10000, REWARDS_PER_SECOND, 15_000_000),
                        1000 * 1e6
                    ),
                    1000 * 1e6
                )
        );
    }

    /// ====== Test cases for the setRewardCap function ======

    function test_setRewardCap() public {
        vm.prank(address(0));
        vm.expectRevert(Governable.Forbidden.selector);
        rewardFarm.setRewardCap(9_000_000e18);

        uint128 rewardCap = rewardFarm.rewardCap();
        assertEqUint(rewardCap, 10_000_000e18);
        vm.expectEmit(false, false, false, true);
        emit RewardCapChanged(9_000_000e18);
        rewardFarm.setRewardCap(9_000_000e18);
        rewardCap = rewardFarm.rewardCap();
        assertEqUint(rewardCap, 9_000_000e18);
    }

    /// ====== Test cases for the onChangeReferralToken function ======

    function test_onChangeReferralToken_RevertIf_TheCallerIsNotReferral() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidCaller.selector, address(0)));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);
    }

    function test_onChangeReferralToken_OldReferralTokenIsEqualToZero() public {
        bool alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertFalse(alreadyBoundReferralToken);
        (uint256 referralToken, uint256 referralParentToken) = efc.referrerTokens(OWNER);
        assertEqUint(referralToken, 0);
        assertEqUint(referralParentToken, 0);

        vm.warp(100);
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);
        alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertTrue(alreadyBoundReferralToken);
        (referralToken, referralParentToken) = efc.referrerTokens(OWNER);
        assertEqUint(referralToken, 10000);
        assertEqUint(referralParentToken, 1000);
    }

    function test_onChangeReferralToken_OldReferralTokenIsNotEqualToZero() public {
        vm.warp(100);
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);
        bool alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertTrue(alreadyBoundReferralToken);
        (uint256 referralToken, uint256 referralParentToken) = efc.referrerTokens(OWNER);
        assertEqUint(referralToken, 10000);
        assertEqUint(referralParentToken, 1000);

        vm.prank(OWNER);
        efc.bindCode("testCode10100");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 10000, 1000, 10100, 1001);
        alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertTrue(alreadyBoundReferralToken);
        (referralToken, referralParentToken) = efc.referrerTokens(OWNER);
        assertEqUint(referralToken, 10100);
        assertEqUint(referralParentToken, 1001);
    }

    function test_onChangeReferralToken_ChangeTokenAfterAddingLiquidity() public {
        vm.warp(100);
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);
        bool alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertTrue(alreadyBoundReferralToken);
        (uint256 referralToken, uint256 referralParentToken) = efc.referrerTokens(OWNER);
        assertEqUint(referralToken, 10000);
        assertEqUint(referralParentToken, 1000);

        vm.warp(1100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
        vm.stopPrank();

        vm.warp(2100);
        vm.prank(OWNER);
        efc.bindCode("testCode10100");
        vm.prank(address(efc));
        vm.expectEmit(true, false, false, true);
        emit PoolLiquidityRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(_calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6)
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralTokenRewardGrowthIncreased(
            BTCPool,
            Math.mulDiv(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                1000 * 1e6,
                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            ),
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            ),
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                Math.mulDiv(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralParentTokenRewardGrowthIncreased(
            BTCPool,
            Math.mulDiv(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                1000 * 1e6,
                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            ),
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            ),
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                Math.mulDiv(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            10000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            1000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(BTCPool, 10100, 0);
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(BTCPool, 1001, 0);
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(
            BTCPool,
            10000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                        Math.mulDiv(
                            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(
            BTCPool,
            1000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                        Math.mulDiv(
                            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(BTCPool, 10100, 0);
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(BTCPool, 1001, 0);
        rewardFarm.onChangeReferralToken(OWNER, 10000, 1000, 10100, 1001);
        alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertTrue(alreadyBoundReferralToken);
        (referralToken, referralParentToken) = efc.referrerTokens(OWNER);
        assertEqUint(referralToken, 10100);
        assertEqUint(referralParentToken, 1001);
        (Bitmap bitmap, uint256 rewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        assertEqUint(
            rewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        (
            uint128 liquidity,
            uint128 liquidityRewardGrowthX64,
            uint128 referralLiquidity,
            uint128 referralTokenRewardGrowthX64,
            uint128 referralParentTokenRewardGrowthX64,
            uint128 referralPosition,
            uint128 referralTokenPositionRewardGrowthX64,
            uint128 referralParentTokenPositionRewardGrowthX64,
            ,
            ,
            ,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(_calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6)
        );
        assertEqUint(referralLiquidity, 1000 * 1e6);
        assertEqUint(
            referralTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            )
        );
        assertEqUint(referralPosition, _calculatePosition(1000 * 1e18, _toPriceX96(1900)));
        assertEqUint(
            referralTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        assertEqUint(
            referralParentTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        assertEqUint(lastMintTime, 2100);
        uint256 mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(
                1000,
                REWARDS_PER_SECOND,
                LIQUIDITY_RATE + REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE
            )
        );
        uint256 member0RewardDebt = rewardFarm.referralRewards(10000);
        uint256 connector0RewardDebt = rewardFarm.referralRewards(1000);
        uint256 member1RewardDebt = rewardFarm.referralRewards(10100);
        uint256 connector1RewardDebt = rewardFarm.referralRewards(1001);
        assertEqUint(
            member0RewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            connector0RewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(member1RewardDebt, 0);
        assertEqUint(connector1RewardDebt, 0);

        vm.warp(3100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 2000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 2000 * 1e18, _toPriceX96(1800));
        vm.stopPrank();
        member0RewardDebt = rewardFarm.referralRewards(10000);
        connector0RewardDebt = rewardFarm.referralRewards(1000);
        member1RewardDebt = rewardFarm.referralRewards(10100);
        connector1RewardDebt = rewardFarm.referralRewards(1001);
        assertEqUint(
            member0RewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            connector0RewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            member1RewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            connector1RewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
    }

    /// ====== Test cases for the onLiquidityPositionChanged function ======

    function test_onLiquidityPositionChanged_RevertIf_TheCallerIsNotPool() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidCaller.selector, address(0)));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
    }

    function test_onLiquidityPositionChanged_LiquidityIncrease_DoesNotBindToken() public {
        vm.warp(100);
        (Bitmap bitmap, uint256 rewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(uint8(0));
        assertFalse(found);
        assertEqUint(rewardDebt, 0);
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, 0);

        vm.startPrank(address(BTCPool));
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(BTCPool, OWNER, 0);
        rewardFarm.onLiquidityPositionChanged(OWNER, 500 * 1e6);

        (
            uint128 liquidity,
            uint128 liquidityRewardGrowthX64,
            uint128 referralLiquidity,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 rewardPerSecond,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 500 * 1e6);
        assertEqUint(liquidityRewardGrowthX64, 0);
        assertEqUint(referralLiquidity, 0);
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 100);
        (bitmap, rewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        assertEqUint(rewardDebt, 0);
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, 0);

        vm.warp(600);
        vm.expectEmit(true, false, false, true);
        emit PoolLiquidityRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(500, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(_calculateRewardDelta(500, REWARDS_PER_SECOND, LIQUIDITY_RATE), 500 * 1e6)
        );
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(BTCPool, OWNER, _calculateRewardDelta(500, REWARDS_PER_SECOND, LIQUIDITY_RATE));
        rewardFarm.onLiquidityPositionChanged(OWNER, 500 * 1e6);

        (
            liquidity,
            liquidityRewardGrowthX64,
            referralLiquidity,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            rewardPerSecond,
            lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 1000 * 1e6);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(_calculateRewardDelta(500, REWARDS_PER_SECOND, LIQUIDITY_RATE), 500 * 1e6)
        );
        assertEqUint(referralLiquidity, 0);
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 600);
        (bitmap, rewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        assertEqUint(
            rewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(_calculateRewardDelta(500, REWARDS_PER_SECOND, LIQUIDITY_RATE), 500 * 1e6),
                500 * 1e6
            )
        );
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(500, REWARDS_PER_SECOND, LIQUIDITY_RATE));
    }

    function test_onLiquidityPositionChanged_LiquidityIncrease_HasBoundToken() public {
        vm.warp(100);
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        vm.warp(200);
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(BTCPool, OWNER, 0);
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(BTCPool, 10000, 0);
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(BTCPool, 1000, 0);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        (
            uint128 liquidity,
            uint128 liquidityRewardGrowthX64,
            uint128 referralLiquidity,
            uint128 referralTokenRewardGrowthX64,
            uint128 referralParentTokenRewardGrowthX64,
            ,
            ,
            ,
            ,
            ,
            uint128 rewardPerSecond,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(liquidityRewardGrowthX64, 0);
        assertEqUint(referralLiquidity, 1000 * 1e6);
        assertEqUint(referralTokenRewardGrowthX64, 0);
        assertEqUint(referralParentTokenRewardGrowthX64, 0);
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 200);

        (Bitmap bitmap, uint256 liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(liquidityRewardDebt, 0);
        uint256 memberRewardDebt = rewardFarm.referralRewards(10000);
        uint256 connectorRewardDebt = rewardFarm.referralRewards(1000);
        assertEqUint(memberRewardDebt, 0);
        assertEqUint(connectorRewardDebt, 0);
        assertEqUint(mintedReward, 0);

        vm.warp(1200);
        vm.expectEmit(true, false, false, true);
        emit PoolLiquidityRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(_calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6)
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                1000 * 1e6
            ),
            0,
            0
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralParentTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, 4_000_000),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                1000 * 1e6
            ),
            0,
            0
        );
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            10000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            1000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        (
            liquidity,
            liquidityRewardGrowthX64,
            referralLiquidity,
            referralTokenRewardGrowthX64,
            referralParentTokenRewardGrowthX64,
            ,
            ,
            ,
            ,
            ,
            rewardPerSecond,
            lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(_calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6)
        );
        assertEqUint(referralLiquidity, 2000 * 1e6);
        assertEqUint(
            referralTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 1200);
        (bitmap, liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        assertEqUint(
            liquidityRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        memberRewardDebt = rewardFarm.referralRewards(10000);
        connectorRewardDebt = rewardFarm.referralRewards(1000);
        assertEqUint(
            memberRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        assertEqUint(
            connectorRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(
                1000,
                REWARDS_PER_SECOND,
                LIQUIDITY_RATE + REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE
            )
        );
    }

    function test_onLiquidityPositionChanged_LiquidityDecrease_DoesNotBindToken() public {
        vm.warp(100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 500 * 1e6);
        vm.warp(200);
        rewardFarm.onLiquidityPositionChanged(OWNER, 500 * 1e6);
        (Bitmap bitmap, uint256 rewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        assertEqUint(
            rewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1000 * 1e6),
                1000 * 1e6
            )
        );
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE));

        vm.warp(300);
        vm.expectEmit(true, false, false, true);
        emit PoolLiquidityRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 500 * 1e6) +
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1000 * 1e6)
        );
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1000 * 1e6),
                1000 * 1e6
            )
        );
        rewardFarm.onLiquidityPositionChanged(OWNER, -1000 * 1e6);

        (
            uint128 liquidity,
            uint128 liquidityRewardGrowthX64,
            uint128 referralLiquidity,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 rewardPerSecond,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 500 * 1e6) +
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1000 * 1e6)
        );
        assertEqUint(referralLiquidity, 0);
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 300);
        (bitmap, rewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, found) = bitmap.searchNextPosition(uint8(0));
        assertFalse(found);
        assertEqUint(
            rewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1000 * 1e6),
                1000 * 1e6
            ) * 2
        );
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(200, REWARDS_PER_SECOND, LIQUIDITY_RATE));
    }

    function test_onLiquidityPositionChanged_LiquidityDecrease_HasBoundToken() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        vm.startPrank(address(BTCPool));
        vm.warp(100);
        rewardFarm.onLiquidityPositionChanged(OWNER, 500 * 1e6);
        vm.warp(200);
        rewardFarm.onLiquidityPositionChanged(OWNER, 500 * 1e6);

        (Bitmap bitmap, uint256 liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        assertEqUint(
            liquidityRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6),
                1100 * 1e6
            )
        );
        uint256 memberRewardDebt = rewardFarm.referralRewards(10000);
        uint256 connectorRewardDebt = rewardFarm.referralRewards(1000);
        assertEqUint(
            memberRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        assertEqUint(
            connectorRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(
                100,
                REWARDS_PER_SECOND,
                LIQUIDITY_RATE + REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE
            )
        );

        vm.warp(300);
        vm.expectEmit(true, false, false, true);
        emit PoolLiquidityRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            (_calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 550 * 1e6)) +
                (
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                        1100 * 1e6
                    )
                )
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
            (
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    500 * 1e6
                )
            ) +
                (
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6
                    )
                ),
            0,
            0
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralParentTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
            (
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    500 * 1e6
                )
            ) +
                (
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6
                    )
                ),
            0,
            0
        );
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6),
                1100 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            10000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            1000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        rewardFarm.onLiquidityPositionChanged(OWNER, -1000 * 1e6);

        (
            uint128 liquidity,
            uint128 liquidityRewardGrowthX64,
            uint128 referralLiquidity,
            uint128 referralTokenRewardGrowthX64,
            uint128 referralParentTokenRewardGrowthX64,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(
            liquidityRewardGrowthX64,
            (_calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 550 * 1e6)) +
                (
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                        1100 * 1e6
                    )
                )
        );
        assertEqUint(referralLiquidity, 0);
        assertEqUint(
            referralTokenRewardGrowthX64,
            (
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    500 * 1e6
                )
            ) +
                (
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6
                    )
                )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            (
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    500 * 1e6
                )
            ) +
                (
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6
                    )
                )
        );
        assertEqUint(lastMintTime, 300);
        (bitmap, liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, found) = bitmap.searchNextPosition(uint8(0));
        assertFalse(found);
        assertEqUint(
            liquidityRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(_calculateRewardDelta(100, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6),
                1100 * 1e6
            ) * 2
        );
        memberRewardDebt = rewardFarm.referralRewards(10000);
        connectorRewardDebt = rewardFarm.referralRewards(1000);
        assertEqUint(
            memberRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) * 2
        );
        assertEqUint(
            connectorRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) * 2
        );
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(
                200,
                REWARDS_PER_SECOND,
                LIQUIDITY_RATE + REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE
            )
        );
    }

    /// ====== Test cases for the onRiskBufferFundPositionChanged function ======

    function test_onRiskBufferFundPositionChanged_RevertIf_TheCallerIsNotPool() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidCaller.selector, address(0)));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);

        vm.prank(address(BTCPool));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
    }

    function test_onRiskBufferFundPositionChanged_LiquidityIncrease() public {
        vm.startPrank(address(BTCPool));
        vm.warp(1000);
        vm.expectEmit(true, true, false, true);
        emit RiskBufferFundRewardDebtChanged(BTCPool, OWNER, 0);
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);

        vm.warp(2000);
        vm.expectEmit(true, false, false, true);
        emit PoolRiskBufferFundRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit RiskBufferFundRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 riskBufferFundLiquidity,
            uint128 riskBufferFundRewardGrowthX64,
            ,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(riskBufferFundLiquidity, 1000 * 1e6);
        assertEqUint(
            riskBufferFundRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(lastMintTime, 2000);
        uint256 rewardDebt = rewardFarm.riskBufferFundRewards(OWNER);
        assertEqUint(
            rewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE));
    }

    function test_onRiskBufferFundPositionChanged_LiquidityDecrease() public {
        vm.startPrank(address(BTCPool));
        vm.warp(1000);
        vm.expectEmit(true, true, false, true);
        emit RiskBufferFundRewardDebtChanged(BTCPool, OWNER, 0);
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 2000 * 1e6);

        vm.warp(2000);
        vm.expectEmit(true, false, false, true);
        emit PoolRiskBufferFundRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                2000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit RiskBufferFundRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    2000 * 1e6
                ),
                2000 * 1e6
            )
        );
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 riskBufferFundLiquidity,
            uint128 riskBufferFundRewardGrowthX64,
            ,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(riskBufferFundLiquidity, 1000 * 1e6);
        assertEqUint(
            riskBufferFundRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                2000 * 1e6
            )
        );
        assertEqUint(lastMintTime, 2000);
        uint256 rewardDebt = rewardFarm.riskBufferFundRewards(OWNER);
        assertEqUint(
            rewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    2000 * 1e6
                ),
                2000 * 1e6
            )
        );
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE));

        vm.warp(2500);
        vm.expectEmit(true, false, false, true);
        emit PoolRiskBufferFundRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(500, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                2000 * 1e6
            ) +
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(500, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                )
        );
        vm.expectEmit(true, true, false, true);
        emit RiskBufferFundRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(500, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 0);
        (, , , , , , , , riskBufferFundLiquidity, riskBufferFundRewardGrowthX64, , lastMintTime) = rewardFarm
            .poolRewards(BTCPool);
        assertEqUint(riskBufferFundLiquidity, 0);
        assertEqUint(
            riskBufferFundRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                2000 * 1e6
            ) +
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(500, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                )
        );
        assertEqUint(lastMintTime, 2500);
        rewardDebt = rewardFarm.riskBufferFundRewards(OWNER);
        assertEqUint(
            rewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    2000 * 1e6
                ),
                2000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(500, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                        1000 * 1e6
                    ),
                    1000 * 1e6
                )
        );
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(1500, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE));
    }

    /// ====== Test cases for the onPositionChanged function ======

    function test_onPositionChanged_RevertIf_TheCallerIsNotPool() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidCaller.selector, address(0)));
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
    }

    function test_onPositionChanged_DoesNotBindToken() public {
        vm.warp(100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
        Bitmap bitmap = rewardFarm.positions(OWNER);
        (, bool found) = bitmap.searchNextPosition(0);
        assertTrue(found);

        vm.warp(200);
        vm.startPrank(address(BTCPool));
        rewardFarm.onPositionChanged(OWNER, LONG, 2000 * 1e18, _toPriceX96(1800));
        bitmap = rewardFarm.positions(OWNER);
        (, found) = bitmap.searchNextPosition(0);
        assertTrue(found);
    }

    function test_onPositionChanged_HasBoundToken() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        vm.warp(100);
        vm.prank(address(BTCPool));
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(BTCPool, 10000, 0);
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(BTCPool, 1000, 0);
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
        Bitmap bitmap = rewardFarm.positions(OWNER);
        (, bool found) = bitmap.searchNextPosition(0);
        assertTrue(found);
        (
            ,
            ,
            ,
            ,
            ,
            uint128 referralPosition,
            uint128 referralTokenPositionRewardGrowthX64,
            uint128 referralParentTokenPositionRewardGrowthX64,
            ,
            ,
            uint128 rewardPerSecond,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(referralPosition, _calculatePosition(1000 * 1e18, _toPriceX96(1900)));
        assertEqUint(referralTokenPositionRewardGrowthX64, 0);
        assertEqUint(referralParentTokenPositionRewardGrowthX64, 0);
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 100);
        uint256 memberRewardDebt = rewardFarm.referralRewards(10000);
        uint256 connectorRewardDebt = rewardFarm.referralRewards(1000);
        assertEqUint(memberRewardDebt, 0);
        assertEqUint(connectorRewardDebt, 0);
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, 0);

        vm.warp(200);
        vm.startPrank(address(BTCPool));
        vm.expectEmit(true, false, false, true);
        emit PoolReferralTokenRewardGrowthIncreased(
            BTCPool,
            0,
            0,
            _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralParentTokenRewardGrowthIncreased(
            BTCPool,
            0,
            0,
            _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(
            BTCPool,
            10000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(
            BTCPool,
            1000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        rewardFarm.onPositionChanged(OWNER, LONG, 2000 * 1e18, _toPriceX96(1800));
        bitmap = rewardFarm.positions(OWNER);
        (, found) = bitmap.searchNextPosition(0);
        assertTrue(found);
        (
            ,
            ,
            ,
            ,
            ,
            referralPosition,
            referralTokenPositionRewardGrowthX64,
            referralParentTokenPositionRewardGrowthX64,
            ,
            ,
            rewardPerSecond,
            lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(referralPosition, _calculatePosition(2000 * 1e18, _toPriceX96(1800)));
        assertEqUint(
            referralTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        assertEqUint(
            referralParentTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        assertEqUint(rewardPerSecond, REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 200);
        memberRewardDebt = rewardFarm.referralRewards(10000);
        connectorRewardDebt = rewardFarm.referralRewards(1000);
        assertEqUint(
            memberRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    _calculatePosition(2000 * 1e18, _toPriceX96(1800))
                ),
                _calculatePosition(2000 * 1e18, _toPriceX96(1800))
            )
        );
        assertEqUint(
            connectorRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    _calculatePosition(2000 * 1e18, _toPriceX96(1800))
                ),
                _calculatePosition(2000 * 1e18, _toPriceX96(1800))
            )
        );
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(100, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE)
        );
    }

    /// ====== Test cases for the collectLiquidityRewardBatch function ======

    function test_collectLiquidityRewardBatch_RevertIf_TheCallerIsNotRouter() public {
        vm.prank(address(0));
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidCaller.selector, address(0)));
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
    }

    function test_collectLiquidityRewardBatch_UserLiquidityIsZero() public {
        vm.prank(address(router));
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        vm.expectEmit();
        emit LiquidityRewardDebtChanged(BTCPool, OWNER, 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), RECEIVER, 0);
        vm.expectEmit(false, true, true, true);
        emit LiquidityRewardCollected(pools, OWNER, RECEIVER, 0);
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
    }

    function test_collectLiquidityRewardBatch_DoesNotBindToken() public {
        vm.warp(100);
        vm.prank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);

        vm.warp(1100);
        vm.prank(address(router));
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE)
        );
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(false, true, true, true);
        emit LiquidityRewardCollected(
            pools,
            OWNER,
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );

        uint256 rewardDebtBefore = rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        assertEqUint(
            rewardDebtBefore,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        (Bitmap bitmap, uint256 rewardDebtAfter) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(0);
        assertTrue(found);
        assertEqUint(rewardDebtAfter, 0);
        assertEq(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        (uint128 liquidity, uint128 liquidityRewardGrowthX64, , , , , , , , , , uint128 lastMintTime) = rewardFarm
            .poolRewards(BTCPool);
        assertEqUint(liquidity, 1000 * 1e6);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(_calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1000 * 1e6)
        );
        assertEqUint(lastMintTime, 1100);
        uint128 minedReward = rewardFarm.mintedReward();
        assertEqUint(minedReward, _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE));
    }

    function test_collectLiquidityRewardBatch_HasBoundToken() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);
        bool alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertTrue(alreadyBoundReferralToken);

        vm.warp(100);
        vm.prank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);

        vm.warp(1100);
        vm.prank(address(router));
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;

        vm.expectEmit(true, false, false, true);
        emit PoolLiquidityRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(_calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6)
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                1000 * 1e6
            ),
            0,
            0
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralParentTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                1000 * 1e6
            ),
            0,
            0
        );
        vm.expectEmit(true, true, false, true);
        emit LiquidityRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        vm.expectEmit(false, true, true, true);
        emit LiquidityRewardCollected(
            pools,
            OWNER,
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );

        uint256 rewardDebtBefore = rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        assertEqUint(
            rewardDebtBefore,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        (Bitmap bitmap, uint256 rewardDebtAfter) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(0);
        assertTrue(found);
        assertEqUint(rewardDebtAfter, 0);
        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        (
            uint128 liquidity,
            ,
            uint128 referralLiquidity,
            uint128 referralTokenRewardGrowthX64,
            uint128 referralParentTokenRewardGrowthX64,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(referralLiquidity, 1000 * 1e6);
        assertEqUint(
            referralTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(lastMintTime, 1100);
        uint128 minedReward = rewardFarm.mintedReward();
        assertEqUint(
            minedReward,
            _calculateRewardDelta(
                1000,
                REWARDS_PER_SECOND,
                LIQUIDITY_RATE + REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE
            )
        );
    }

    /// ====== Test cases for the collectRiskBufferFundRewardBatfch function ======

    function test_collectRiskBufferFundRewardBatch_RevertIf_TheCallerIsNotRouter() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidCaller.selector, address(0)));
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, RECEIVER);
    }

    function test_collectRiskBufferFundRewardBatch() public {
        vm.warp(100);
        vm.prank(address(BTCPool));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);

        vm.warp(1100);
        vm.prank(address(router));
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        vm.expectEmit(true, false, false, true);
        emit PoolRiskBufferFundRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit RiskBufferFundRewardDebtChanged(
            BTCPool,
            OWNER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(false, true, true, true);
        emit RiskBufferFundRewardCollected(
            pools,
            OWNER,
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );

        uint256 rewardDebtBefore = rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, RECEIVER);
        assertEqUint(
            rewardDebtBefore,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        uint256 rewardDebtAfter = rewardFarm.riskBufferFundRewards(OWNER);
        assertEqUint(rewardDebtAfter, 0);
        (
            uint128 liquidity,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 riskBufferFundLiquidity,
            uint128 riskBufferFundRewardGrowthX64,
            ,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(riskBufferFundLiquidity, 1000 * 1e6);
        assertEqUint(
            riskBufferFundRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(lastMintTime, 1100);
        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        uint256 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE));
    }

    /// ====== Test cases for the collectReferralRewardBatch function ======

    function test_collectReferralRewardBatch_RevertIf_TheCallerIsNotRouter() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IRewardFarm.InvalidCaller.selector, address(0)));

        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = 1000;
        tokens[1] = 10000;
        rewardFarm.collectReferralRewardBatch(pools, tokens, RECEIVER);
    }

    function test_collectReferralRewardBatch_MemberAndConnector() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        vm.warp(100);
        vm.prank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);

        vm.warp(1100);

        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = 10000;
        tokens[1] = 1000;

        vm.expectEmit(true, false, false, true);
        emit PoolLiquidityRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
            _calculatePerShareGrowthX64(_calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE), 1100 * 1e6)
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                1000 * 1e6
            ),
            0,
            0
        );
        vm.expectEmit(true, false, false, true);
        emit PoolReferralParentTokenRewardGrowthIncreased(
            BTCPool,
            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                1000 * 1e6
            ),
            0,
            0
        );

        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            10000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(BTCPool, 10000, 0);
        vm.expectEmit(true, true, false, true);
        emit ReferralLiquidityRewardDebtChanged(
            BTCPool,
            1000,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(true, true, false, true);
        emit ReferralPositionRewardDebtChanged(BTCPool, 1000, 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(0),
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.expectEmit(false, false, false, true);
        emit ReferralRewardCollected(
            pools,
            tokens,
            RECEIVER,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        vm.prank(address(router));
        uint256 rewardDebtBefore = rewardFarm.collectReferralRewardBatch(pools, tokens, RECEIVER);
        assertEqUint(
            rewardDebtBefore,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        uint256 memberRewardDebt = rewardFarm.referralRewards(10000);
        uint256 connectorRewardDebt = rewardFarm.referralRewards(1000);
        assertEqUint(memberRewardDebt, 0);
        assertEqUint(connectorRewardDebt, 0);
        uint256 rewardDebtAfter = memberRewardDebt + connectorRewardDebt;
        assertEqUint(rewardDebtAfter, 0);

        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        (
            uint128 liquidity,
            ,
            uint128 referralLiquidity,
            uint128 referralTokenRewardGrowthX64,
            uint128 referralParentTokenRewardGrowthX64,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(referralLiquidity, 1000 * 1e6);
        assertEqUint(
            referralTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(lastMintTime, 1100);
        uint256 mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(
                1000,
                REWARDS_PER_SECOND,
                LIQUIDITY_RATE + REFERRAL_TOKEN_RATE + REFERRAL_PARENT_TOKEN_RATE
            )
        );
    }

    /// ====== Test cases for collectRewardBatch ======

    function test_collectRewardBatch_OnePool() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);
        bool alreadyBoundReferralToken = rewardFarm.alreadyBoundReferralTokens(OWNER);
        assertTrue(alreadyBoundReferralToken);

        vm.warp(100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        vm.stopPrank();

        vm.warp(1100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 0);
        vm.stopPrank();

        (Bitmap bitmap, uint256 liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(uint8(0));
        uint256 memberRewardDebt = rewardFarm.referralRewards(10000);
        uint256 connectorRewardDebt = rewardFarm.referralRewards(1000);
        uint256 riskBufferFundRewardDebt = rewardFarm.riskBufferFundRewards(OWNER);
        assertTrue(found);
        assertEqUint(
            liquidityRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        assertEqUint(
            memberRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            connectorRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            riskBufferFundRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        IPool[] memory pools = new IPool[](1);
        pools[0] = BTCPool;
        uint256[] memory members = new uint256[](1);
        members[0] = 10000;
        uint256[] memory connectors = new uint256[](1);
        connectors[0] = 1000;
        vm.startPrank(address(router));
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        (bitmap, liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, found) = bitmap.searchNextPosition(uint8(0));
        memberRewardDebt = rewardFarm.referralRewards(10000);
        connectorRewardDebt = rewardFarm.referralRewards(1000);
        riskBufferFundRewardDebt = rewardFarm.riskBufferFundRewards(OWNER);
        assertTrue(found);
        assertEqUint(liquidityRewardDebt, 0);
        assertEqUint(memberRewardDebt, 0);
        assertEqUint(connectorRewardDebt, 0);
        assertEqUint(riskBufferFundRewardDebt, 0);
        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            )
        );
        assertEqUint(
            equ.balanceOf(MEMBER_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(CONNECTOR_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(OTHER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(1000, REWARDS_PER_SECOND, Constants.BASIS_POINTS_DIVISOR));
    }

    function test_collectRewardBatch_MultiplePools() public {
        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        IPool[] memory pools = new IPool[](2);
        uint128[] memory rewardsPerSeconds = new uint128[](2);
        pools[0] = BTCPool;
        pools[1] = ETHPool;
        rewardsPerSeconds[0] = REWARDS_PER_SECOND;
        rewardsPerSeconds[1] = REWARDS_PER_SECOND;
        rewardFarm.setPoolsReward(pools, rewardsPerSeconds);

        vm.warp(100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        vm.stopPrank();
        vm.startPrank(address(ETHPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 2000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 2000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 2000 * 1e6);
        vm.stopPrank();

        vm.warp(1100);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 0);
        vm.stopPrank();
        vm.warp(1100);
        vm.startPrank(address(ETHPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 2000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, LONG, 2000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 0);
        vm.stopPrank();

        (Bitmap bitmap, uint256 liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        (, bool found) = bitmap.searchNextPosition(uint8(0));
        assertTrue(found);
        (, found) = bitmap.searchNextPosition(uint8(1));
        assertTrue(found);
        assertEqUint(
            liquidityRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                        2200 * 1e6
                    ),
                    2200 * 1e6
                )
        );
        uint256 memberRewardDebt = rewardFarm.referralRewards(10000);
        uint256 connectorRewardDebt = rewardFarm.referralRewards(1000);
        uint256 riskBufferFundRewardDebt = rewardFarm.riskBufferFundRewards(OWNER);
        assertEqUint(
            memberRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                            2000 * 1e6,
                            2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                        ),
                        2000 * 1e6
                    ),
                    2000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                2000 * 1e6,
                                2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            connectorRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                            2000 * 1e6,
                            2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                        ),
                        2000 * 1e6
                    ),
                    2000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                2000 * 1e6,
                                2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            riskBufferFundRewardDebt,
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                        2000 * 1e6
                    ),
                    2000 * 1e6
                )
        );

        uint256[] memory members = new uint256[](1);
        members[0] = 10000;
        uint256[] memory connectors = new uint256[](1);
        connectors[0] = 1000;
        vm.startPrank(address(router));
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        (bitmap, liquidityRewardDebt) = rewardFarm.liquidityRewards(OWNER);
        memberRewardDebt = rewardFarm.referralRewards(10000);
        connectorRewardDebt = rewardFarm.referralRewards(1000);
        riskBufferFundRewardDebt = rewardFarm.riskBufferFundRewards(OWNER);
        assertEqUint(liquidityRewardDebt, 0);
        assertEqUint(memberRewardDebt, 0);
        assertEqUint(connectorRewardDebt, 0);
        assertEqUint(riskBufferFundRewardDebt, 0);
        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    1100 * 1e6
                ),
                1100 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE),
                        2200 * 1e6
                    ),
                    2200 * 1e6
                )
        );
        assertEqUint(
            equ.balanceOf(MEMBER_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                            2000 * 1e6,
                            2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                        ),
                        2000 * 1e6
                    ),
                    2000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                2000 * 1e6,
                                2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(CONNECTOR_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        Math.mulDiv(
                            _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                            2000 * 1e6,
                            2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                        ),
                        2000 * 1e6
                    ),
                    2000 * 1e6
                ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1000, REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                2000 * 1e6,
                                2000 * 1e6 + _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(2000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(OTHER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    2000 * 1e6
                ),
                2000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1000, REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                        2000 * 1e6
                    ),
                    2000 * 1e6
                )
        );
        uint128 mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, _calculateRewardDelta(1000, REWARDS_PER_SECOND, Constants.BASIS_POINTS_DIVISOR) * 2);
    }

    /// ====== Test cases for rewardCap ======

    function test_RewardCap_ModifyToTheCorrectRewardIfExceedingCap() public {
        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](1);
        pools[0] = BTCPool;
        rewardsPerSeconds[0] = CHANGED_REWARDS_PER_SECOND;
        rewardFarm.setPoolsReward(pools, rewardsPerSeconds);

        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);

        vm.warp(1);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, SHORT, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        vm.stopPrank();

        vm.warp(100_000_000);
        vm.startPrank(address(router));
        uint256[] memory members = new uint256[](1);
        members[0] = 10000;
        uint256[] memory connectors = new uint256[](1);
        connectors[0] = 1000;
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        assertEqUint(
            equ.balanceOf(RECEIVER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                ),
                _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
            )
        );
        assertEqUint(
            equ.balanceOf(MEMBER_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(CONNECTOR_OWNER0),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(
                                    99_999_999,
                                    CHANGED_REWARDS_PER_SECOND,
                                    REFERRAL_PARENT_TOKEN_RATE
                                ),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(OTHER),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                    1000 * 1e6
                ),
                1000 * 1e6
            )
        );
        (, , , , , , , , , , , uint128 lastMintTime) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(lastMintTime, 100_000_000);
        uint256 mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, Constants.BASIS_POINTS_DIVISOR)
        );

        vm.warp(110_000_000);
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, address(15));
        rewardFarm.collectReferralRewardBatch(pools, members, address(16));
        rewardFarm.collectReferralRewardBatch(pools, connectors, address(17));
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, address(18));
        assertEqUint(
            equ.balanceOf(address(15)),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, LIQUIDITY_RATE),
                    _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
                ),
                _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
            )
        );
        assertEqUint(
            equ.balanceOf(address(16)),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(address(17)),
            _calculateRewardDebt(
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                ),
                1000 * 1e6
            ) +
                _calculateRewardDebt(
                    _calculatePerShareGrowthX64(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                            Math.mulDiv(
                                _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                                1000 * 1e6,
                                1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                            ),
                        _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            equ.balanceOf(address(18)),
            ((10_000_000e18 -
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, Constants.BASIS_POINTS_DIVISOR)) * 4) / 25
        );
        (, , , , , , , , , , , lastMintTime) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(lastMintTime, 110_000_000);
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, 10_000_000 * 1e18);

        vm.warp(120_000_000);
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, address(19));
        rewardFarm.collectReferralRewardBatch(pools, members, address(20));
        rewardFarm.collectReferralRewardBatch(pools, connectors, address(21));
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, address(22));
        assertEqUint(equ.balanceOf(address(19)), 0);
        assertEqUint(equ.balanceOf(address(20)), 0);
        assertEqUint(equ.balanceOf(address(21)), 0);
        assertEqUint(equ.balanceOf(address(22)), 0);
        (, , , , , , , , , , , lastMintTime) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(lastMintTime, 110_000_000);
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, 10_000_000 * 1e18);
    }

    function test_RewardCap_StopUpdatingRewardGrowthX64IfCapIsExceeded() public {
        IPool[] memory pools = new IPool[](1);
        uint128[] memory rewardsPerSeconds = new uint128[](1);
        pools[0] = BTCPool;
        rewardsPerSeconds[0] = CHANGED_REWARDS_PER_SECOND;
        rewardFarm.setPoolsReward(pools, rewardsPerSeconds);

        vm.prank(OWNER);
        efc.bindCode("testCode10000");
        vm.prank(address(efc));
        rewardFarm.onChangeReferralToken(OWNER, 0, 0, 10000, 1000);

        vm.warp(1);
        vm.startPrank(address(BTCPool));
        rewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        rewardFarm.onPositionChanged(OWNER, SHORT, 1000 * 1e18, _toPriceX96(1900));
        rewardFarm.onRiskBufferFundPositionChanged(OWNER, 1000 * 1e6);
        vm.stopPrank();

        vm.warp(100_000_000);
        vm.startPrank(address(router));
        uint256[] memory members = new uint256[](1);
        members[0] = 10000;
        uint256[] memory connectors = new uint256[](1);
        connectors[0] = 1000;
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        rewardFarm.collectReferralRewardBatch(pools, members, MEMBER_OWNER0);
        rewardFarm.collectReferralRewardBatch(pools, connectors, CONNECTOR_OWNER0);
        rewardFarm.collectRiskBufferFundRewardBatch(pools, OWNER, OTHER);
        (
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
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, LIQUIDITY_RATE),
                _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
            )
        );
        assertEqUint(referralLiquidity, 1000 * 1e6);
        assertEqUint(
            referralTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            )
        );
        assertEqUint(referralPosition, _calculatePosition(1000 * 1e18, _toPriceX96(1900)));
        assertEqUint(
            referralTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        assertEqUint(
            referralParentTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            )
        );
        assertEqUint(riskBufferFundLiquidity, 1000 * 1e6);
        assertEqUint(
            riskBufferFundRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(rewardPerSecond, CHANGED_REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 100_000_000);
        uint256 mintedReward = rewardFarm.mintedReward();
        assertEqUint(
            mintedReward,
            _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, Constants.BASIS_POINTS_DIVISOR)
        );

        vm.warp(100_000_001);
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        (
            liquidity,
            liquidityRewardGrowthX64,
            referralLiquidity,
            referralTokenRewardGrowthX64,
            referralParentTokenRewardGrowthX64,
            referralPosition,
            referralTokenPositionRewardGrowthX64,
            referralParentTokenPositionRewardGrowthX64,
            riskBufferFundLiquidity,
            riskBufferFundRewardGrowthX64,
            rewardPerSecond,
            lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100_000_000, CHANGED_REWARDS_PER_SECOND, LIQUIDITY_RATE),
                _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
            )
        );
        assertEqUint(referralLiquidity, 1000 * 1e6);
        assertEqUint(
            referralTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            ) +
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            ) +
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                )
        );
        assertEqUint(referralPosition, _calculatePosition(1000 * 1e18, _toPriceX96(1900)));
        assertEqUint(
            referralTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            ) +
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                        Math.mulDiv(
                            _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            referralParentTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            ) +
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                        Math.mulDiv(
                            _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(riskBufferFundLiquidity, 1000 * 1e6);
        assertEqUint(
            riskBufferFundRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100_000_000, CHANGED_REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(rewardPerSecond, CHANGED_REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 100_000_001);
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, 10_000_000 * 1e18);

        vm.warp(100_000_002);
        rewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        (
            liquidity,
            liquidityRewardGrowthX64,
            referralLiquidity,
            referralTokenRewardGrowthX64,
            referralParentTokenRewardGrowthX64,
            referralPosition,
            referralTokenPositionRewardGrowthX64,
            referralParentTokenPositionRewardGrowthX64,
            riskBufferFundLiquidity,
            riskBufferFundRewardGrowthX64,
            rewardPerSecond,
            lastMintTime
        ) = rewardFarm.poolRewards(BTCPool);
        assertEqUint(liquidity, 0);
        assertEqUint(
            liquidityRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100_000_000, CHANGED_REWARDS_PER_SECOND, LIQUIDITY_RATE),
                _calculateReferralLiquidityWithMultiplier(1000 * 1e6, REFERRAL_MULTIPLIER)
            )
        );
        assertEqUint(referralLiquidity, 1000 * 1e6);
        assertEqUint(
            referralTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            ) +
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                )
        );
        assertEqUint(
            referralParentTokenRewardGrowthX64,
            _calculatePerShareGrowthX64(
                Math.mulDiv(
                    _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                    1000 * 1e6,
                    1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                ),
                1000 * 1e6
            ) +
                _calculatePerShareGrowthX64(
                    Math.mulDiv(
                        _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                    1000 * 1e6
                )
        );
        assertEqUint(referralPosition, _calculatePosition(1000 * 1e18, _toPriceX96(1900)));
        assertEqUint(
            referralTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            ) +
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE) -
                        Math.mulDiv(
                            _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(
            referralParentTokenPositionRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                    Math.mulDiv(
                        _calculateRewardDelta(99_999_999, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                        1000 * 1e6,
                        1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                    ),
                _calculatePosition(1000 * 1e18, _toPriceX96(1900))
            ) +
                _calculatePerShareGrowthX64(
                    _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE) -
                        Math.mulDiv(
                            _calculateRewardDelta(1, CHANGED_REWARDS_PER_SECOND, REFERRAL_PARENT_TOKEN_RATE),
                            1000 * 1e6,
                            1000 * 1e6 + _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                        ),
                    _calculatePosition(1000 * 1e18, _toPriceX96(1900))
                )
        );
        assertEqUint(riskBufferFundLiquidity, 1000 * 1e6);
        assertEqUint(
            riskBufferFundRewardGrowthX64,
            _calculatePerShareGrowthX64(
                _calculateRewardDelta(100_000_000, CHANGED_REWARDS_PER_SECOND, RISK_BUFFERFUND_LIQUIDITY_RATE),
                1000 * 1e6
            )
        );
        assertEqUint(rewardPerSecond, CHANGED_REWARDS_PER_SECOND);
        assertEqUint(lastMintTime, 100_000_001);
        mintedReward = rewardFarm.mintedReward();
        assertEqUint(mintedReward, 10_000_000 * 1e18);
    }

    /// ====== Test case for Bitmap ======

    function test_Bitmap_RevertIf_TheNumberOfPoolsExceeds256() public {
        IPool[] memory pools = new IPool[](256);

        uint128[] memory rewardsPerSeconds = new uint128[](256);
        for (uint256 i; i <= type(uint8).max; i++) {
            IERC20 token = new ERC20("TEST TOKEN", "TTOKEN");
            poolFactory.enableToken(token, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
            pools[i] = poolFactory.createPool(token);
            rewardsPerSeconds[i] = REWARDS_PER_SECOND;
        }
        vm.expectRevert(IRewardFarm.TooManyPools.selector);
        rewardFarm.setPoolsReward(pools, rewardsPerSeconds);
    }

    function test_Bitmap_IfSomePoolsRewardsPerSecondIsEqualZero() public {
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);
        equ.setMinter(address(otherRewardFarm), true);
        IRewardFarm.Config memory rightConfig = IRewardFarm.Config(
            LIQUIDITY_RATE,
            RISK_BUFFERFUND_LIQUIDITY_RATE,
            REFERRAL_TOKEN_RATE,
            REFERRAL_PARENT_TOKEN_RATE
        );
        otherRewardFarm.setConfig(rightConfig);

        vm.warp(100);
        IPool[] memory pools = new IPool[](256);
        uint128[] memory rewardsPerSeconds = new uint128[](256);
        for (uint256 i; i <= type(uint8).max; i++) {
            IERC20 token = new ERC20("TEST TOKEN", "TTOKEN");
            poolFactory.enableToken(token, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
            pools[i] = poolFactory.createPool(token);
            rewardsPerSeconds[i] = REWARDS_PER_SECOND;
            if (i >= 200) {
                rewardsPerSeconds[i] = 0;
            }
            vm.prank(address(pools[i]));
            otherRewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
        }
        otherRewardFarm.setPoolsReward(pools, rewardsPerSeconds);

        vm.warp(1100);
        vm.prank(address(router));
        otherRewardFarm.collectLiquidityRewardBatch(pools, OWNER, RECEIVER);
        assertEqUint(equ.balanceOf(RECEIVER), _calculateRewardDelta(1000, REWARDS_PER_SECOND, LIQUIDITY_RATE) * 200);
    }

    function test_Bitmap_ExceedTheSizeOfTheBitmap() public {
        otherRewardFarm = new RewardFarm(poolFactory, router, efc, equ, 1, REFERRAL_MULTIPLIER);
        equ.setMinter(address(otherRewardFarm), true);
        IRewardFarm.Config memory rightConfig = IRewardFarm.Config(
            LIQUIDITY_RATE,
            RISK_BUFFERFUND_LIQUIDITY_RATE,
            REFERRAL_TOKEN_RATE,
            REFERRAL_PARENT_TOKEN_RATE
        );
        otherRewardFarm.setConfig(rightConfig);

        vm.warp(100);
        for (uint256 i; i <= 256; i++) {
            IERC20 token = new ERC20("TEST TOKEN", "TTOKEN");
            poolFactory.enableToken(token, tokenConfig, tokenFeeRateConfig, tokenPriceConfig);
            pool = poolFactory.createPool(token);
            vm.prank(address(pool));
            otherRewardFarm.onLiquidityPositionChanged(OWNER, 1000 * 1e6);
            uint256 poolIndex = otherRewardFarm.poolIndexes(pool);
            if (i <= type(uint8).max) {
                assertEq(poolIndex, i | (1 << 8));
            } else {
                assertEq(poolIndex, 0);
            }
        }
    }

    /// ====== calculation tool ======

    function _calculateRewardDelta(
        uint256 _timeDelta,
        uint128 _rewardPerSecond,
        uint32 _rate
    ) private pure returns (uint256 rewardDelta) {
        rewardDelta = Math.mulDiv(_timeDelta * _rewardPerSecond, _rate, Constants.BASIS_POINTS_DIVISOR);
    }

    function _calculateReferralLiquidityWithMultiplier(
        uint128 _referralLiquidity,
        uint32 _referralMultiplier
    ) private pure returns (uint256 referralLiquidityWithMultiplier) {
        referralLiquidityWithMultiplier = Math.mulDivUp(
            _referralLiquidity,
            _referralMultiplier,
            Constants.BASIS_POINTS_DIVISOR
        );
    }

    function _calculatePerShareGrowthX64(
        uint256 _rewardDelta,
        uint256 _totalLiquidity
    ) private pure returns (uint128 perShareGrowthX64) {
        perShareGrowthX64 = Math.mulDiv(_rewardDelta, Constants.Q64, _totalLiquidity).toUint128();
    }

    function _calculateRewardDebt(
        uint256 _globalRewardGrowthX64,
        uint256 _totalLiquidity
    ) private pure returns (uint256 rewardDebt) {
        rewardDebt = Math.mulDiv(_globalRewardGrowthX64, _totalLiquidity, Constants.Q64);
    }

    function _calculatePosition(
        uint128 _sizeAfter,
        uint160 _entryPriceAfterX96
    ) private pure returns (uint128 position) {
        position = Math.mulDiv(_sizeAfter, _entryPriceAfterX96, Constants.Q96).toUint128();
    }

    function _toPriceX96(uint256 _price) private pure returns (uint160) {
        _price = Math.mulDiv(_price, Constants.Q96, 1e12);
        return _price.toUint160();
    }
}
