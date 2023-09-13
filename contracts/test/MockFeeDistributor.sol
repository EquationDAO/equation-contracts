// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

contract MockFeeDistributor {
    uint256 public balance;
    uint256 public rewardAmountRes;
    uint256 public tokenIDRes;

    function depositFee(uint256 amount) external {
        balance += amount;
    }

    function collectBatchByRouter(
        address /*_owner*/,
        address /*_receiver*/,
        uint256[] calldata /*_ids*/
    ) external returns (uint256 rewardAmount) {
        rewardAmountRes = 1;
        return 1;
    }

    function collectV3PosBatchByRouter(
        address /*_owner*/,
        address /*_receiver*/,
        uint256[] calldata /*_ids*/
    ) external returns (uint256 rewardAmount) {
        rewardAmountRes = 2;
        return 2;
    }

    function collectArchitectBatchByRouter(
        address /*_receiver*/,
        uint256[] calldata /*_tokenIDs*/
    ) external returns (uint256 rewardAmount) {
        rewardAmountRes = 3;
        return 3;
    }
}
