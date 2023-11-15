// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "./Token.sol";
import "forge-std/Test.sol";
import "../../contracts/plugins/RewardCollectorV3.sol";
import "../../contracts/farming/FarmRewardDistributorV2.sol";
import "../../contracts/test/MockEFC.sol";
import "../../contracts/test/MockPool.sol";
import "../../contracts/test/MockPoolFactory.sol";
import "../../contracts/test/MockFeeDistributor.sol";

contract FarmRewardDistributorV2Test is Test {
    uint256 private constant SIGNER_PRIVATE_KEY = 0x12345;
    uint256 private constant OTHER_PRIVATE_KEY = 0x54321;
    address private constant ACCOUNT1 = address(0x201);
    address private constant ACCOUNT2 = address(0x202);

    MockPool public pool1;
    MockPool public pool2;
    MockPoolFactory public poolFactory;

    PoolIndexer public poolIndexer;

    MockEFC public EFC;
    RewardCollectorV3 public collector;
    PositionFarmRewardDistributor public distributorV1;
    FarmRewardDistributorV2 public distributorV2;
    IERC20 public token;
    MockFeeDistributor public feeDistributor;

    event RewardTypeDescriptionSet(uint16 indexed rewardType, string description);
    event LockupFreeRateSet(uint16 indexed period, uint32 lockupFreeRate);
    event RewardCollected(
        IPool pool,
        address indexed account,
        uint16 indexed rewardType,
        uint16 indexed referralToken,
        uint32 nonce,
        address receiver,
        uint200 amount
    );
    event RewardLockedAndBurned(
        address indexed account,
        uint16 indexed period,
        address indexed receiver,
        uint256 lockedOrUnlockedAmount,
        uint256 burnedAmount
    );

    function setUp() public {
        pool1 = new MockPool(IERC20(address(0)), IERC20(address(0x101)));
        pool2 = new MockPool(IERC20(address(0)), IERC20(address(0x102)));

        poolFactory = new MockPoolFactory();
        poolFactory.createPool(address(pool1));
        poolFactory.createPool(address(pool2));

        poolIndexer = new PoolIndexer(IPoolFactory(address(poolFactory)));
        poolIndexer.assignPoolIndex(IPool(address(pool1)));
        poolIndexer.assignPoolIndex(IPool(address(pool2)));

        address signer = vm.addr(SIGNER_PRIVATE_KEY);
        token = new Token("T18", "T18");

        distributorV1 = new PositionFarmRewardDistributor(signer, token);
        Ownable(address(token)).transferOwnership(address(distributorV1));
        distributorV1.setCollector(address(this), true);

        PositionFarmRewardDistributor.PoolTotalReward[]
            memory poolTotalRewards = new PositionFarmRewardDistributor.PoolTotalReward[](2);
        poolTotalRewards[0] = PositionFarmRewardDistributor.PoolTotalReward(address(pool1), 1000);
        poolTotalRewards[1] = PositionFarmRewardDistributor.PoolTotalReward(address(pool2), 2000);
        distributorV1.collectPositionFarmRewardBatchByCollector(
            ACCOUNT1,
            1,
            poolTotalRewards,
            signV1(SIGNER_PRIVATE_KEY, ACCOUNT1, 1, poolTotalRewards),
            ACCOUNT1
        );

        feeDistributor = new MockFeeDistributor();
        feeDistributor.setToken(token);
        EFC = new MockEFC();
        EFC.setOwner(1, ACCOUNT1);
        EFC.setOwner(1000, ACCOUNT1);
        EFC.setOwner(10000, ACCOUNT1);
        EFC.setOwner(19999, ACCOUNT1);

        distributorV2 = new FarmRewardDistributorV2(
            signer,
            IEFC(address(EFC)),
            distributorV1,
            IFeeDistributor(address(feeDistributor)),
            poolIndexer
        );
        distributorV2.setCollector(address(this), true);
        vm.prank(address(distributorV1));
        Ownable(address(token)).transferOwnership(address(distributorV2));
    }

    function test_setRewardType_RevertIf_caller_is_not_gov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(Governable.Forbidden.selector));
        distributorV2.setRewardType(4, "12345678901234567890123456789012");
    }

    function test_setRewardType_RevertIf_description_too_long() public {
        vm.expectRevert();
        distributorV2.setRewardType(4, "1234567890123456789012345678901234567890123456789012345678901234567890");
    }

    function test_setRewardType() public {
        vm.expectEmit(true, false, false, true);
        emit RewardTypeDescriptionSet(4, "12345678901234567890123456789012");
        distributorV2.setRewardType(4, "12345678901234567890123456789012");
        assertEq(distributorV2.rewardTypesDescriptions(4), "12345678901234567890123456789012");

        vm.expectEmit(true, false, false, true);
        emit RewardTypeDescriptionSet(1, "12345678901234567890123456789012");
        distributorV2.setRewardType(1, "12345678901234567890123456789012");
        assertEq(distributorV2.rewardTypesDescriptions(1), "12345678901234567890123456789012");
    }

    function testFuzz_setRewardType(uint16 rewardType, string memory description) public {
        if (bytes(description).length > 32) {
            vm.expectRevert();
            distributorV2.setRewardType(rewardType, description);
        } else {
            vm.expectEmit(true, false, false, true);
            emit RewardTypeDescriptionSet(rewardType, description);
            distributorV2.setRewardType(rewardType, description);
            assertEq(distributorV2.rewardTypesDescriptions(rewardType), description);
        }
    }

    function test_setLockupFreeRates_RevertIf_caller_is_not_gov() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(Governable.Forbidden.selector));
        FarmRewardDistributorV2.LockupFreeRateParameter[]
            memory parameters = new FarmRewardDistributorV2.LockupFreeRateParameter[](1);
        parameters[0] = FarmRewardDistributorV2.LockupFreeRateParameter(0, 1);
        distributorV2.setLockupFreeRates(parameters);
    }

    function test_setLockupFreeRates_RevertIf_lockup_free_rate_too_large() public {
        vm.expectRevert(abi.encodeWithSelector(FarmRewardDistributorV2.InvalidLockupFreeRate.selector, 100000001));
        FarmRewardDistributorV2.LockupFreeRateParameter[]
            memory parameters = new FarmRewardDistributorV2.LockupFreeRateParameter[](1);
        parameters[0] = FarmRewardDistributorV2.LockupFreeRateParameter(0, 100000001);
        distributorV2.setLockupFreeRates(parameters);
    }

    function test_setLockupFreeRates_RevertIf_period_not_enabled() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidLockupPeriod.selector, 31));
        FarmRewardDistributorV2.LockupFreeRateParameter[]
            memory parameters = new FarmRewardDistributorV2.LockupFreeRateParameter[](1);
        parameters[0] = FarmRewardDistributorV2.LockupFreeRateParameter(31, 100000000);
        distributorV2.setLockupFreeRates(parameters);
    }

    function test_setLockupFreeRates() public {
        vm.expectEmit(true, false, false, true);
        emit LockupFreeRateSet(0, 20_000_000);
        vm.expectEmit(true, false, false, true);
        emit LockupFreeRateSet(30, 30_000_000);
        vm.expectEmit(true, false, false, true);
        emit LockupFreeRateSet(60, 30_000_000);
        vm.expectEmit(true, false, false, true);
        emit LockupFreeRateSet(90, 0);
        FarmRewardDistributorV2.LockupFreeRateParameter[]
            memory parameters = new FarmRewardDistributorV2.LockupFreeRateParameter[](4);
        parameters[0] = FarmRewardDistributorV2.LockupFreeRateParameter(0, 20_000_000);
        parameters[1] = FarmRewardDistributorV2.LockupFreeRateParameter(30, 30_000_000);
        parameters[2] = FarmRewardDistributorV2.LockupFreeRateParameter(60, 30_000_000);
        parameters[3] = FarmRewardDistributorV2.LockupFreeRateParameter(90, 0);
        distributorV2.setLockupFreeRates(parameters);
    }

    function test_collectBatch_RevertIf_caller_is_not_collector() public {
        vm.prank(address(0x1));
        vm.expectRevert(abi.encodeWithSelector(Governable.Forbidden.selector));
        PackedValue[] memory packedValues = new PackedValue[](1);
        packedValues[0] = PackedValue.wrap(0);
        distributorV2.collectBatch(ACCOUNT1, PackedValue.wrap(1), packedValues, bytes(""), ACCOUNT1);
    }

    function test_collectBatch_RevertIf_nonce_is_invalid() public {
        vm.expectRevert(abi.encodeWithSelector(PositionFarmRewardDistributor.InvalidNonce.selector, 1));
        PackedValue[] memory packedValues = new PackedValue[](1);
        packedValues[0] = PackedValue.wrap(0);
        distributorV2.collectBatch(ACCOUNT1, PackedValue.wrap(1), packedValues, bytes(""), ACCOUNT1);
    }

    function test_collectBatch_RevertIf_period_is_invalid() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidLockupPeriod.selector, 31));
        PackedValue[] memory packedValues = new PackedValue[](1);
        packedValues[0] = PackedValue.wrap(0);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(31, 32);
        distributorV2.collectBatch(ACCOUNT2, nonceAndLockupPeriod, packedValues, bytes(""), ACCOUNT2);
    }

    function test_collectBatch_RevertIf_signature_is_invalid() public {
        vm.expectRevert(abi.encodeWithSelector(PositionFarmRewardDistributor.InvalidSignature.selector));
        PackedValue[] memory packedValues = new PackedValue[](1);
        packedValues[0] = PackedValue.wrap(0);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT2,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT2
        );
    }

    function test_collectBatch_RevertIf_pool_is_invalid() public {
        vm.expectRevert(abi.encodeWithSelector(PoolIndexer.InvalidPool.selector, address(0)));
        PackedValue[] memory packedValues = new PackedValue[](1);
        packedValues[0] = PackedValue.wrap(0);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(2, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );
    }

    function test_collectBatch_RevertIf_reward_type_is_invalid() public {
        vm.expectRevert(abi.encodeWithSelector(FarmRewardDistributorV2.InvalidRewardType.selector, type(uint16).max));
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(type(uint16).max, 24);
        packedValues[0] = packedPoolRewardValue;
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(2, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );
    }

    function test_collectBatch_RevertIf_amount_too_small() public {
        vm.expectRevert();
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(999, 56);
        packedValues[0] = packedPoolRewardValue;
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(2, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );
    }

    function test_collectBatch_RevertIf_not_referral_token_owner() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidNFTOwner.selector, ACCOUNT2, 1));
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint216(999, 56);
        packedValues[0] = packedPoolRewardValue;
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT2,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT2, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );
    }

    function test_collectBatch_read_value_once_from_distributor_v1_if_reward_type_is_1() public {
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(2, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT1, 1, 0, 3, ACCOUNT1, 7);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1010, 56);
        packedValues[0] = packedPoolRewardValue;
        nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(3, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );
    }

    function test_collectBatch_read_value_from_distributor_v1_if_reward_type_is_1() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT1, 1, 0, 2, ACCOUNT1, 3);
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(2, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );
    }

    function test_collectBatch_not_read_value_from_distributor_v1_if_reward_type_is_2() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT1, 2, 0, 2, ACCOUNT1, 1003);
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(2, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(2, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );
    }

    function test_collectBatch_multiple_pools() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT1, 1, 0, 2, ACCOUNT1, 3);
        PackedValue[] memory packedValues = new PackedValue[](8);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool2)), ACCOUNT1, 1, 0, 2, ACCOUNT1, 5);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(2, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(2005, 56);
        packedValues[1] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT1, 2, 0, 2, ACCOUNT1, 1003);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(2, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[2] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool2)), ACCOUNT1, 2, 0, 2, ACCOUNT1, 2005);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(2, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(2, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(2005, 56);
        packedValues[3] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT1, 3, 0, 2, ACCOUNT1, 1003);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(3, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[4] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool2)), ACCOUNT1, 3, 0, 2, ACCOUNT1, 2005);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(2, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(3, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(2005, 56);
        packedValues[5] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT1, 3, 1, 2, ACCOUNT1, 1003);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(3, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[6] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool2)), ACCOUNT1, 3, 19999, 2, ACCOUNT1, 2005);
        packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(2, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(3, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(19999, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(2005, 56);
        packedValues[7] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardLockedAndBurned(ACCOUNT1, 30, ACCOUNT1, 4516, 4516);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(2, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT1,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT1, nonceAndLockupPeriod, packedValues),
            ACCOUNT1
        );

        assertEq(1003, distributorV2.collectedRewards(ACCOUNT1, IPool(address(pool1)), 1));
        assertEq(2005, distributorV2.collectedRewards(ACCOUNT1, IPool(address(pool2)), 1));

        assertEq(1003, distributorV2.collectedRewards(ACCOUNT1, IPool(address(pool1)), 2));
        assertEq(2005, distributorV2.collectedRewards(ACCOUNT1, IPool(address(pool2)), 2));

        assertEq(1003, distributorV2.collectedRewards(ACCOUNT1, IPool(address(pool1)), 3));
        assertEq(2005, distributorV2.collectedRewards(ACCOUNT1, IPool(address(pool2)), 3));

        assertEq(1003, distributorV2.collectedReferralRewards(1, IPool(address(pool1)), 3));
        assertEq(0, distributorV2.collectedReferralRewards(1, IPool(address(pool2)), 3));

        assertEq(0, distributorV2.collectedReferralRewards(19999, IPool(address(pool1)), 3));
        assertEq(2005, distributorV2.collectedReferralRewards(19999, IPool(address(pool2)), 3));
    }

    function test_collectBatch_receiver_is_zero_address() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT2, 1, 0, 1, address(this), 1003);
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardLockedAndBurned(ACCOUNT2, 30, address(this), 501, 502);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT2,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT2, nonceAndLockupPeriod, packedValues),
            address(0)
        );
    }

    function test_collectBatch_period_is_0() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT2, 1, 0, 1, address(this), 1003);
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardLockedAndBurned(ACCOUNT2, 0, address(this), 250, 1003 - 250);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(0, 32);
        distributorV2.collectBatch(
            ACCOUNT2,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT2, nonceAndLockupPeriod, packedValues),
            address(0)
        );

        assertEq(250, token.balanceOf(address(this)));
        assertEq(1003 - 250, token.balanceOf(address(0x1)));
    }

    function test_collectBatch_period_is_30() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT2, 1, 0, 1, address(this), 1003);
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardLockedAndBurned(ACCOUNT2, 30, address(this), 501, 502);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(30, 32);
        distributorV2.collectBatch(
            ACCOUNT2,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT2, nonceAndLockupPeriod, packedValues),
            address(0)
        );

        assertEq(501, token.balanceOf(address(feeDistributor)));
        assertEq(502, token.balanceOf(address(0x1)));
    }

    function test_collectBatch_period_is_60() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT2, 1, 0, 1, address(this), 1003);
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardLockedAndBurned(ACCOUNT2, 60, address(this), 752, 1003 - 752);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(60, 32);
        distributorV2.collectBatch(
            ACCOUNT2,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT2, nonceAndLockupPeriod, packedValues),
            address(0)
        );

        assertEq(752, token.balanceOf(address(feeDistributor)));
        assertEq(1003 - 752, token.balanceOf(address(0x1)));
    }

    function test_collectBatch_period_is_90() public {
        vm.expectEmit(true, true, true, true);
        emit RewardCollected(IPool(address(pool1)), ACCOUNT2, 1, 0, 1, address(this), 1003);
        PackedValue[] memory packedValues = new PackedValue[](1);
        PackedValue packedPoolRewardValue = PackedValue.wrap(0);
        packedPoolRewardValue = packedPoolRewardValue.packUint24(1, 0);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(1, 24);
        packedPoolRewardValue = packedPoolRewardValue.packUint16(0, 40);
        packedPoolRewardValue = packedPoolRewardValue.packUint200(1003, 56);
        packedValues[0] = packedPoolRewardValue;

        vm.expectEmit(true, true, true, true);
        emit RewardLockedAndBurned(ACCOUNT2, 90, address(this), 1003, 0);
        PackedValue nonceAndLockupPeriod = PackedValue.wrap(0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint32(1, 0);
        nonceAndLockupPeriod = nonceAndLockupPeriod.packUint16(90, 32);
        distributorV2.collectBatch(
            ACCOUNT2,
            nonceAndLockupPeriod,
            packedValues,
            signV2(SIGNER_PRIVATE_KEY, ACCOUNT2, nonceAndLockupPeriod, packedValues),
            address(0)
        );

        assertEq(1003, token.balanceOf(address(feeDistributor)));
        assertEq(0, token.balanceOf(address(0x1)));
    }

    function signV1(
        uint256 _privateKey,
        address _account,
        uint32 _nonce,
        PositionFarmRewardDistributor.PoolTotalReward[] memory _poolTotalRewards
    ) private pure returns (bytes memory) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encode(_account, _nonce, _poolTotalRewards))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function signV2(
        uint256 _privateKey,
        address _account,
        PackedValue _nonceAndLockupPeriod,
        PackedValue[] memory _packedPoolRewardValues
    ) private pure returns (bytes memory) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encode(_account, _nonceAndLockupPeriod, _packedPoolRewardValues))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
