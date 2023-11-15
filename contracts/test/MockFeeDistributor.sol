// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../libraries/SafeERC20.sol";

contract MockFeeDistributor {
    uint256 public balance;
    uint256 public rewardAmountRes;
    uint256 public tokenIDRes;
    mapping(uint16 => uint16) public multipliers;

    IERC20 public token;

    constructor() {
        multipliers[30] = 1;
        multipliers[60] = 2;
        multipliers[90] = 3;
    }

    function setToken(IERC20 _token) external {
        token = _token;
    }

    function depositFee(uint256 amount) external {
        balance += amount;
    }

    function lockupRewardMultipliers(uint16 period) external view returns (uint16 multiplier) {
        multiplier = multipliers[period];
    }

    function stake(uint256 amount, address /*account*/, uint16 period) external {
        require(multipliers[period] > 0, "MockFeeDistributor: invalid period");
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
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
