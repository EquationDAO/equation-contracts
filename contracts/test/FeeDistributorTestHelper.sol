// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../plugins/Router.sol";
import "../staking/FeeDistributor.sol";
import "../tokens/interfaces/IEFC.sol";
import "../staking/interfaces/IUniswapV3Minimum.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeDistributorTestHelper is FeeDistributor {
    address public v3PoolAddress;

    constructor(
        IEFC _EFC,
        IERC20 _EQU,
        IERC20 _WETH,
        IERC20 _veEQU,
        IERC20 _feeToken,
        Router _router,
        IUniswapV3PoolFactoryMinimum _v3PoolFactory,
        IPositionManagerMinimum _v3PositionManager,
        uint16 _withdrawalPeriod,
        address _v3PoolAddress
    )
        FeeDistributor(
            _EFC,
            _EQU,
            _WETH,
            _veEQU,
            _feeToken,
            _router,
            _v3PoolFactory,
            _v3PositionManager,
            _withdrawalPeriod
        )
    {
        v3PoolAddress = _v3PoolAddress;
    }

    function _computeV3PoolAddress(
        address /*_token0*/,
        address /*_token1*/,
        uint24 /*_fee*/
    ) internal view override returns (address pool) {
        pool = v3PoolAddress;
    }
}
