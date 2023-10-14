// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Side} from "../../types/Side.sol";

interface IRewardFarmCallback {
    /// @notice The callback function was called after referral token bound
    /// @param referee The address of the user who bound the referral token
    /// @param oldReferralToken The referral token that the user had previously bound
    /// @param oldReferralParentToken The parent of the referral token that the user had previously bound
    /// @param newReferralToken The referral token that is currently bound by the user
    /// @param newReferralParentToken The parent of the referral token that is currently bound by the user
    function onChangeReferralToken(
        address referee,
        uint256 oldReferralToken,
        uint256 oldReferralParentToken,
        uint256 newReferralToken,
        uint256 newReferralParentToken
    ) external;

    /// @notice The callback function was called after a new liquidity position was opened
    /// @param account The owner of the liquidity position
    /// @param liquidityDelta The liquidity delta of the position
    function onLiquidityPositionChanged(address account, int256 liquidityDelta) external;

    /// @notice The callback function was called after a risk buffer fund position was changed
    /// @param account The owner of the position
    /// @param liquidityAfter The liquidity of the position after the change
    function onRiskBufferFundPositionChanged(address account, uint256 liquidityAfter) external;

    /// @notice The callback function was called after a position was changed
    /// @param account The owner of the position
    /// @param side The side of the position
    /// @param sizeAfter The size of the position after the change
    /// @param entryPriceAfterX96 The entry price of the position after the change, as a Q64.96
    function onPositionChanged(address account, Side side, uint128 sizeAfter, uint160 entryPriceAfterX96) external;
}
