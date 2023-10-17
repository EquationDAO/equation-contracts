// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../staking/interfaces/IUniswapV3Minimum.sol";

contract MockUniswapV3PoolFactory is IUniswapV3PoolFactoryMinimum {
    function feeAmountTickSpacing(uint24 fee) external view override returns (int24) {
        if (fee == 0) return 0;

        return fee == 3000 ? int24(60) : int24(30);
    }
}
