// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../staking/interfaces/IUniswapV3Minimum.sol";

contract MockUniswapV3Pool is IUniswapV3PoolMinimum {
    function slot0()
        external
        pure
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (792242363124136400178523925, -92109, 0, 1, 1, 0, true);
    }
}
