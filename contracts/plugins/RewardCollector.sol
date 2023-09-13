// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./Router.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RewardCollector is Multicall {
    using SafeMath for uint256;

    IERC20 public immutable EQU;
    Router public immutable router;
    IEFC public immutable EFC;

    error InvalidCaller(address caller, address requiredCaller);
    error InsufficientBalance(uint256 amount, uint256 requiredAmount);

    constructor(Router _router, IERC20 _EQU, IEFC _EFC) {
        router = _router;
        EQU = _EQU;
        EFC = _EFC;
    }

    function sweepToken(IERC20 _token, uint256 _amountMinimum, address _receiver) external returns (uint256 amount) {
        amount = _token.balanceOf(address(this));
        if (amount < _amountMinimum) revert InsufficientBalance(amount, _amountMinimum);

        SafeERC20.safeTransfer(_token, _receiver, amount);
    }

    function collectReferralFeeBatch(
        IPool[] calldata _pools,
        uint256[] calldata _referralTokens
    ) external returns (uint256 amount) {
        _validateOwner(_referralTokens);
        IPool pool;
        for (uint256 i; i < _pools.length; ++i) {
            pool = _pools[i];
            for (uint256 j; j < _referralTokens.length; ++j) {
                amount += router.pluginCollectReferralFee(pool, _referralTokens[j], address(this));
            }
        }
    }

    function collectFarmLiquidityRewardBatch(IPool[] calldata _pools) external returns (uint256 rewardDebt) {
        rewardDebt = router.pluginCollectFarmLiquidityRewardBatch(_pools, msg.sender, address(this));
    }

    function collectFarmRiskBufferFundRewardBatch(IPool[] calldata _pools) external returns (uint256 rewardDebt) {
        rewardDebt = router.pluginCollectFarmRiskBufferFundRewardBatch(_pools, msg.sender, address(this));
    }

    function collectFarmReferralRewardBatch(
        IPool[] calldata _pools,
        uint256[] calldata _referralTokens
    ) external returns (uint256 rewardDebt) {
        _validateOwner(_referralTokens);
        return router.pluginCollectFarmReferralRewardBatch(_pools, _referralTokens, address(this));
    }

    function collectStakingRewardBatch(uint256[] calldata _ids) external returns (uint256 rewardDebt) {
        rewardDebt = router.pluginCollectStakingRewardBatch(msg.sender, address(this), _ids);
    }

    function collectV3PosStakingRewardBatch(uint256[] calldata _ids) external returns (uint256 rewardDebt) {
        rewardDebt = router.pluginCollectV3PosStakingRewardBatch(msg.sender, address(this), _ids);
    }

    function collectArchitectRewardBatch(uint256[] calldata _tokenIDs) external returns (uint256 rewardDebt) {
        _validateOwner(_tokenIDs);
        rewardDebt = router.pluginCollectArchitectRewardBatch(address(this), _tokenIDs);
    }

    function _validateOwner(uint256[] calldata _referralTokens) private view {
        address caller = msg.sender;
        for (uint256 i; i < _referralTokens.length; ++i) {
            if (EFC.ownerOf(_referralTokens[i]) != caller)
                revert InvalidCaller(caller, EFC.ownerOf(_referralTokens[i]));
        }
    }
}
