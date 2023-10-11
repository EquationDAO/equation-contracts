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
    struct IndexPerOperation {
        /// @dev The start index of the operation
        uint128 index;
        /// @dev The next index of the operation
        uint128 indexNext;
        /// @dev The end index of the operation.
        /// If the index == indexNext, indexEnd is invalid.
        uint128 indexEnd;
    }

    IPositionRouterState public immutable positionRouter;

    constructor(IPositionRouterState _positionRouter) {
        positionRouter = _positionRouter;
    }

    /// @dev Calculate the next pool that `Multicall` needs to update the price, and the required indexEnd
    /// @param _max The maximum index that execute in one call
    /// @return pools The pools that need to update the price, address(0) means no operation
    /// @return indexPerOperations The index of the per operation
    function calculateNextMulticall(
        uint128 _max
    ) external view returns (IPool[] memory pools, IndexPerOperation[7] memory indexPerOperations) {
        pools = new IPool[](7 * _max);
        uint256 poolIndex;

        // scope for open liquidity position
        {
            IndexPerOperation memory indexPerOperation = indexPerOperations[0];
            (indexPerOperation.index, indexPerOperation.indexNext) = (
                positionRouter.openLiquidityPositionIndex(),
                positionRouter.openLiquidityPositionIndexNext()
            );
            if (indexPerOperation.index != indexPerOperation.indexNext) {
                indexPerOperation.indexEnd = uint128(
                    Math.min(indexPerOperation.index + _max, indexPerOperation.indexNext)
                );
                uint128 index = indexPerOperation.index;
                while (index < indexPerOperation.indexEnd) {
                    IPositionRouter.OpenLiquidityPositionRequest memory request = positionRouter
                        .openLiquidityPositionRequests(index);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { index++; }
                }
            }
        }

        // scope for close liquidity position
        {
            IndexPerOperation memory indexPerOperation = indexPerOperations[1];
            (indexPerOperation.index, indexPerOperation.indexNext) = (
                positionRouter.closeLiquidityPositionIndex(),
                positionRouter.closeLiquidityPositionIndexNext()
            );
            if (indexPerOperation.index != indexPerOperation.indexNext) {
                indexPerOperation.indexEnd = uint128(
                    Math.min(indexPerOperation.index + _max, indexPerOperation.indexNext)
                );
                uint128 index = indexPerOperation.index;
                while (index < indexPerOperation.indexEnd) {
                    IPositionRouter.CloseLiquidityPositionRequest memory request = positionRouter
                        .closeLiquidityPositionRequests(index);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { index++; }
                }
            }
        }

        // scope for adjust liquidity position margin
        {
            IndexPerOperation memory indexPerOperation = indexPerOperations[2];
            (indexPerOperation.index, indexPerOperation.indexNext) = (
                positionRouter.adjustLiquidityPositionMarginIndex(),
                positionRouter.adjustLiquidityPositionMarginIndexNext()
            );
            if (indexPerOperation.index != indexPerOperation.indexNext) {
                indexPerOperation.indexEnd = uint128(
                    Math.min(indexPerOperation.index + _max, indexPerOperation.indexNext)
                );
                uint128 index = indexPerOperation.index;
                while (index < indexPerOperation.indexEnd) {
                    IPositionRouter.AdjustLiquidityPositionMarginRequest memory request = positionRouter
                        .adjustLiquidityPositionMarginRequests(index);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { index++; }
                }
            }
        }

        // scope for increase risk buffer fund position
        {
            IndexPerOperation memory indexPerOperation = indexPerOperations[3];
            (indexPerOperation.index, indexPerOperation.indexNext) = (
                positionRouter.increaseRiskBufferFundPositionIndex(),
                positionRouter.increaseRiskBufferFundPositionIndexNext()
            );
            if (indexPerOperation.index != indexPerOperation.indexNext) {
                indexPerOperation.indexEnd = uint128(
                    Math.min(indexPerOperation.index + _max, indexPerOperation.indexNext)
                );
                uint128 index = indexPerOperation.index;
                while (index < indexPerOperation.indexEnd) {
                    IPositionRouter.IncreaseRiskBufferFundPositionRequest memory request = positionRouter
                        .increaseRiskBufferFundPositionRequests(index);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { index++; }
                }
            }
        }

        // scope for decrease risk buffer fund position
        {
            IndexPerOperation memory indexPerOperation = indexPerOperations[4];
            (indexPerOperation.index, indexPerOperation.indexNext) = (
                positionRouter.decreaseRiskBufferFundPositionIndex(),
                positionRouter.decreaseRiskBufferFundPositionIndexNext()
            );
            if (indexPerOperation.index != indexPerOperation.indexNext) {
                indexPerOperation.indexEnd = uint128(
                    Math.min(indexPerOperation.index + _max, indexPerOperation.indexNext)
                );
                uint128 index = indexPerOperation.index;
                while (index < indexPerOperation.indexEnd) {
                    IPositionRouter.DecreaseRiskBufferFundPositionRequest memory request = positionRouter
                        .decreaseRiskBufferFundPositionRequests(index);
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { index++; }
                }
            }
        }

        // scope for increase position
        {
            IndexPerOperation memory indexPerOperation = indexPerOperations[5];
            (indexPerOperation.index, indexPerOperation.indexNext) = (
                positionRouter.increasePositionIndex(),
                positionRouter.increasePositionIndexNext()
            );
            if (indexPerOperation.index != indexPerOperation.indexNext) {
                indexPerOperation.indexEnd = uint128(
                    Math.min(indexPerOperation.index + _max, indexPerOperation.indexNext)
                );
                uint128 index = indexPerOperation.index;
                while (index < indexPerOperation.indexEnd) {
                    IPositionRouter.IncreasePositionRequest memory request = positionRouter.increasePositionRequests(
                        index
                    );
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { index++; }
                }
            }
        }

        // scope for decrease position
        {
            IndexPerOperation memory indexPerOperation = indexPerOperations[6];
            (indexPerOperation.index, indexPerOperation.indexNext) = (
                positionRouter.decreasePositionIndex(),
                positionRouter.decreasePositionIndexNext()
            );
            if (indexPerOperation.index != indexPerOperation.indexNext) {
                indexPerOperation.indexEnd = uint128(
                    Math.min(indexPerOperation.index + _max, indexPerOperation.indexNext)
                );
                uint128 index = indexPerOperation.index;
                while (index < indexPerOperation.indexEnd) {
                    IPositionRouter.DecreasePositionRequest memory request = positionRouter.decreasePositionRequests(
                        index
                    );
                    if (request.account != address(0)) pools[poolIndex++] = request.pool;

                    // prettier-ignore
                    unchecked { index++; }
                }
            }
        }
        uint dropNum = pools.length - poolIndex;
        // prettier-ignore
        assembly { mstore(pools, sub(mload(pools), dropNum)) }
    }
}
