// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../core/interfaces/IPool.sol";

contract MockRewardFarm {
    uint256 public rewardDebtRes;

    function collectLiquidityRewardBatch(
        IPool[] calldata /*_pools*/,
        address /*_owner*/,
        address /*_receiver*/
    ) external returns (uint256 rewardDebt) {
        rewardDebtRes = 1;
        return 1;
    }

    function collectRiskBufferFundRewardBatch(
        IPool[] calldata /*_pools*/,
        address /*_owner*/,
        address /*_receiver*/
    ) external returns (uint256 rewardDebt) {
        rewardDebtRes = 2;
        return 2;
    }

    function collectReferralRewardBatch(
        IPool[] calldata /*_pools*/,
        uint256[] calldata /*_referralTokens*/,
        address /*_receiver*/
    ) external returns (uint256 rewardDebt) {
        rewardDebtRes = 3;
        return 3;
    }

    function collectReferralReward(
        uint256 /*referralToken*/,
        address /*receiver*/
    ) external returns (uint256 rewardDebt) {
        rewardDebtRes = 4;
        return 4;
    }
}
