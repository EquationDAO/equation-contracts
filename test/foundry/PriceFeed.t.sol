// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../contracts/oracle/PriceFeed.sol";
import "../../contracts/oracle/interfaces/IPriceFeed.sol";
import "../../contracts/oracle/interfaces/IChainLinkAggregator.sol";
import "../../contracts/test/MockChainLinkPriceFeed.sol";

contract PriceFeedTest is Test {
    using SafeCast for *;

    event PriceUpdated(IERC20 indexed token, uint160 priceX96, uint160 minPriceX96, uint160 maxPriceX96);
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    uint8 constant refPriceDecimals = 8;

    PriceFeed priceFeed;
    MockChainLinkPriceFeed mockChainLink;

    function setUp() public {
        priceFeed = new PriceFeed();
        priceFeed.setUpdater(address(1), true);
        priceFeed.setMaxCumulativeDeltaDiffs(IERC20(WETH), 100 * 1000);
        mockChainLink = new MockChainLinkPriceFeed();
        priceFeed.setRefPriceFeeds(IERC20(WETH), IChainLinkAggregator(address(mockChainLink)));
    }

    function test_SetPrices() public {
        uint256 nowTs = 200000;
        vm.warp(nowTs);
        uint256 _magnification = 10 ** refPriceDecimals;
        mockChainLink.setRoundData(100, 100 * _magnification.toInt256(), nowTs - 1, nowTs - 1, 100);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH);
        uint160[] memory priceX96s = new uint160[](1);
        priceX96s[0] = _toPriceX96(111, 18, 6);
        vm.prank(address(1));
        vm.expectEmit(true, false, false, true, address(priceFeed));
        emit PriceUpdated(IERC20(WETH), priceX96s[0], _toPriceX96(100, 18, 6), priceX96s[0]);
        priceFeed.setPriceX96s(tokens, priceX96s, nowTs.toUint64());
    }

    function testFuzz_SetPrices(uint128 currentPriceX96) public {
        setPricesForTest(currentPriceX96);
    }

    function setPricesForTest(uint160 currentPriceX96) private {
        uint256 nowTs = 200000;
        vm.warp(nowTs);
        uint256 _magnification = 10 ** refPriceDecimals;
        mockChainLink.setRoundData(100, 100 * _magnification.toInt256(), nowTs - 1, nowTs - 1, 100);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH);
        uint160[] memory priceX96s = new uint160[](1);
        priceX96s[0] = currentPriceX96;

        uint160 currentRefPrice = _toPriceX96(100, 18, 6);
        uint160 minPriceX96;
        uint160 maxPriceX96;
        uint256 DELTA_PRECISION = priceFeed.DELTA_PRECISION();
        (uint32 maxDeviationRatio, , , ) = priceFeed.slot();
        if (currentRefPrice > currentPriceX96) {
            if (((currentRefPrice - currentPriceX96) * DELTA_PRECISION) / currentRefPrice > maxDeviationRatio) {
                maxPriceX96 = currentRefPrice;
                minPriceX96 = currentPriceX96;
            } else {
                maxPriceX96 = currentPriceX96;
                minPriceX96 = currentPriceX96;
            }
        } else {
            if (((currentPriceX96 - currentRefPrice) * DELTA_PRECISION) / currentRefPrice > maxDeviationRatio) {
                maxPriceX96 = currentPriceX96;
                minPriceX96 = currentRefPrice;
            } else {
                maxPriceX96 = currentPriceX96;
                minPriceX96 = currentPriceX96;
            }
        }

        vm.prank(address(1));
        vm.expectEmit(true, false, false, true, address(priceFeed));
        emit PriceUpdated(IERC20(WETH), currentPriceX96, minPriceX96, maxPriceX96);
        priceFeed.setPriceX96s(tokens, priceX96s, nowTs.toUint64());
    }

    function _toPriceX96(uint256 _price, uint8 _tokenDecimals, uint8 _usdDecimals) private pure returns (uint160) {
        _price = Math.mulDiv(_price, Constants.Q96, 1);
        _price = Math.mulDiv(_price, 10 ** _usdDecimals, 10 ** _tokenDecimals);
        return _price.toUint160();
    }
}
