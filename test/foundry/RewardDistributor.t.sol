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
    address private constant ACCOUNT = address(1);
    address private constant RECEIVER = address(2);
    address private constant OTHER_ACCOUNT = address(3);
    uint32 private constant NONCE = 1;
    uint224 private constant TOTAL_REWARD = 1000;

    RewardDistributor private rewardDistributor;
    IERC20 private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Claimed(address indexed receiver, address indexed account, uint32 indexed nonce, uint224 amount);

    function setUp() public {
        address signer = vm.addr(SIGNER_PRIVATE_KEY);
        token = new Token("T18", "T18");
        rewardDistributor = new RewardDistributor(signer, token);
        Ownable(address(token)).transferOwnership(address(rewardDistributor));
        rewardDistributor.setCollector(address(this), true);
    }

    function testClaim_RevertIfTheCallerIsNotTheCollector() public {
        vm.prank(OTHER_ACCOUNT);
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectRevert(abi.encodeWithSignature("CallerUnauthorized(address)", OTHER_ACCOUNT));
        rewardDistributor.claim(ACCOUNT, NONCE, TOTAL_REWARD, signature, RECEIVER);
    }

    function testClaim_RevertIfTheNonceIsInvalid() public {
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectRevert(abi.encodeWithSignature("InvalidNonce(uint32)", NONCE + 1));
        rewardDistributor.claim(ACCOUNT, NONCE + 1, TOTAL_REWARD, signature, RECEIVER);
    }

    function testClaim_RevertIfAccountIsNotTheSignedAccount() public {
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectRevert(RewardDistributor.InvalidSignature.selector);
        rewardDistributor.claim(OTHER_ACCOUNT, NONCE, TOTAL_REWARD, signature, RECEIVER);
    }

    function testClaim_RevertIfTheTotalRewardIsInvalid() public {
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectRevert(RewardDistributor.InvalidSignature.selector);
        rewardDistributor.claim(ACCOUNT, NONCE, TOTAL_REWARD + 1, signature, RECEIVER);
    }

    function testClaim_RevertIfPrivateKeyIsNotSignerPrivateKey() public {
        bytes memory signature = sign(OTHER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectRevert(RewardDistributor.InvalidSignature.selector);
        rewardDistributor.claim(ACCOUNT, NONCE, TOTAL_REWARD, signature, RECEIVER);
    }

    function testClaim_ShouldUpdateWithTheRightValueAndEmitTheRightEvent() public {
        deal(address(token), address(RECEIVER), 1000);
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectEmit(true, true, true, true);
        emit Claimed(RECEIVER, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), RECEIVER, TOTAL_REWARD);
        rewardDistributor.claim(ACCOUNT, NONCE, TOTAL_REWARD, signature, RECEIVER);
        assertEq(token.balanceOf(RECEIVER), TOTAL_REWARD + 1000);
        (uint32 nonce, uint224 claimedReward) = rewardDistributor.claimedInfos(ACCOUNT);
        assertEq(nonce, NONCE);
        assertEq(claimedReward, TOTAL_REWARD);

        uint224 newAmount = 2000;
        signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE + 1, TOTAL_REWARD + newAmount);
        vm.expectEmit(true, true, true, true);
        emit Claimed(RECEIVER, ACCOUNT, NONCE + 1, newAmount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), RECEIVER, newAmount);
        rewardDistributor.claim(ACCOUNT, NONCE + 1, TOTAL_REWARD + newAmount, signature, RECEIVER);
        assertEq(token.balanceOf(RECEIVER), TOTAL_REWARD + newAmount + 1000);
        (nonce, claimedReward) = rewardDistributor.claimedInfos(ACCOUNT);
        assertEq(nonce, NONCE + 1);
        assertEq(claimedReward, TOTAL_REWARD + newAmount);
    }

    function testClaim_RevertIfTheSameNonceIsUsedAgain() public {
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        rewardDistributor.claim(ACCOUNT, NONCE, TOTAL_REWARD, signature, RECEIVER);
        vm.expectRevert(abi.encodeWithSignature("InvalidNonce(uint32)", NONCE));
        rewardDistributor.claim(ACCOUNT, NONCE, TOTAL_REWARD, signature, RECEIVER);
    }

    function testClaim_RevertIfTheTotalRewardIsLtClaimedReward() public {
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        rewardDistributor.claim(ACCOUNT, NONCE, TOTAL_REWARD, signature, RECEIVER);
        signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE + 1, TOTAL_REWARD - 1);
        vm.expectRevert(stdError.arithmeticError);
        rewardDistributor.claim(ACCOUNT, NONCE + 1, TOTAL_REWARD - 1, signature, RECEIVER);
    }

    function testClaim_BySender() public {
        vm.prank(ACCOUNT);
        bytes memory signature = sign(SIGNER_PRIVATE_KEY, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectEmit(true, true, true, true);
        emit Claimed(ACCOUNT, ACCOUNT, NONCE, TOTAL_REWARD);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), ACCOUNT, TOTAL_REWARD);
        rewardDistributor.claim(NONCE, TOTAL_REWARD, signature, address(0));
        assertEq(token.balanceOf(ACCOUNT), TOTAL_REWARD);
        (uint32 nonce, uint224 claimedReward) = rewardDistributor.claimedInfos(ACCOUNT);
        assertEq(nonce, NONCE);
        assertEq(claimedReward, TOTAL_REWARD);
    }

    function sign(
        uint256 _privateKey,
        address _account,
        uint32 _nonce,
        uint224 _totalReward
    ) private pure returns (bytes memory signature) {
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(_account, _nonce, _totalReward)))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        signature = abi.encodePacked(r, s, v);
    }
}
