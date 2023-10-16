// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

library Constants {
    uint32 internal constant BASIS_POINTS_DIVISOR = 100_000_000;

    uint16 internal constant ADJUST_FUNDING_RATE_INTERVAL = 1 hours;
    uint16 internal constant SAMPLE_PREMIUM_RATE_INTERVAL = 5 seconds;
    uint16 internal constant REQUIRED_SAMPLE_COUNT = ADJUST_FUNDING_RATE_INTERVAL / SAMPLE_PREMIUM_RATE_INTERVAL;
    /// @dev 8 * (1+2+3+...+720) = 8 * ((1+720) * 720 / 2) = 8 * 259560
    uint32 internal constant PREMIUM_RATE_AVG_DENOMINATOR = 8 * 259560;
    /// @dev RoundingUp(50000 / 8 * Q96 / BASIS_POINTS_DIVISOR) = 4951760157141521099596497
    int256 internal constant PREMIUM_RATE_CLAMP_BOUNDARY_X96 = 4951760157141521099596497; // 0.05% / 8

    uint8 internal constant VERTEX_NUM = 7;
    uint8 internal constant LATEST_VERTEX = VERTEX_NUM - 1;

    uint64 internal constant RISK_BUFFER_FUND_LOCK_PERIOD = 90 days;

    uint256 internal constant Q64 = 1 << 64;
    uint256 internal constant Q96 = 1 << 96;

    bytes32 internal constant ROLE_POSITION_LIQUIDATOR = keccak256("ROLE_POSITION_LIQUIDATOR");
    bytes32 internal constant ROLE_LIQUIDITY_POSITION_LIQUIDATOR = keccak256("ROLE_LIQUIDITY_POSITION_LIQUIDATOR");
}
