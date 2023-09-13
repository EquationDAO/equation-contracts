// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPriceFeed {
    mapping(IERC20 => uint160) public minPriceX96s;
    mapping(IERC20 => uint160) public maxPriceX96s;

    function setMinPriceX96(IERC20 _token, uint160 _priceX96) external {
        minPriceX96s[_token] = _priceX96;
    }

    function getMinPriceX96(IERC20 _token) external view returns (uint160 priceX96) {
        return minPriceX96s[_token];
    }

    function setMaxPriceX96(IERC20 _token, uint160 _priceX96) external {
        maxPriceX96s[_token] = _priceX96;
    }

    function getMaxPriceX96(IERC20 _token) external view returns (uint160 priceX96) {
        return maxPriceX96s[_token];
    }
}
