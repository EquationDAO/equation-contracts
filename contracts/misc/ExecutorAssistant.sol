// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import {M as Math} from "../libraries/Math.sol";
import "../plugins/interfaces/IPositionRouter.sol";

interface IPositionRouterState is IPositionRouter {
    function openLiquidityPositionIndex() external view returns (uint128);

    function openLiquidityPositionIndexNext() external view returns (uint128);

    function openLiquidityPositionRequests(uint128 index) external view returns (OpenLiquidityPositionRequest memory);

    function closeLiquidityPositionIndex() external view returns (uint128);

    function closeLiquidityPositionIndexNext() external view returns (uint128);

    function closeLiquidityPositionRequests(uint128 index) external view returns (CloseLiquidityPositionRequest memory);

    function adjustLiquidityPositionMarginIndex() external view returns (uint128);

    function adjustLiquidityPositionMarginIndexNext() external view returns (uint128);

    function adjustLiquidityPositionMarginRequests(
        uint128 index
    ) external view returns (AdjustLiquidityPositionMarginRequest memory);

    function increaseRiskBufferFundPositionIndex() external view returns (uint128);

    function increaseRiskBufferFundPositionIndexNext() external view returns (uint128);

    function increaseRiskBufferFundPositionRequests(
        uint128 index
    ) external view returns (IncreaseRiskBufferFundPositionRequest memory);

    function decreaseRiskBufferFundPositionIndex() external view returns (uint128);

    function decreaseRiskBufferFundPositionIndexNext() external view returns (uint128);

    function decreaseRiskBufferFundPositionRequests(
        uint128 index
    ) external view returns (DecreaseRiskBufferFundPositionRequest memory);

    function increasePositionIndex() external view returns (uint128);

    function increasePositionIndexNext() external view returns (uint128);

    function increasePositionRequests(uint128 index) external view returns (IncreasePositionRequest memory);

    function decreasePositionIndex() external view returns (uint128);

    function decreasePositionIndexNext() external view returns (uint128);

    function decreasePositionRequests(uint128 index) external view returns (DecreasePositionRequest memory);
}

