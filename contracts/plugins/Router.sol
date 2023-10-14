// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./PluginManager.sol";
import "../libraries/SafeERC20.sol";
import "../tokens/interfaces/IEFC.sol";
import "../farming/interfaces/IRewardFarm.sol";
import "../staking/interfaces/IFeeDistributor.sol";

contract Router is PluginManager {
    IEFC public immutable EFC;
    IRewardFarm public immutable rewardFarm;
    IFeeDistributor public immutable feeDistributor;

    /// @notice Caller is not a plugin or not approved
    error CallerUnauthorized();
    /// @notice Owner mismatch
    error OwnerMismatch(address owner, address expectedOwner);

    constructor(IEFC _EFC, IRewardFarm _rewardFarm, IFeeDistributor _feeDistributor) {
        (EFC, rewardFarm, feeDistributor) = (_EFC, _rewardFarm, _feeDistributor);
    }

    /// @notice Transfers `_amount` of `_token` from `_from` to `_to`
    /// @param _token The address of the ERC20 token
    /// @param _from The address to transfer the tokens from
    /// @param _to The address to transfer the tokens to
    /// @param _amount The amount of tokens to transfer
    function pluginTransfer(IERC20 _token, address _from, address _to, uint256 _amount) external {
        _onlyPluginApproved(_from);
        SafeERC20.safeTransferFrom(_token, _from, _to, _amount);
    }

    /// @notice Transfers an NFT token from `_from` to `_to`
    /// @param _token The address of the ERC721 token to transfer
    /// @param _from The address to transfer the NFT from
    /// @param _to The address to transfer the NFT to
    /// @param _tokenId The ID of the NFT token to transfer
    function pluginTransferNFT(IERC721 _token, address _from, address _to, uint256 _tokenId) external {
        _onlyPluginApproved(_from);
        _token.safeTransferFrom(_from, _to, _tokenId);
    }

    /// @notice Open a new liquidity position
    /// @param _pool The pool in which to open liquidity position
    /// @param _account The owner of the position
    /// @param _margin The margin of the position
    /// @param _liquidity The liquidity (value) of the position
    /// @return positionID The position ID
    function pluginOpenLiquidityPosition(
        IPool _pool,
        address _account,
        uint128 _margin,
        uint128 _liquidity
    ) external returns (uint96 positionID) {
        _onlyPluginApproved(_account);
        return _pool.openLiquidityPosition(_account, _margin, _liquidity);
    }

    /// @notice Close a liquidity position
    /// @param _pool The pool in which to close liquidity position
    /// @param _positionID The position ID
    /// @param _receiver The address to receive the margin at the time of closing
    function pluginCloseLiquidityPosition(IPool _pool, uint96 _positionID, address _receiver) external {
        _onlyPluginApproved(_pool.liquidityPositionAccount(_positionID));
        _pool.closeLiquidityPosition(_positionID, _receiver);
    }

    /// @notice Adjust the margin of a liquidity position
    /// @param _pool The pool in which to adjust liquidity position margin
    /// @param _positionID The position ID
    /// @param _marginDelta The change in margin, positive for increasing margin and negative for decreasing margin
    /// @param _receiver The address to receive the margin when the margin is decreased
    function pluginAdjustLiquidityPositionMargin(
        IPool _pool,
        uint96 _positionID,
        int128 _marginDelta,
        address _receiver
    ) external {
        _onlyPluginApproved(_pool.liquidityPositionAccount(_positionID));
        _pool.adjustLiquidityPositionMargin(_positionID, _marginDelta, _receiver);
    }

    /// @notice Increase the liquidity of a risk buffer fund position
    /// @param _pool The pool in which to increase liquidity
    /// @param _account The owner of the position
    /// @param _liquidityDelta The increase in liquidity
    function pluginIncreaseRiskBufferFundPosition(IPool _pool, address _account, uint128 _liquidityDelta) external {
        _onlyPluginApproved(_account);
        _pool.increaseRiskBufferFundPosition(_account, _liquidityDelta);
    }

    /// @notice Decrease the liquidity of a risk buffer fund position
    /// @param _pool The pool in which to decrease liquidity
    /// @param _account The owner of the position
    /// @param _liquidityDelta The decrease in liquidity
    /// @param _receiver The address to receive the liquidity when it is decreased
    function pluginDecreaseRiskBufferFundPosition(
        IPool _pool,
        address _account,
        uint128 _liquidityDelta,
        address _receiver
    ) external {
        _onlyPluginApproved(_account);
        _pool.decreaseRiskBufferFundPosition(_account, _liquidityDelta, _receiver);
    }

    /// @notice Increase the margin/liquidity (value) of a position
    /// @param _pool The pool in which to increase position
    /// @param _account The owner of the position
    /// @param _side The side of the position (Long or Short)
    /// @param _marginDelta The increase in margin, which can be 0
    /// @param _sizeDelta The increase in size, which can be 0
    /// @return tradePriceX96 The trade price at which the position is adjusted.
    /// If only adding margin, it returns 0, as a Q64.96
    function pluginIncreasePosition(
        IPool _pool,
        address _account,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta
    ) external returns (uint160 tradePriceX96) {
        _onlyPluginApproved(_account);
        return _pool.increasePosition(_account, _side, _marginDelta, _sizeDelta);
    }

    /// @notice Decrease the margin/liquidity (value) of a position
    /// @param _pool The pool in which to decrease position
    /// @param _account The owner of the position
    /// @param _side The side of the position (Long or Short)
    /// @param _marginDelta The decrease in margin, which can be 0
    /// @param _sizeDelta The decrease in size, which can be 0
    /// @param _receiver The address to receive the margin
    /// @return tradePriceX96 The trade price at which the position is adjusted.
    /// If only reducing margin, it returns 0, as a Q64.96
    function pluginDecreasePosition(
        IPool _pool,
        address _account,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta,
        address _receiver
    ) external returns (uint160 tradePriceX96) {
        _onlyPluginApproved(_account);
        return _pool.decreasePosition(_account, _side, _marginDelta, _sizeDelta, _receiver);
    }

    /// @notice Close a position by the liquidator
    /// @param _pool The pool in which to close position
    /// @param _account The owner of the position
    /// @param _side The side of the position (Long or Short)
    /// @param _sizeDelta The decrease in size
    /// @param _receiver The address to receive the margin
    function pluginClosePositionByLiquidator(
        IPool _pool,
        address _account,
        Side _side,
        uint128 _sizeDelta,
        address _receiver
    ) external {
        _onlyLiquidator();
        _pool.decreasePosition(_account, _side, 0, _sizeDelta, _receiver);
    }

    /// @notice Collect the referral fee
    /// @param _pool The pool in which to collect referral fee
    /// @param _referralToken The id of the referral token
    /// @param _receiver The address to receive the referral fee
    /// @return The amount of referral fee received
    function pluginCollectReferralFee(
        IPool _pool,
        uint256 _referralToken,
        address _receiver
    ) external returns (uint256) {
        _onlyPluginApproved(EFC.ownerOf(_referralToken));
        return _pool.collectReferralFee(_referralToken, _receiver);
    }

    /// @notice Collect the liquidity reward
    /// @param _pools The pools in which to collect farm liquidity reward
    /// @param _owner The address of the reward owner
    /// @param _receiver The address to receive the reward
    /// @return rewardDebt The amount of liquidity reward received
    function pluginCollectFarmLiquidityRewardBatch(
        IPool[] calldata _pools,
        address _owner,
        address _receiver
    ) external returns (uint256 rewardDebt) {
        _onlyPluginApproved(_owner);
        return rewardFarm.collectLiquidityRewardBatch(_pools, _owner, _receiver);
    }

    /// @notice Collect the risk buffer fund reward
    /// @param _pools The pools in which to collect farm risk buffer fund reward
    /// @param _owner The address of the reward owner
    /// @param _receiver The address to receive the reward
    /// @return rewardDebt The amount of risk buffer fund reward received
    function pluginCollectFarmRiskBufferFundRewardBatch(
        IPool[] calldata _pools,
        address _owner,
        address _receiver
    ) external returns (uint256 rewardDebt) {
        _onlyPluginApproved(_owner);
        return rewardFarm.collectRiskBufferFundRewardBatch(_pools, _owner, _receiver);
    }

    /// @notice Collect the farm referral reward
    /// @param _pools The pools in which to collect farm risk buffer fund reward
    /// @param _referralTokens The IDs of the referral tokens
    /// @param _receiver The address to receive the referral reward
    /// @return rewardDebt The amount of the referral reward received
    function pluginCollectFarmReferralRewardBatch(
        IPool[] calldata _pools,
        uint256[] calldata _referralTokens,
        address _receiver
    ) external returns (uint256 rewardDebt) {
        uint256 tokensLen = _referralTokens.length;
        require(tokensLen > 0);

        address owner = EFC.ownerOf(_referralTokens[0]);
        _onlyPluginApproved(owner);
        for (uint256 i = 1; i < tokensLen; ++i)
            if (EFC.ownerOf(_referralTokens[i]) != owner) revert OwnerMismatch(EFC.ownerOf(_referralTokens[i]), owner);

        return rewardFarm.collectReferralRewardBatch(_pools, _referralTokens, _receiver);
    }

    /// @notice Collect EQU staking reward tokens
    /// @param _owner The staker
    /// @param _receiver The address used to receive staking reward tokens
    /// @param _ids Index of EQU tokens staking information that need to be collected
    /// @return rewardDebt The amount of staking reward tokens received
    function pluginCollectStakingRewardBatch(
        address _owner,
        address _receiver,
        uint256[] calldata _ids
    ) external returns (uint256 rewardDebt) {
        _onlyPluginApproved(_owner);
        return feeDistributor.collectBatchByRouter(_owner, _receiver, _ids);
    }

    /// @notice Collect Uniswap V3 positions NFT staking reward tokens
    /// @param _owner The Staker
    /// @param _receiver The address used to receive staking reward tokens
    /// @param _ids Index of Uniswap V3 positions NFTs staking information that need to be collected
    /// @return rewardDebt The amount of staking reward tokens received
    function pluginCollectV3PosStakingRewardBatch(
        address _owner,
        address _receiver,
        uint256[] calldata _ids
    ) external returns (uint256 rewardDebt) {
        _onlyPluginApproved(_owner);
        return feeDistributor.collectV3PosBatchByRouter(_owner, _receiver, _ids);
    }

    /// @notice Collect the architect reward
    /// @param _receiver The address used to receive rewards
    /// @param _tokenIDs The IDs of the Architect-type NFT
    /// @return rewardDebt The amount of architect rewards received
    function pluginCollectArchitectRewardBatch(
        address _receiver,
        uint256[] calldata _tokenIDs
    ) external returns (uint256 rewardDebt) {
        uint256 idsLen = _tokenIDs.length;
        require(idsLen > 0);

        address owner = EFC.ownerOf(_tokenIDs[0]);
        _onlyPluginApproved(owner);
        for (uint256 i = 1; i < idsLen; ++i)
            if (EFC.ownerOf(_tokenIDs[i]) != owner) revert OwnerMismatch(EFC.ownerOf(_tokenIDs[i]), owner);

        return feeDistributor.collectArchitectBatchByRouter(_receiver, _tokenIDs);
    }

    function _onlyPluginApproved(address _account) internal view {
        if (!isPluginApproved(_account, msg.sender)) revert CallerUnauthorized();
    }

    function _onlyLiquidator() internal view {
        if (!isRegisteredLiquidator(msg.sender)) revert CallerUnauthorized();
    }
}
