// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import {SafeCast} from "../../contracts/libraries/SafeCast.sol";
import {SafeERC20} from "../../contracts/libraries/SafeERC20.sol";
import {ReentrancyGuard} from "../../contracts/libraries/ReentrancyGuard.sol";
import {ERC20Test, IERC20} from "../../contracts/test/ERC20Test.sol";
import {MockRewardFarmCallback} from "../../contracts/test/MockRewardFarmCallback.sol";
import {MockFeeDistributorCallback} from "../../contracts/test/MockFeeDistributorCallback.sol";
import {EQU} from "../../contracts/tokens/EQU.sol";
import {IEFC, EFC} from "../../contracts/tokens/EFC.sol";
import {IFeeDistributor, FeeDistributor, IPositionManagerMinimum, IERC721, Constants, Math, Address} from "../../contracts/staking/FeeDistributor.sol";
import {Governable} from "../../contracts/governance/Governable.sol";
import {Router} from "../../contracts/plugins/Router.sol";
import {veEQU} from "../../contracts/tokens/veEQU.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/contracts/libraries/SqrtPriceMath.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";

contract FeeDistributorTest is Test {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using stdStorage for StdStorage;

    // ==================== Constants ====================

    address internal constant ROUTER_ADDRESS = address(1);
    address internal constant MARK = address(2);
    address internal constant ALICE = address(3);
    address internal constant BOB = address(4);
    uint256 internal constant CAP_ARCHITECT = 100;
    uint256 internal constant CAP_CONNECTOR = 100;
    uint256 internal constant CAP_PER_CONNECTOR_CAN_MINT = 100;
    uint16 internal constant WITHDRAWAL_PERIOD = 7;
    uint256 internal constant TOTAL_SUPPLY = 1_000 * 10_000 * 1e18;
    uint8 internal constant DECIMALS = 18;
    string internal constant GOERLI_TESTNET_PUBLIC_URL = "https://eth-goerli.g.alchemy.com/v2/demo";

    // ==================== Uniswap V3 Constants ====================

    address internal constant TOKEN0 = 0x8c9e6c40d3402480ACE624730524fACC5482798c;
    address internal constant TOKEN1 = 0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1;
    address internal constant V3_POOL_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant V3_POS = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // ==================== Contract Addresses ====================

    EFC EFCToken;
    veEQU veEQUToken;
    ERC20Test USDC;
    FeeDistributor feeDistributor;

    // ==================== variables ====================

    uint256 goerliFork;
    uint256[] stakeIDs;
    address[] addresses;
    uint16[] periods = [30, 90, 180];
    uint16[] multipliers = [1, 2, 3];

    event FeeDeposited(
        uint256 amount,
        uint256 equFeeAmount,
        uint256 architectFeeAmount,
        uint160 perShareGrowthAfterX64,
        uint160 architectPerShareGrowthAfterX64
    );
    event Staked(address indexed sender, address indexed account, uint256 stakeID, uint256 amount, uint16 period);
    event LockupRewardMultipliersSet(uint16[] periods, uint16[] multipliers);
    event Unstaked(address indexed owner, address indexed receiver, uint256 id, uint256 amount0, uint256 amount1);
    event V3PosUnstaked(address indexed owner, address indexed receiver, uint256 id, uint256 amount0, uint256 amount1);
    event Collected(address indexed owner, address indexed receiver, uint256 id, uint256 amount);
    event V3PosCollected(address indexed owner, address indexed receiver, uint256 id, uint256 amount);
    event ArchitectCollected(address indexed receiver, uint256 tokenID, uint256 amount);

    error Forbidden();

    function setUp() public {
        // fork goerli testnet
        goerliFork = vm.createFork(GOERLI_TESTNET_PUBLIC_URL);
        vm.selectFork(goerliFork);
        // vm.rollFork(9565569);

        // Initialize EFC token.
        EFCToken = new EFC(
            CAP_ARCHITECT,
            CAP_CONNECTOR,
            CAP_PER_CONNECTOR_CAN_MINT,
            new MockRewardFarmCallback(),
            new MockFeeDistributorCallback()
        );

        // Initialize veEQU token.
        veEQUToken = new veEQU();

        // Initialize USDC token.
        USDC = new ERC20Test("USDC TOKEN", "USDC", DECIMALS, TOTAL_SUPPLY);
        USDC.mint(ALICE, TOTAL_SUPPLY);

        // Initialize FeeDistributor.
        feeDistributor = new FeeDistributor(
            IEFC(address(EFCToken)),
            IERC20(TOKEN0),
            IERC20(TOKEN1),
            IERC20(address(veEQUToken)),
            IERC20(address(USDC)),
            Router(ROUTER_ADDRESS),
            V3_POOL_FACTORY,
            IPositionManagerMinimum(V3_POS),
            WITHDRAWAL_PERIOD
        );
        veEQUToken.setMinter(address(feeDistributor), true);
        feeDistributor.setLockupRewardMultipliers(periods, multipliers);

        // Initialize Balance.
        deal(ALICE, 100 ether);
        deal(TOKEN0, ALICE, TOTAL_SUPPLY);
        deal(TOKEN1, ALICE, TOTAL_SUPPLY);
    }

    function test_SetUpState() public {
        assertEq(USDC.balanceOf(ALICE), TOTAL_SUPPLY);
        assertEq(feeDistributor.lockupRewardMultipliers(30), 1);
        assertEq(feeDistributor.lockupRewardMultipliers(90), 2);
        assertEq(feeDistributor.lockupRewardMultipliers(180), 3);
        assertEq(feeDistributor.withdrawalPeriod(), WITHDRAWAL_PERIOD);
        assertEq(ALICE.balance, 100 * 1e18);
        assertEq(IERC20(TOKEN0).balanceOf(ALICE), TOTAL_SUPPLY);
        assertEq(IERC20(TOKEN1).balanceOf(ALICE), TOTAL_SUPPLY);
    }

    /// ====== Test cases for the setLockupRewardMultipliers function ======

    function test_RevertIf_InputLengthMismatch() public {
        periods.push(360);
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.UnequalLengths.selector));
        feeDistributor.setLockupRewardMultipliers(periods, multipliers);
    }

    function test_RevertIf_CallerNotGovAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Forbidden.selector));
        vm.prank(ALICE);
        feeDistributor.setLockupRewardMultipliers(periods, multipliers);
    }

    function test_SetLockupRewardMultipliers() public {
        vm.expectEmit(true, true, true, true);
        emit LockupRewardMultipliersSet(periods, multipliers);
        feeDistributor.setLockupRewardMultipliers(periods, multipliers);
    }

    /// ====== Test cases for the depositFee function ======

    function test_RevertIf_MintedArchitectsIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.DepositConditionNotMet.selector));
        feeDistributor.depositFee(1e18);
    }

    function test_RevertIf_EQUTotalStakedWithMultiplierIsZero() public {
        _mintArchitect(1);
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.DepositConditionNotMet.selector));
        feeDistributor.depositFee(1e18);
    }

    function test_RevertIf_DepositAmountIsGreaterThanTheTransfer() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, BOB, 30);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(IFeeDistributor.DepositAmountIsGreaterThanTheTransfer.selector, 1e18, 0)
        );
        feeDistributor.depositFee(1e18);
    }

    function testFuzz_DepositFee(uint256 _amount) public {
        vm.assume(_amount <= TOTAL_SUPPLY);

        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, BOB, 30);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        USDC.transfer(address(feeDistributor), _amount);
        vm.stopPrank();
        vm.expectEmit(true, true, true, true);
        emit FeeDeposited(
            _amount,
            _amount >> 1,
            _amount - (_amount >> 1),
            Math.mulDiv(_amount >> 1, Constants.Q64, 1e18 + 999999999999991746).toUint160(),
            Math.mulDiv(_amount - (_amount >> 1), Constants.Q64, 1).toUint160()
        );
        feeDistributor.depositFee(_amount);
    }

    function test_FirstTimeDepositFee() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, BOB, 90);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        feeDistributor.depositFee(10e18);
        vm.stopPrank();
        assertEq(feeDistributor.perShareGrowthX64(), 30744573456182670615);
        assertEq(feeDistributor.architectPerShareGrowthX64(), 92233720368547758080000000000000000000);
    }

    function test_MultipleDepositFee() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, BOB, 90);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        USDC.transfer(address(feeDistributor), 30e18);
        vm.stopPrank();
        // First
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.perShareGrowthX64(), 30744573456182670615);
        assertEq(feeDistributor.architectPerShareGrowthX64(), 92233720368547758080000000000000000000);
        // Second
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.perShareGrowthX64(), 61489146912365341230);
        assertEq(feeDistributor.architectPerShareGrowthX64(), 184467440737095516160000000000000000000);
        // Third
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.perShareGrowthX64(), 92233720368548011845);
        assertEq(feeDistributor.architectPerShareGrowthX64(), 276701161105643274240000000000000000000);
    }

    function test_MultiDepositFeeAndMultipleStake() public {
        // First
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, BOB, 30);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        USDC.transfer(address(feeDistributor), 30e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.perShareGrowthX64(), 46116860184274069364);
        assertEq(feeDistributor.architectPerShareGrowthX64(), 92233720368547758080000000000000000000);
        // Second
        _mintArchitect(2);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, BOB, 90);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.perShareGrowthX64(), 64563604257983681883);
        assertEq(feeDistributor.architectPerShareGrowthX64(), 138350580552821637120000000000000000000);
        // Third
        _mintArchitect(3);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, BOB, 90);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.perShareGrowthX64(), 76092819304052187328);
        assertEq(feeDistributor.architectPerShareGrowthX64(), 169095154009004223146666666666666666666);
    }

    /// ====== Test cases for the stake function ======

    function test_RevertIf_InvalidLockupPeriod() public {
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidLockupPeriod.selector));
        vm.prank(ALICE);
        feeDistributor.stake(1e18, ALICE, 360);
    }

    function testFuzz_Stake(uint256 _amount, uint8 _period) public {
        vm.assume(_amount <= TOTAL_SUPPLY);
        if (_period <= 30) {
            _period = 30;
        } else if (_period <= 90) {
            _period = 90;
        } else {
            _period = 180;
        }

        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), _amount);
        vm.expectEmit(true, true, true, true);
        emit Staked(ALICE, BOB, 1, _amount, _period);
        vm.prank(ALICE);
        uint64 time = block.timestamp.toUint64();
        feeDistributor.stake(_amount, BOB, _period);
        assertEq(veEQUToken.balanceOf(BOB), _amount);
        assertEq(feeDistributor.totalStakedWithMultiplier(), _amount * feeDistributor.lockupRewardMultipliers(_period));
        (
            uint256 amount,
            uint64 lockupStartTime,
            uint16 multiplier,
            uint16 period,
            uint160 perShareGrowthX64
        ) = feeDistributor.stakeInfos(BOB, 1);
        assertEq(amount, _amount);
        assertEq(lockupStartTime, time);
        assertEq(multiplier, feeDistributor.lockupRewardMultipliers(_period));
        assertEq(period, _period);
        assertEq(perShareGrowthX64, 0);
        assertEq(veEQUToken.balanceOf(BOB), _amount);
    }

    function test_SingleUserStake() public {
        _mintArchitect(1);
        // First
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        uint64 time1 = block.timestamp.toUint64();
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 1999999999999991746);
        assertEq(veEQUToken.balanceOf(ALICE), 1999999999999991746);
        // Second
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        vm.prank(ALICE);
        uint64 time2 = block.timestamp.toUint64();
        feeDistributor.stake(1e18, ALICE, 90);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 3999999999999991746);
        assertEq(veEQUToken.balanceOf(ALICE), 2999999999999991746);
        (
            uint256 amount,
            uint64 lockupStartTime,
            uint16 multiplier,
            uint16 period,
            uint160 perShareGrowthX64
        ) = feeDistributor.stakeInfos(ALICE, 1);
        assertEq(amount, 1e18);
        assertEq(lockupStartTime, time1);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 0);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.stakeInfos(ALICE, 2);
        assertEq(amount, 1e18);
        assertEq(lockupStartTime, time2);
        assertEq(multiplier, 2);
        assertEq(period, 90);
        assertEq(perShareGrowthX64, 46116860184274069364);
    }

    function test_MultiUserStake() public {
        _mintArchitect(1);
        // First
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 2e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        uint64 time1 = block.timestamp.toUint64();
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stake(1e18, BOB, 30);
        feeDistributor.stakeV3Pos(tokenId, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 2999999999999991746);
        assertEq(veEQUToken.balanceOf(ALICE), 1999999999999991746);
        assertEq(veEQUToken.balanceOf(BOB), 1e18);
        // Second
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 2e18);
        vm.startPrank(ALICE);
        uint64 time2 = block.timestamp.toUint64();
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stake(1e18, BOB, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 4999999999999991746);
        assertEq(veEQUToken.balanceOf(ALICE), 2999999999999991746);
        assertEq(veEQUToken.balanceOf(BOB), 2e18);
        (
            uint256 amount,
            uint64 lockupStartTime,
            uint16 multiplier,
            uint16 period,
            uint160 perShareGrowthX64
        ) = feeDistributor.stakeInfos(ALICE, 1);
        assertEq(amount, 1e18);
        assertEq(lockupStartTime, time1);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 0);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.stakeInfos(ALICE, 3);
        assertEq(amount, 1e18);
        assertEq(lockupStartTime, time2);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 30744573456182670615);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.stakeInfos(BOB, 2);
        assertEq(amount, 1e18);
        assertEq(lockupStartTime, time1);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 0);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.stakeInfos(BOB, 4);
        assertEq(amount, 1e18);
        assertEq(lockupStartTime, time2);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 30744573456182670615);
    }

    /// ====== Test cases for the stakeV3Pos function ======

    function test_RevertIf_InvalidUniswapV3PositionNFT() public {
        vm.prank(0xb7d9EC4288ED8CC57415d042bbF3695139365634);
        IERC721(V3_POS).transferFrom(0xb7d9EC4288ED8CC57415d042bbF3695139365634, ALICE, 75860);
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidUniswapV3PositionNFT.selector));
        vm.prank(ALICE);
        feeDistributor.stakeV3Pos(75860, ALICE, 30);
    }

    function test_RevertIf_ExchangeableEQUAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.ExchangeableEQUAmountIsZero.selector));
        vm.prank(0x64B5Be6b2919831cD7e1AA9fCB1EAD37d8919eD0);
        feeDistributor.stakeV3Pos(76878, ALICE, 30);
    }

    function test_SingleUserStakeV3Pos() public {
        _mintArchitect(1);
        // First
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId1, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        uint64 time1 = block.timestamp.toUint64();
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId1, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 1999999999999991746);
        assertEq(veEQUToken.balanceOf(ALICE), 1999999999999991746);
        // Second
        (uint256 tokenId2, , , ) = _mintV3PosAndApprove(ALICE);
        vm.prank(ALICE);
        uint64 time2 = block.timestamp.toUint64();
        feeDistributor.stakeV3Pos(tokenId2, ALICE, 90);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 3999999999999975238);
        assertEq(veEQUToken.balanceOf(ALICE), 2999999999999983492);
        (
            uint256 amount,
            uint64 lockupStartTime,
            uint16 multiplier,
            uint16 period,
            uint160 perShareGrowthX64
        ) = feeDistributor.v3PosStakeInfos(ALICE, tokenId1);
        assertEq(amount, 999999999999991746);
        assertEq(lockupStartTime, time1);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 0);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.v3PosStakeInfos(
            ALICE,
            tokenId2
        );
        assertEq(amount, 999999999999991746);
        assertEq(lockupStartTime, time2);
        assertEq(multiplier, 2);
        assertEq(period, 90);
        assertEq(perShareGrowthX64, 46116860184274069364);
    }

    function test_MultiUserStakeV3Pos() public {
        _mintArchitect(1);
        // First
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId1, , , ) = _mintV3PosAndApprove(ALICE);
        (uint256 tokenId2, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        uint64 time1 = block.timestamp.toUint64();
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId1, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId2, BOB, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 2999999999999983492);
        assertEq(veEQUToken.balanceOf(ALICE), 1999999999999991746);
        assertEq(veEQUToken.balanceOf(BOB), 999999999999991746);
        // Second
        (uint256 tokenId3, , , ) = _mintV3PosAndApprove(ALICE);
        (uint256 tokenId4, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        uint64 time2 = block.timestamp.toUint64();
        feeDistributor.stakeV3Pos(tokenId3, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId4, BOB, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        assertEq(feeDistributor.totalStakedWithMultiplier(), 4999999999999966984);
        assertEq(veEQUToken.balanceOf(ALICE), 2999999999999983492);
        assertEq(veEQUToken.balanceOf(BOB), 1999999999999983492);
        (
            uint256 amount,
            uint64 lockupStartTime,
            uint16 multiplier,
            uint16 period,
            uint160 perShareGrowthX64
        ) = feeDistributor.v3PosStakeInfos(ALICE, tokenId1);
        assertEq(amount, 999999999999991746);
        assertEq(lockupStartTime, time1);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 0);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.v3PosStakeInfos(
            ALICE,
            tokenId3
        );
        assertEq(amount, 999999999999991746);
        assertEq(lockupStartTime, time2);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 30744573456182755203);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.v3PosStakeInfos(
            BOB,
            tokenId2
        );
        assertEq(amount, 999999999999991746);
        assertEq(lockupStartTime, time1);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 0);
        (amount, lockupStartTime, multiplier, period, perShareGrowthX64) = feeDistributor.v3PosStakeInfos(
            BOB,
            tokenId4
        );
        assertEq(amount, 999999999999991746);
        assertEq(lockupStartTime, time2);
        assertEq(multiplier, 1);
        assertEq(period, 30);
        assertEq(perShareGrowthX64, 30744573456182755203);
    }

    /// ====== Test cases for the unstake function ======

    function test_RevertIf_InvalidStakeID() public {
        stakeIDs.push(1);
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidStakeID.selector, 1));
        feeDistributor.unstake(stakeIDs, ALICE);
    }

    function test_RevertIf_NotYetReachedTheUnlockingTime() public {
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, ALICE, 30);
        stakeIDs.push(1);
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.NotYetReachedTheUnlockingTime.selector, 1));
        feeDistributor.unstake(stakeIDs, ALICE);
        vm.stopPrank();
    }

    function test_SingleUserUnstake() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, MARK, 30);
        feeDistributor.stakeV3Pos(tokenId, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        stakeIDs.push(1);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        vm.warp(block.timestamp + 31 * 1 days);
        vm.expectEmit(true, true, true, true);
        emit Unstaked(MARK, MARK, 1, 1e18, 2500000000000010317);
        vm.prank(MARK);
        feeDistributor.unstake(stakeIDs, MARK);
        assertEq(veEQUToken.balanceOf(MARK), 0);
        assertEq(IERC20(TOKEN0).balanceOf(MARK), 1e18);
        assertEq(USDC.balanceOf(MARK), 2500000000000010317);
    }

    function test_MultiUserUnstake() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 2e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, MARK, 30);
        feeDistributor.stake(1e18, BOB, 30);
        feeDistributor.stakeV3Pos(tokenId, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        vm.warp(block.timestamp + 31 * 1 days);
        // MARK
        stakeIDs.push(1);
        vm.expectEmit(true, true, true, true);
        emit Unstaked(MARK, MARK, 1, 1e18, 1666666666666671252);
        vm.prank(MARK);
        feeDistributor.unstake(stakeIDs, MARK);
        assertEq(veEQUToken.balanceOf(MARK), 0);
        assertEq(IERC20(TOKEN0).balanceOf(MARK), 1e18);
        assertEq(USDC.balanceOf(MARK), 1666666666666671252);
        // BOB
        delete stakeIDs;
        stakeIDs.push(2);
        vm.expectEmit(true, true, true, true);
        emit Unstaked(BOB, BOB, 2, 1e18, 1666666666666671252);
        vm.prank(BOB);
        feeDistributor.unstake(stakeIDs, BOB);
        assertEq(veEQUToken.balanceOf(BOB), 0);
        assertEq(IERC20(TOKEN0).balanceOf(BOB), 1e18);
        assertEq(USDC.balanceOf(BOB), 1666666666666671252);
    }

    /// ====== Test cases for the unstakeV3Pos function ======

    function test_SingleUserUnstakeV3Pos() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, MARK, 30);
        feeDistributor.stakeV3Pos(tokenId, BOB, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        stakeIDs.push(tokenId);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        vm.warp(block.timestamp + 31 * 1 days);
        vm.expectEmit(true, true, true, true);
        emit V3PosUnstaked(BOB, BOB, tokenId, 999999999999991746, 2499999999999989682);
        vm.prank(BOB);
        feeDistributor.unstakeV3Pos(stakeIDs, BOB);
        assertEq(veEQUToken.balanceOf(BOB), 0);
        assertEq(IERC721(V3_POS).ownerOf(tokenId), BOB);
        assertEq(USDC.balanceOf(BOB), 2499999999999989682);
    }

    function test_MultiUserUnstakeV3Pos() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId1, , , ) = _mintV3PosAndApprove(ALICE);
        (uint256 tokenId2, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId1, MARK, 30);
        feeDistributor.stakeV3Pos(tokenId2, BOB, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        vm.warp(block.timestamp + 31 * 1 days);
        // MARK
        stakeIDs.push(tokenId1);
        vm.expectEmit(true, true, true, true);
        emit V3PosUnstaked(MARK, MARK, tokenId1, 999999999999991746, 1666666666666662081);
        vm.prank(MARK);
        feeDistributor.unstakeV3Pos(stakeIDs, MARK);
        assertEq(veEQUToken.balanceOf(MARK), 0);
        assertEq(IERC721(V3_POS).ownerOf(tokenId1), MARK);
        assertEq(USDC.balanceOf(MARK), 1666666666666662081);
        // BOB
        delete stakeIDs;
        stakeIDs.push(tokenId2);
        vm.expectEmit(true, true, true, true);
        emit V3PosUnstaked(BOB, BOB, tokenId2, 999999999999991746, 1666666666666662081);
        vm.prank(BOB);
        feeDistributor.unstakeV3Pos(stakeIDs, BOB);
        assertEq(veEQUToken.balanceOf(BOB), 0);
        assertEq(IERC721(V3_POS).ownerOf(tokenId2), BOB);
        assertEq(USDC.balanceOf(BOB), 1666666666666662081);
    }

    /// ====== Test cases for the onMintArchitect function ======

    function test_RevertIf_CallerNotEFCAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidCaller.selector, address(this)));
        feeDistributor.onMintArchitect(1);
    }

    function testFuzz_OnMintArchitect(uint256 _tokenID) public {
        _mintArchitect(_tokenID);
        assertEq(feeDistributor.mintedArchitects(), 1);
    }

    function test_FirstTimeMintArchitect() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        uint160 perShareGrowthX64 = feeDistributor.architectPerShareGrowthX64s(1);
        assertEq(perShareGrowthX64, 0);
        assertEq(feeDistributor.mintedArchitects(), 1);
    }

    function test_MultiMintArchitect() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        _mintArchitect(2);
        uint160 perShareGrowthX64 = feeDistributor.architectPerShareGrowthX64s(2);
        assertEq(perShareGrowthX64, 92233720368547758080000000000000000000);
        assertEq(feeDistributor.mintedArchitects(), 2);
    }

    /// ====== Test cases for the collectByRouter function ======

    function test_RevertIf_CallerNotRouterAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidCaller.selector, address(this)));
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        feeDistributor.collectBatchByRouter(ALICE, ALICE, ids);
    }

    function test_CollectBatchByRouter() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 2e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stake(1e18, BOB, 90);
        feeDistributor.stakeV3Pos(tokenId, ALICE, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        vm.startPrank(ROUTER_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit Collected(ALICE, ALICE, 1, 1250000000000002579);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        feeDistributor.collectBatchByRouter(ALICE, ALICE, ids);
        vm.expectEmit(true, true, true, true);
        emit Collected(BOB, BOB, 2, 2500000000000005158);
        ids[0] = 2;
        feeDistributor.collectBatchByRouter(BOB, BOB, ids);
        vm.stopPrank();
    }

    /// ====== Test cases for the collectV3PosByRouter function ======

    function test_CollectV3PosBatchByRouter() public {
        _mintArchitect(1);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId1, , , ) = _mintV3PosAndApprove(ALICE);
        (uint256 tokenId2, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId1, MARK, 30);
        feeDistributor.stakeV3Pos(tokenId2, BOB, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        vm.startPrank(ROUTER_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit V3PosCollected(MARK, MARK, tokenId1, 1666666666666662081);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId1;
        feeDistributor.collectV3PosBatchByRouter(MARK, MARK, ids);
        vm.expectEmit(true, true, true, true);
        emit V3PosCollected(BOB, BOB, tokenId2, 1666666666666662081);
        ids[0] = tokenId2;
        feeDistributor.collectV3PosBatchByRouter(BOB, BOB, ids);
        vm.stopPrank();
    }

    /// ====== Test cases for the collectArchitectByRouter function ======

    function test_RevertIf_InvalidCaller() public {
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidCaller.selector, address(this)));
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        feeDistributor.collectArchitectBatchByRouter(ALICE, ids);
    }

    function test_CollectArchitectBatchByRouter() public {
        _mintArchitect(1);
        _mintArchitect(2);
        _tokenApprove(TOKEN0, ALICE, address(feeDistributor), 1e18);
        (uint256 tokenId, , , ) = _mintV3PosAndApprove(ALICE);
        vm.startPrank(ALICE);
        feeDistributor.stake(1e18, ALICE, 30);
        feeDistributor.stakeV3Pos(tokenId, MARK, 30);
        USDC.transfer(address(feeDistributor), 10e18);
        vm.stopPrank();
        feeDistributor.depositFee(10e18);
        vm.startPrank(ROUTER_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit ArchitectCollected(ALICE, 1, 2500000000000000000);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        feeDistributor.collectArchitectBatchByRouter(ALICE, ids);
        vm.expectEmit(true, true, true, true);
        emit ArchitectCollected(BOB, 2, 2500000000000000000);
        ids[0] = 2;
        feeDistributor.collectArchitectBatchByRouter(BOB, ids);
        vm.stopPrank();
    }

    /// ====== Test cases for the collectArchitect function ======

    function test_RevertIf_InvalidNFTOwner() public {
        addresses.push(ALICE);
        EFCToken.batchMintArchitect(addresses);
        vm.prank(MARK);
        vm.expectRevert(abi.encodeWithSelector(IFeeDistributor.InvalidNFTOwner.selector, MARK, 1));
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        feeDistributor.collectArchitectBatch(MARK, ids);
    }

    function _mintV3PosAndApprove(
        address _receiver
    ) private returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        vm.startPrank(ALICE);
        IERC20(TOKEN0).approve(V3_POS, type(uint256).max);
        IERC20(TOKEN1).approve(V3_POS, type(uint256).max);
        bytes memory positionInfo = Address.functionCall(
            V3_POS,
            abi.encodeWithSignature(
                "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))",
                TOKEN0,
                TOKEN1,
                3000,
                -887220,
                887220,
                999999999999991747,
                99990089118708,
                997509336107624671,
                99739800643261,
                _receiver,
                block.timestamp + 1 hours
            )
        );
        (tokenId, liquidity, amount0, amount1) = abi.decode(positionInfo, (uint256, uint128, uint256, uint256));
        IERC721(V3_POS).approve(address(feeDistributor), tokenId);
        vm.stopPrank();
    }

    function _tokenApprove(address _token, address _owner, address _approveAddress, uint256 _amount) private {
        vm.prank(_owner);
        IERC20(_token).approve(_approveAddress, _amount);
    }

    function _mintArchitect(uint256 _id) private {
        vm.prank(address(EFCToken));
        feeDistributor.onMintArchitect(_id);
    }
}
