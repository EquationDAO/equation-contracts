// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../types/Side.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPool {
    IERC20 public USD;
    IERC20 public token;

    uint96 private liquidityPositionID;

    mapping(uint96 => address) private positionIDAccount;

    uint160 private longMarketPriceX96;
    uint160 private shortMarketPriceX96;

    constructor(IERC20 _usd, IERC20 _token) {
        USD = _usd;
        token = _token;
    }

    function setLiquidityPositionID(uint96 _positionID) external {
        liquidityPositionID = _positionID;
    }

    function setPositionIDAddress(uint96 _positionID, address account) external {
        positionIDAccount[_positionID] = account;
    }

    function setMarketPriceX96(uint160 _longMarketPriceX96, uint160 _shortMarketPriceX96) external {
        longMarketPriceX96 = _longMarketPriceX96;
        shortMarketPriceX96 = _shortMarketPriceX96;
    }

    // ==================== Liquidity Position Methods ====================

    function liquidityPositionAccount(uint96 _positionID) external view returns (address account) {
        return positionIDAccount[_positionID];
    }

    function openLiquidityPosition(
        address /*_account*/,
        uint128 /*_margin*/,
        uint128 /*_liquidity*/
    ) external view returns (uint96 positionID) {
        return liquidityPositionID;
    }

    function closeLiquidityPosition(
        uint96 /*_positionID*/,
        address /*_receiver*/
    ) external pure returns (uint128 priceImpactFee) {
        return 10000;
    }

    function adjustLiquidityPositionMargin(
        uint96 /*_positionID*/,
        int128 /*_marginDelta*/,
        address /*_receiver*/
    ) external {}

    // ==================== Position Methods ====================
    function increasePosition(
        address /*_account*/,
        Side /*_side*/,
        uint128 /*_marginDelta*/,
        uint128 /*_sizeDelta*/
    ) external pure returns (uint160 tradePriceX96) {
        return 10000;
    }

    function decreasePosition(
        address /*_account*/,
        Side /*_side*/,
        uint128 /*_marginDelta*/,
        uint128 /*_sizeDelta*/,
        address /*_receiver*/
    ) external pure returns (uint160 tradePriceX96) {
        return 10000;
    }

    function positions(
        address /*_account*/,
        Side /*_side*/
    ) external pure returns (uint128 margin, uint128 size, uint160 entryPriceX96, int192 entryFundingRateGrowthX96) {
        return (100, 10, 1000, 1000);
    }

    function collectReferralFee(
        uint256 /*_referralToken*/,
        address /*_receiver*/
    ) external pure returns (uint256 amount) {
        return 1;
    }

    function marketPriceX96(Side _side) external view returns (uint160 _marketPriceX96) {
        return _side.isLong() ? longMarketPriceX96 : shortMarketPriceX96;
    }
}
