// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../farming/interfaces/IRewardFarmCallback.sol";

contract MockRewardFarmCallback is IRewardFarmCallback {
    address public pool;

    address public account;
    int256 public liquidityDelta;
    uint256 public liquidityAfter;
    Side public side;
    uint128 public sizeAfter;
    uint160 public entryPriceAfterX96;

    function onChangeReferralToken(
        address referee,
        uint256 oldReferralToken,
        uint256 oldReferralParentToken,
        uint256 newReferralToken,
        uint256 newReferralParentToken
    ) external override {}

    function onLiquidityPositionChanged(address _account, int256 _liquidityDelta) external override {
        account = _account;
        liquidityDelta = _liquidityDelta;
    }

    function onRiskBufferFundPositionChanged(address _account, uint256 _liquidityAfter) external override {
        account = _account;
        liquidityAfter = _liquidityAfter;
    }

    function onPositionChanged(
        address _account,
        Side _side,
        uint128 _sizeAfter,
        uint160 _entryPriceAfterX96
    ) external override {
        account = _account;
        side = _side;
        sizeAfter = _sizeAfter;
        entryPriceAfterX96 = _entryPriceAfterX96;
    }
}
