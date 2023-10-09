// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./Router.sol";
import "./interfaces/ILiquidator.sol";
import "../core/interfaces/IPoolFactory.sol";
import "../libraries/PositionUtil.sol";
import {M as Math} from "../libraries/Math.sol";

contract Liquidator is ILiquidator, Governable {
    using SafeERC20 for IERC20;

    Router public immutable router;
    IPoolFactory public immutable poolFactory;
    IERC20 public immutable usd;
    IEFC public immutable EFC;

    IPriceFeed public priceFeed;

    mapping(address => bool) public executors;

    constructor(Router _router, IPoolFactory _poolFactory, IERC20 _usd, IEFC _efc) {
        (router, poolFactory, usd, EFC, priceFeed) = (_router, _poolFactory, _usd, _efc, _poolFactory.priceFeed());
    }

    /// @inheritdoc ILiquidator
    function updatePriceFeed() external override onlyGov {
        priceFeed = poolFactory.priceFeed();
    }

    /// @inheritdoc ILiquidator
    function updateExecutor(address _account, bool _active) external override onlyGov {
        executors[_account] = _active;
        emit ExecutorUpdated(_account, _active);
    }

    /// @inheritdoc ILiquidator
    function liquidateLiquidityPosition(IPool _pool, uint96 _positionID, address _feeReceiver) external override {
        _onlyExecutor();

        _pool.liquidateLiquidityPosition(_positionID, _feeReceiver);
    }

    /// @inheritdoc ILiquidator
    function liquidatePosition(IPool _pool, address _account, Side _side, address _feeReceiver) external override {
        _onlyExecutor();

        IERC20 token = _pool.token();
        uint160 decreaseIndexPriceX96 = _chooseIndexPriceX96(token, _side.flip());
        (uint128 margin, uint128 size, uint160 entryPriceX96, int192 entryFundingRateGrowthX96) = _pool.positions(
            _account,
            _side
        );

        // Fast path, if the position is empty or there is no unrealized profit in the position,
        // liquidate the position directly

        if (size == 0 || !_hasUnrealizedProfit(_side, entryPriceX96, decreaseIndexPriceX96)) {
            _pool.liquidatePosition(_account, _side, _feeReceiver);
            return;
        }

        // Slow path, if the position has unrealized profit, there is a possibility of liquidating
        // the position due to funding fee.
        // Therefore, attempt to close the position, if the closing fails, then liquidate the position directly

        _pool.sampleAndAdjustFundingRate();

        // Before closing, MUST verify that the position meets the liquidation conditions
        int256 fundingFee = PositionUtil.calculateFundingFee(
            _chooseFundingRateGrowthX96(_pool, _side),
            entryFundingRateGrowthX96,
            size
        );
        uint64 liquidationExecutionFee = _requireLiquidatable(
            token,
            _account,
            int256(uint256(margin)) + fundingFee,
            _side,
            size,
            entryPriceX96,
            decreaseIndexPriceX96
        );

        try router.pluginClosePositionByLiquidator(_pool, _account, _side, size, address(this)) {
            // If the closing succeeds, transfer the liquidation execution fee to the fee receiver
            uint256 balance = usd.balanceOf(address(this));
            uint256 balanceRemaining;

            unchecked {
                (liquidationExecutionFee, balanceRemaining) = balance >= liquidationExecutionFee
                    ? (liquidationExecutionFee, balance - liquidationExecutionFee)
                    : (uint64(balance), 0);
            }

            usd.safeTransfer(_feeReceiver, liquidationExecutionFee);
            if (balanceRemaining > 0) usd.safeTransfer(_account, balanceRemaining);

            emit PositionClosedByLiquidator(_pool, _account, _side, liquidationExecutionFee);
        } catch {
            _pool.liquidatePosition(_account, _side, _feeReceiver);
        }
    }

    function _onlyExecutor() private view {
        if (!executors[msg.sender]) revert Forbidden();
    }

    function _hasUnrealizedProfit(
        Side _side,
        uint160 _entryPriceX96,
        uint160 _indexPriceX96
    ) private pure returns (bool) {
        return _side.isLong() ? _indexPriceX96 > _entryPriceX96 : _indexPriceX96 < _entryPriceX96;
    }

    function _chooseIndexPriceX96(IERC20 _token, Side _side) private view returns (uint160) {
        return _side.isLong() ? priceFeed.getMaxPriceX96(_token) : priceFeed.getMinPriceX96(_token);
    }

    function _chooseFundingRateGrowthX96(IPool _pool, Side _side) private view returns (int192) {
        (, , int192 longFundingRateGrowthX96, int192 shortFundingRateGrowthX96) = _pool.globalPosition();
        return _side.isLong() ? longFundingRateGrowthX96 : shortFundingRateGrowthX96;
    }

    /// @dev The function is similar to `Pool#_validatePositionLiquidateMaintainMarginRate`
    function _requireLiquidatable(
        IERC20 _token,
        address _account,
        int256 _margin,
        Side _side,
        uint128 _size,
        uint160 _entryPriceX96,
        uint160 _decreasePriceX96
    ) private view returns (uint64 liquidationExecutionFee) {
        int256 unrealizedPnL = PositionUtil.calculateUnrealizedPnL(_side, _size, _entryPriceX96, _decreasePriceX96);

        (uint32 tradingFeeRate, , , , , uint32 referralDiscountRate) = poolFactory.tokenFeeRateConfigs(_token);
        (uint256 referralToken, ) = EFC.referrerTokens(_account);
        if (referralToken > 0)
            tradingFeeRate = uint32(
                Math.mulDivUp(tradingFeeRate, referralDiscountRate, Constants.BASIS_POINTS_DIVISOR)
            );

        uint32 liquidationFeeRatePerPosition;
        (, , , , , liquidationFeeRatePerPosition, liquidationExecutionFee, , ) = poolFactory.tokenConfigs(_token);
        uint256 maintenanceMargin = PositionUtil.calculateMaintenanceMargin(
            _size,
            _entryPriceX96,
            _decreasePriceX96,
            liquidationFeeRatePerPosition,
            tradingFeeRate,
            liquidationExecutionFee
        );

        int256 marginAfter = _margin + unrealizedPnL;
        if (_margin > 0 && marginAfter > 0 && maintenanceMargin < uint256(marginAfter))
            revert IPoolErrors.MarginRateTooLow(_margin, unrealizedPnL, maintenanceMargin);
    }
}
