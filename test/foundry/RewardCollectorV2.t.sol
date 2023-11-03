// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/tokens/EQU.sol";
import "../../contracts/plugins/Router.sol";
import "../../contracts/tokens/interfaces/IEFC.sol";
import "../../contracts/plugins/RewardCollectorV2.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RewardCollectorV2Test is Test {
    using ECDSA for bytes32;

    uint256 private constant SIGNER_PRIVATE_KEY = 0x12345;
    EQU private token;
    PositionFarmRewardDistributor private distributor;
    RewardCollectorV2 private rewardCollectorV2;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event PositionFarmRewardCollected(
        address indexed pool,
        address indexed account,
        uint32 indexed nonce,
        address receiver,
        uint256 amount
    );

    function setUp() public {
        token = new EQU();
        distributor = new PositionFarmRewardDistributor(vm.addr(SIGNER_PRIVATE_KEY), token);
        token.setMinter(address(distributor), true);
        rewardCollectorV2 = new RewardCollectorV2(Router(address(0)), token, IEFC(address(0)), distributor);
        distributor.setCollector(address(rewardCollectorV2), true);
    }

    function testMulticall() public {
        address pool1 = address(1);
        address pool2 = address(2);
        address account = address(3);
        uint32 nonce = 1;
        uint256 totalReward1 = 100;
        uint256 totalReward2 = 200;
        PositionFarmRewardDistributor.PoolTotalReward[]
            memory poolTotalRewards = new PositionFarmRewardDistributor.PoolTotalReward[](2);
        poolTotalRewards[0] = PositionFarmRewardDistributor.PoolTotalReward(pool1, totalReward1);
        poolTotalRewards[1] = PositionFarmRewardDistributor.PoolTotalReward(pool2, totalReward2);
        bytes32 hash = keccak256(abi.encode(account, nonce, poolTotalRewards)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "collectPositionFarmRewardBatch(uint32,(address,uint256)[],bytes)",
            nonce,
            poolTotalRewards,
            signature
        );
        data[1] = abi.encodeWithSignature("sweepToken(address,uint256,address)", address(token), 0, account);
        vm.prank(account);
        vm.expectEmit(true, true, true, true);
        emit PositionFarmRewardCollected(pool1, account, nonce, address(rewardCollectorV2), totalReward1);
        vm.expectEmit(true, true, true, true);
        emit PositionFarmRewardCollected(pool2, account, nonce, address(rewardCollectorV2), totalReward2);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(rewardCollectorV2), totalReward1 + totalReward2);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(rewardCollectorV2), account, totalReward1 + totalReward2);
        bytes[] memory results = rewardCollectorV2.multicall(data);
        assertEq(results[0], bytes(""));
        assertEq(abi.decode(results[1], (uint256)), totalReward1 + totalReward2);
        assertEq(token.balanceOf(account), totalReward1 + totalReward2);
    }
}