contract ExecutorAssistant {
    IPositionRouterState public immutable positionRouter;

    constructor(IPositionRouterState _positionRouter) {
        positionRouter = _positionRouter;
    }

    /// @dev Calculate the next pool that `Multicall` needs to update the price, and the required endIndex
    /// @param _max The maximum index that execute in one call
    /// @return pools The pools that need to update the price, address(0) means no operation
    /// @return endIndexes The end indexes of each operation, -1 means no operation
    function calculateNextMulticall(
        uint128 _max
    ) external view returns (IPool[] memory pools, int256[7] memory endIndexes) {
        pools = new IPool[](7 * _max);
        uint256 poolIndex;

        // scope for open liquidity position
        {
            (uint128 openLiquidityPositionIndex, uint128 openLiquidityPositionIndexNext) = (
                positionRouter.openLiquidityPositionIndex(),
                positionRouter.openLiquidityPositionIndexNext()
            );
            if (openLiquidityPositionIndex == openLiquidityPositionIndexNext) {
                endIndexes[0] = -1;
            } else {
                endIndexes[0] = int256(Math.min(openLiquidityPositionIndex + _max, openLiquidityPositionIndexNext));
                while (openLiquidityPositionIndex < uint128(uint256(endIndexes[0]))) {
                    IPositionRouter.OpenLiquidityPositionRequest memory request = positionRouter
                        .openLiquidityPositionRequests(openLiquidityPositionIndex);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { openLiquidityPositionIndex++; }
                }
            }
        }

        // scope for close liquidity position
        {
            (uint128 closeLiquidityPositionIndex, uint128 closeLiquidityPositionIndexNext) = (
                positionRouter.closeLiquidityPositionIndex(),
                positionRouter.closeLiquidityPositionIndexNext()
            );
            if (closeLiquidityPositionIndex == closeLiquidityPositionIndexNext) {
                endIndexes[1] = -1;
            } else {
                endIndexes[1] = int256(Math.min(closeLiquidityPositionIndex + _max, closeLiquidityPositionIndexNext));
                while (closeLiquidityPositionIndex < uint128(uint256(endIndexes[1]))) {
                    IPositionRouter.CloseLiquidityPositionRequest memory request = positionRouter
                        .closeLiquidityPositionRequests(closeLiquidityPositionIndex);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { closeLiquidityPositionIndex++; }
                }
            }
        }

        // scope for adjust liquidity position margin
        {
            (uint128 adjustLiquidityPositionMarginIndex, uint128 adjustLiquidityPositionMarginIndexNext) = (
                positionRouter.adjustLiquidityPositionMarginIndex(),
                positionRouter.adjustLiquidityPositionMarginIndexNext()
            );
            if (adjustLiquidityPositionMarginIndex == adjustLiquidityPositionMarginIndexNext) {
                endIndexes[2] = -1;
            } else {
                endIndexes[2] = int256(
                    Math.min(adjustLiquidityPositionMarginIndex + _max, adjustLiquidityPositionMarginIndexNext)
                );
                while (adjustLiquidityPositionMarginIndex < uint128(uint256(endIndexes[2]))) {
                    IPositionRouter.AdjustLiquidityPositionMarginRequest memory request = positionRouter
                        .adjustLiquidityPositionMarginRequests(adjustLiquidityPositionMarginIndex);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { adjustLiquidityPositionMarginIndex++; }
                }
            }
        }

        // scope for increase risk buffer fund position
        {
            (uint128 increaseRiskBufferFundPositionIndex, uint128 increaseRiskBufferFundPositionIndexNext) = (
                positionRouter.increaseRiskBufferFundPositionIndex(),
                positionRouter.increaseRiskBufferFundPositionIndexNext()
            );
            if (increaseRiskBufferFundPositionIndex == increaseRiskBufferFundPositionIndexNext) {
                endIndexes[3] = -1;
            } else {
                endIndexes[3] = int256(
                    Math.min(increaseRiskBufferFundPositionIndex + _max, increaseRiskBufferFundPositionIndexNext)
                );
                while (increaseRiskBufferFundPositionIndex < uint128(uint256(endIndexes[3]))) {
                    IPositionRouter.IncreaseRiskBufferFundPositionRequest memory request = positionRouter
                        .increaseRiskBufferFundPositionRequests(increaseRiskBufferFundPositionIndex);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { increaseRiskBufferFundPositionIndex++; }
                }
            }
        }

        // scope for decrease risk buffer fund position
        {
            (uint128 decreaseRiskBufferFundPositionIndex, uint128 decreaseRiskBufferFundPositionIndexNext) = (
                positionRouter.decreaseRiskBufferFundPositionIndex(),
                positionRouter.decreaseRiskBufferFundPositionIndexNext()
            );
            if (decreaseRiskBufferFundPositionIndex == decreaseRiskBufferFundPositionIndexNext) {
                endIndexes[4] = -1;
            } else {
                endIndexes[4] = int256(
                    Math.min(decreaseRiskBufferFundPositionIndex + _max, decreaseRiskBufferFundPositionIndexNext)
                );
                while (decreaseRiskBufferFundPositionIndex < uint128(uint256(endIndexes[4]))) {
                    IPositionRouter.DecreaseRiskBufferFundPositionRequest memory request = positionRouter
                        .decreaseRiskBufferFundPositionRequests(decreaseRiskBufferFundPositionIndex);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { decreaseRiskBufferFundPositionIndex++; }
                }
            }
        }

        // scope for increase position
        {
            (uint128 increasePositionIndex, uint128 increasePositionIndexNext) = (
                positionRouter.increasePositionIndex(),
                positionRouter.increasePositionIndexNext()
            );
            if (increasePositionIndex == increasePositionIndexNext) {
                endIndexes[5] = -1;
            } else {
                endIndexes[5] = int256(Math.min(increasePositionIndex + _max, increasePositionIndexNext));
                while (increasePositionIndex < uint128(uint256(endIndexes[5]))) {
                    IPositionRouter.IncreasePositionRequest memory request = positionRouter.increasePositionRequests(
                        increasePositionIndex
                    );
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { increasePositionIndex++; }
                }
            }
        }

        // scope for decrease position
        {
            (uint128 decreasePositionIndex, uint128 decreasePositionIndexNext) = (
                positionRouter.decreasePositionIndex(),
                positionRouter.decreasePositionIndexNext()
            );
            if (decreasePositionIndex == decreasePositionIndexNext) {
                endIndexes[6] = -1;
            } else {
                endIndexes[6] = int256(Math.min(decreasePositionIndex + _max, decreasePositionIndexNext));
                while (decreasePositionIndex < uint128(uint256(endIndexes[6]))) {
                    IPositionRouter.DecreasePositionRequest memory request = positionRouter.decreasePositionRequests(
                        decreasePositionIndex
                    );
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { decreasePositionIndex++; }
                }
            }
        }
    }
}
