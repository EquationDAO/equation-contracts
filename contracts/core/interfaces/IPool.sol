// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IPoolErrors.sol";
import "./IPoolPosition.sol";
import "./IPoolLiquidityPosition.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Perpetual Pool Position Interface
/// @notice This interface defines the functions for managing positions and liquidity positions in a perpetual pool
interface IPool is IPoolLiquidityPosition, IPoolPosition, IPoolErrors {
    struct PriceVertex {
        uint128 size;
        uint128 premiumRateX96;
    }

    struct PriceState {
        uint128 maxPriceImpactLiquidity;
        uint128 premiumRateX96;
        PriceVertex[7] priceVertices;
        uint8 pendingVertexIndex;
        uint8 liquidationVertexIndex;
        uint8 currentVertexIndex;
        uint128[7] liquidationBufferNetSizes;
    }

    /// @notice Emitted when the price vertex is changed
    event PriceVertexChanged(uint8 index, uint128 sizeAfter, uint128 premiumRateAfterX96);

    /// @notice Emitted when the protocol fee is increased
    /// @param amount The increased protocol fee
    event ProtocolFeeIncreased(uint128 amount);

    /// @notice Emitted when the protocol fee is collected
    /// @param amount The collected protocol fee
    event ProtocolFeeCollected(uint128 amount);

    /// @notice Emitted when the referral fee is increased
    /// @param referee The address of the referee
    /// @param referralToken The id of the referral token
    /// @param referralFee The amount of referral fee
    /// @param referralParentToken The id of the referral parent token
    /// @param referralParentFee The amount of referral parent fee
    event ReferralFeeIncreased(
        address indexed referee,
        uint256 indexed referralToken,
        uint128 referralFee,
        uint256 indexed referralParentToken,
        uint128 referralParentFee
    );

    /// @notice Emitted when the referral fee is collected
    /// @param referralToken The id of the referral token
    /// @param receiver The address to receive the referral fee
    /// @param amount The collected referral fee
    event ReferralFeeCollected(uint256 indexed referralToken, address indexed receiver, uint256 amount);

    function token() external view returns (IERC20);

    /// @notice Change the token config
    /// @dev The call will fail if caller is not the pool factory
    function onChangeTokenConfig() external;

    /// @notice Sample and adjust the funding rate
    function sampleAndAdjustFundingRate() external;

    /// @notice Return the price state
    /// @return maxPriceImpactLiquidity The maximum LP liquidity value used to calculate
    /// premium rate when trader increase or decrease positions
    /// @return premiumRateX96 The premium rate during the last position adjustment by the trader, as a Q32.96
    /// @return priceVertices The price vertices used to determine the pricing function
    /// @return pendingVertexIndex The index used to track the pending update of the price vertex
    /// @return liquidationVertexIndex The index used to store the net position of the liquidation
    /// @return currentVertexIndex The index used to track the current used price vertex
    /// @return liquidationBufferNetSizes The net sizes of the liquidation buffer
    function priceState()
        external
        view
        returns (
            uint128 maxPriceImpactLiquidity,
            uint128 premiumRateX96,
            PriceVertex[7] memory priceVertices,
            uint8 pendingVertexIndex,
            uint8 liquidationVertexIndex,
            uint8 currentVertexIndex,
            uint128[7] memory liquidationBufferNetSizes
        );

    /// @notice Get the market price
    /// @param side The side of the position adjustment, 1 for opening long or closing short positions,
    /// 2 for opening short or closing long positions
    /// @return marketPriceX96 The market price, as a Q64.96
    function marketPriceX96(Side side) external view returns (uint160 marketPriceX96);

    /// @notice Change the price vertex
    /// @param startExclusive The start index of the price vertex to be changed, exclusive
    /// @param endInclusive The end index of the price vertex to be changed, inclusive
    function changePriceVertex(uint8 startExclusive, uint8 endInclusive) external;

    /// @notice Return the protocol fee
    function protocolFee() external view returns (uint128);

    /// @notice Collect the protocol fee
    /// @dev This function can be called without authorization
    function collectProtocolFee() external;

    /// @notice Return the referral fee
    /// @param referralToken The id of the referral token
    function referralFees(uint256 referralToken) external view returns (uint256);

    /// @notice Collect the referral fee
    /// @param referralToken The id of the referral token
    /// @param receiver The address to receive the referral fee
    /// @return The collected referral fee
    function collectReferralFee(uint256 referralToken, address receiver) external returns (uint256);
}
