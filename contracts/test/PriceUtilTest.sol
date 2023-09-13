// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../libraries/PriceUtil.sol";
import "../core/interfaces/IPoolFactory.sol";

contract PriceUtilTest {
    using SafeCast for *;

    IPoolFactory private poolFactory;
    IPriceFeed private priceFeed;
    IERC20 public token;

    IPool.GlobalLiquidityPosition public globalLiquidityPosition;
    IPool.PriceState public priceState;

    uint160 public tradePriceX96;

    event PriceVertexChanged(uint8 index, uint128 sizeAfter, uint128 premiumRateAfterX96);
    error InvalidCaller(address requiredCaller);

    // ==================== setting methods ====================

    function setPoolFactory(address _poolFactory) external {
        poolFactory = IPoolFactory(_poolFactory);
    }

    function setPriceFeed(address _priceFeed) external {
        priceFeed = IPriceFeed(_priceFeed);
    }

    function setToken(address _token) external {
        token = IERC20(_token);
    }

    function setGlobalLiquidityPosition(IPool.GlobalLiquidityPosition memory _globalLiquidityPosition) external {
        globalLiquidityPosition = _globalLiquidityPosition;
    }

    function setPriceState(IPool.PriceState memory _priceState) external {
        priceState = _priceState;
    }

    // ==================== PriceUtil methods ====================

    function updatePriceState(Side _side, uint128 _sizeDelta, uint160 _indexPriceX96, bool liquidation) external {
        tradePriceX96 = PriceUtil.updatePriceState(
            globalLiquidityPosition,
            priceState,
            _side,
            _sizeDelta,
            _indexPriceX96,
            liquidation
        );
    }

    function calculateMarketPriceX96(
        Side _globalSide,
        Side _side,
        uint160 _indexPriceX96,
        uint128 _premiumRateX96
    ) external pure returns (uint160 marketPriceX96) {
        return PriceUtil.calculateMarketPriceX96(_globalSide, _side, _indexPriceX96, _premiumRateX96);
    }

    // ==================== copied from Pool.sol ====================

    function changePriceVertex(uint8 startExclusive, uint8 endInclusive) external {
        if (msg.sender != address(this)) revert InvalidCaller(address(this));

        unchecked {
            // If the vertex represented by end is the same as the vertex represented by end + 1,
            // then the vertices in the range (start, LATEST_VERTEX] need to be updated
            if (endInclusive < Constants.LATEST_VERTEX) {
                IPool.PriceVertex memory previous = priceState.priceVertices[endInclusive];
                IPool.PriceVertex memory next = priceState.priceVertices[endInclusive + 1];
                if (previous.size >= next.size || previous.premiumRateX96 >= next.premiumRateX96)
                    endInclusive = Constants.LATEST_VERTEX;
            }
        }

        _changePriceVertex(startExclusive, endInclusive);
    }

    /// @dev Change the price vertex
    /// @param startExclusive The start index of the price vertex to be changed, exclusive
    /// @param endInclusive The end index of the price vertex to be changed, inclusive
    function _changePriceVertex(uint8 startExclusive, uint8 endInclusive) private {
        uint160 indexPriceX96 = priceFeed.getMaxPriceX96(token);
        uint128 liquidity = uint128(Math.min(globalLiquidityPosition.liquidity, priceState.maxPriceImpactLiquidity));

        unchecked {
            for (uint8 index = startExclusive + 1; index <= endInclusive; ++index) {
                (uint32 balanceRate, uint32 premiumRate) = poolFactory.tokenPriceVertexConfigs(token, index);
                (uint128 sizeAfter, uint128 premiumRateAfterX96) = _calculatePriceVertex(
                    balanceRate,
                    premiumRate,
                    liquidity,
                    indexPriceX96
                );
                if (index > 1) {
                    IPool.PriceVertex memory previous = priceState.priceVertices[index - 1];
                    if (previous.size >= sizeAfter || previous.premiumRateX96 >= premiumRateAfterX96)
                        (sizeAfter, premiumRateAfterX96) = (previous.size, previous.premiumRateX96);
                }

                priceState.priceVertices[index].size = sizeAfter;
                priceState.priceVertices[index].premiumRateX96 = premiumRateAfterX96;
                emit PriceVertexChanged(index, sizeAfter, premiumRateAfterX96);

                // If the vertex represented by end is the same as the vertex represented by end + 1,
                // then the vertices in range (start, LATEST_VERTEX] need to be updated
                if (index == endInclusive && endInclusive < Constants.LATEST_VERTEX) {
                    IPool.PriceVertex memory next = priceState.priceVertices[index + 1];
                    if (sizeAfter >= next.size || premiumRateAfterX96 >= next.premiumRateX96)
                        endInclusive = Constants.LATEST_VERTEX;
                }
            }
        }
    }

    function _calculatePriceVertex(
        uint32 _balanceRate,
        uint32 _premiumRate,
        uint128 _liquidity,
        uint160 _indexPriceX96
    ) private pure returns (uint128 size, uint128 premiumRateX96) {
        size = Math
            .mulDiv((Constants.Q96 * _balanceRate) / Constants.BASIS_POINTS_DIVISOR, _liquidity, _indexPriceX96)
            .toUint128();
        premiumRateX96 = uint128((Constants.Q96 * _premiumRate) / Constants.BASIS_POINTS_DIVISOR);
    }
}
