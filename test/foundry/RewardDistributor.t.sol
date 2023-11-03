// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.21;

import "./Token.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../contracts/plugins/RewardDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardDistributorTest is Test {
    uint256 private constant SIGNER_PRIVATE_KEY = 0x12345;
    uint256 private constant OTHER_PRIVATE_KEY = 0x54321;
    address private constant POOL1 = address(1);
    address private constant POOL2 = address(2);
    address private constant ACCOUNT = address(3);
    address private constant RECEIVER = address(4);
    address private constant OTHER_ACCOUNT = address(5);
    uint32 private constant NONCE = 1;
    uint256 private constant TOTAL_REWARD1 = 1000;
    uint256 private constant TOTAL_REWARD2 = 2000;

    RewardDistributor private rewardDistributor;
    IERC20 private token;
    RewardDistributor.PoolTotalReward[] private poolTotalRewards;
    bytes private signature;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Claimed(
        address indexed pool,
        address indexed account,
        uint32 indexed nonce,
        address receiver,
        uint256 amount
    );

    function setUp() public {
        address signer = vm.addr(SIGNER_PRIVATE_KEY);
        token = new Token("T18", "T18");
        rewardDistributor = new RewardDistributor(signer, token);
        Ownable(address(token)).transferOwnership(address(rewardDistributor));
        rewardDistributor.setCollector(address(this), true);
        poolTotalRewards = new RewardDistributor.PoolTotalReward[](2);
        poolTotalRewards[0] = RewardDistributor.PoolTotalReward(POOL1, TOTAL_REWARD1);
        poolTotalRewards[1] = RewardDistributor.PoolTotalReward(POOL2, TOTAL_REWARD2);
        signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, poolTotalRewards);
    }

    function testClaim_RevertIfTheCallerIsNotTheCollector() public {
        vm.prank(OTHER_ACCOUNT);
        vm.expectRevert(abi.encodeWithSignature("CallerUnauthorized(address)", OTHER_ACCOUNT));
        rewardDistributor.claimByCollector(ACCOUNT, NONCE, poolTotalRewards, signature, RECEIVER);
    }

    function testClaim_RevertIfTheNonceIsInvalid() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidNonce(uint32)", NONCE + 1));
        rewardDistributor.claimByCollector(ACCOUNT, NONCE + 1, poolTotalRewards, signature, RECEIVER);
    }

    function testClaim_RevertIfAccountIsNotTheSignedAccount() public {
        vm.expectRevert(RewardDistributor.InvalidSignature.selector);
        rewardDistributor.claimByCollector(OTHER_ACCOUNT, NONCE, poolTotalRewards, signature, RECEIVER);
    }

    function testClaim_RevertIfTheTotalRewardIsInvalid() public {
        poolTotalRewards[0] = RewardDistributor.PoolTotalReward(POOL1, TOTAL_REWARD1 + 1);
        vm.expectRevert(RewardDistributor.InvalidSignature.selector);
        rewardDistributor.claimByCollector(ACCOUNT, NONCE, poolTotalRewards, signature, RECEIVER);
    }

    function testClaim_RevertIfPrivateKeyIsNotSignerPrivateKey() public {
        bytes memory newSignature = sign(OTHER_PRIVATE_KEY, ACCOUNT, NONCE, poolTotalRewards);
        vm.expectRevert(RewardDistributor.InvalidSignature.selector);
        rewardDistributor.claimByCollector(ACCOUNT, NONCE, poolTotalRewards, newSignature, RECEIVER);
    }

    function testClaim_ShouldUpdateWithTheRightValueAndEmitTheRightEvent() public {
        deal(address(token), address(RECEIVER), 1000);
        vm.expectEmit(true, true, true, true);
        emit Claimed(POOL1, ACCOUNT, NONCE, RECEIVER, TOTAL_REWARD1);
        vm.expectEmit(true, true, true, true);
        emit Claimed(POOL2, ACCOUNT, NONCE, RECEIVER, TOTAL_REWARD2);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), RECEIVER, TOTAL_REWARD1 + TOTAL_REWARD2);
        rewardDistributor.claimByCollector(ACCOUNT, NONCE, poolTotalRewards, signature, RECEIVER);
        assertEq(token.balanceOf(RECEIVER), TOTAL_REWARD1 + TOTAL_REWARD2 + 1000);
        assertEq(rewardDistributor.nonces(ACCOUNT), NONCE);
        assertEq(rewardDistributor.claimedRewards(POOL1, ACCOUNT), TOTAL_REWARD1);
        assertEq(rewardDistributor.claimedRewards(POOL2, ACCOUNT), TOTAL_REWARD2);

        uint256 newAmount1 = 10000;
        uint256 newAmount2 = 20000;
        RewardDistributor.PoolTotalReward[] memory newPoolTotalRewards = new RewardDistributor.PoolTotalReward[](2);
        newPoolTotalRewards[0] = RewardDistributor.PoolTotalReward(POOL1, TOTAL_REWARD1 + newAmount1);
        newPoolTotalRewards[1] = RewardDistributor.PoolTotalReward(POOL2, TOTAL_REWARD2 + newAmount2);

        bytes memory newSignature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE + 1, newPoolTotalRewards);
        vm.expectEmit(true, true, true, true);
        emit Claimed(POOL1, ACCOUNT, NONCE + 1, RECEIVER, newAmount1);
        vm.expectEmit(true, true, true, true);
        emit Claimed(POOL2, ACCOUNT, NONCE + 1, RECEIVER, newAmount2);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), RECEIVER, newAmount1 + newAmount2);
        rewardDistributor.claimByCollector(ACCOUNT, NONCE + 1, newPoolTotalRewards, newSignature, RECEIVER);
        assertEq(token.balanceOf(RECEIVER), TOTAL_REWARD1 + TOTAL_REWARD2 + newAmount1 + newAmount2 + 1000);
        assertEq(rewardDistributor.nonces(ACCOUNT), NONCE + 1);
        assertEq(rewardDistributor.claimedRewards(POOL1, ACCOUNT), TOTAL_REWARD1 + newAmount1);
        assertEq(rewardDistributor.claimedRewards(POOL2, ACCOUNT), TOTAL_REWARD2 + newAmount2);
    }

    function testClaim_RevertIfTheSameNonceIsUsedAgain() public {
        rewardDistributor.claimByCollector(ACCOUNT, NONCE, poolTotalRewards, signature, RECEIVER);
        vm.expectRevert(abi.encodeWithSignature("InvalidNonce(uint32)", NONCE));
        rewardDistributor.claimByCollector(ACCOUNT, NONCE, poolTotalRewards, signature, RECEIVER);
    }

    function testClaim_RevertIfTheTotalRewardIsLtClaimedReward() public {
        rewardDistributor.claimByCollector(ACCOUNT, NONCE, poolTotalRewards, signature, RECEIVER);
        poolTotalRewards[0] = RewardDistributor.PoolTotalReward(POOL1, TOTAL_REWARD1 - 1);
        signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE + 1, poolTotalRewards);
        vm.expectRevert(stdError.arithmeticError);
        rewardDistributor.claimByCollector(ACCOUNT, NONCE + 1, poolTotalRewards, signature, RECEIVER);
    }

    function testClaim_BySender() public {
        vm.prank(ACCOUNT);
        vm.expectEmit(true, true, true, true);
        emit Claimed(POOL1, ACCOUNT, NONCE, ACCOUNT, TOTAL_REWARD1);
        vm.expectEmit(true, true, true, true);
        emit Claimed(POOL2, ACCOUNT, NONCE, ACCOUNT, TOTAL_REWARD2);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ACCOUNT, TOTAL_REWARD1 + TOTAL_REWARD2);
        rewardDistributor.claim(NONCE, poolTotalRewards, signature, address(0));
        assertEq(token.balanceOf(ACCOUNT), TOTAL_REWARD1 + TOTAL_REWARD2);
        assertEq(rewardDistributor.nonces(ACCOUNT), NONCE);
        assertEq(rewardDistributor.claimedRewards(POOL1, ACCOUNT), TOTAL_REWARD1);
        assertEq(rewardDistributor.claimedRewards(POOL2, ACCOUNT), TOTAL_REWARD2);
    }

    function sign(
        uint256 _privateKey,
        address _account,
        uint32 _nonce,
        RewardDistributor.PoolTotalReward[] memory _poolTotalRewards
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
}
