// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../libraries/PoolUtil.sol";
import "../libraries/PriceUtil.sol";
import "../libraries/FundingRateUtil.sol";
import "../libraries/ReentrancyGuard.sol";

contract Pool is IPool, ReentrancyGuard {
    using SafeCast for *;
    using SafeERC20 for IERC20;

    struct TradingFeeState {
        uint32 tradingFeeRate;
        uint32 referralReturnFeeRate;
        uint32 referralParentReturnFeeRate;
        uint256 referralToken;
        uint256 referralParentToken;
    }

    IPoolFactory private immutable poolFactory;
    Router private immutable router;

    IFeeDistributor private immutable feeDistributor;
    IEFC private immutable EFC;
    IRewardFarmCallback private immutable callback;

    IPriceFeed public priceFeed;
    /// @dev The serial number of the next liquidity position, starting from 1
    uint96 private liquidityPositionIDNext;
    /// @inheritdoc IPool
    IERC20 public immutable override token;
    IERC20 private immutable usd;

    IConfigurable.TokenConfig private tokenConfig;
    IConfigurable.TokenFeeRateConfig private tokenFeeRateConfig;
    PriceState private priceState0;

    uint128 public usdBalance;
    /// @inheritdoc IPool
    uint128 public override protocolFee;
    /// @inheritdoc IPool
    mapping(uint256 => uint256) public override referralFees;

    // ==================== Liquidity Position Stats ====================

    /// @inheritdoc IPoolLiquidityPosition
    GlobalLiquidityPosition public override globalLiquidityPosition;
    /// @inheritdoc IPoolLiquidityPosition
    GlobalUnrealizedLossMetrics public override globalUnrealizedLossMetrics;
    /// @inheritdoc IPoolLiquidityPosition
    mapping(uint96 => LiquidityPosition) public override liquidityPositions;

    // ==================== Risk Buffer Fund Position Stats =============

    /// @inheritdoc IPoolLiquidityPosition
    GlobalRiskBufferFund public override globalRiskBufferFund;
    /// @inheritdoc IPoolLiquidityPosition
    mapping(address => RiskBufferFundPosition) public override riskBufferFundPositions;

    // ==================== Position Stats ==============================

    /// @inheritdoc IPoolPosition
    GlobalPosition public override globalPosition;
    /// @inheritdoc IPoolPosition
    PreviousGlobalFundingRate public override previousGlobalFundingRate;
    /// @inheritdoc IPoolPosition
    GlobalFundingRateSample public override globalFundingRateSample;
    /// @inheritdoc IPoolPosition
    mapping(address => mapping(Side => Position)) public override positions;

    constructor() {
        poolFactory = IPoolFactory(msg.sender);
        (token, usd, router, feeDistributor, EFC, callback) = poolFactory.deployParameters();
        priceFeed = poolFactory.priceFeed();

        PoolUtil.changeTokenConfig(tokenConfig, tokenFeeRateConfig, priceState0, poolFactory, token);

        globalFundingRateSample.lastAdjustFundingRateTime = _calculateFundingRateTime(_blockTimestamp());
    }

    // ==================== Liquidity Position Methods ====================

    /// @inheritdoc IPoolLiquidityPosition
    function liquidityPositionAccount(uint96 _positionID) external view override returns (address account) {
        return liquidityPositions[_positionID].account;
    }

    /// @inheritdoc IPoolLiquidityPosition
    function openLiquidityPosition(
        address _account,
        uint128 _margin,
        uint128 _liquidity
    ) external override nonReentrant returns (uint96 positionID) {
        _onlyRouter();

        _sampleAndAdjustFundingRate();

        if (_liquidity == 0) revert InvalidLiquidityToOpen();

        _validateMargin(_margin, tokenConfig.minMarginPerLiquidityPosition);
        _validateLeverage(_margin, _liquidity, tokenConfig.maxLeveragePerLiquidityPosition);
        _validateTransferInAndUpdateBalance(_margin);

        GlobalLiquidityPosition memory globalPositionCache = globalLiquidityPosition;
        // prettier-ignore
        (
            uint64 blockTimestamp,
            uint256 unrealizedLoss,
            /* GlobalUnrealizedLossMetrics memory globalMetricsCache */
        ) = _updateUnrealizedLossMetrics(globalPositionCache, int256(uint256(_liquidity)));

        // Update global liquidity position
        globalLiquidityPosition.liquidity = globalPositionCache.liquidity + _liquidity;

        positionID = ++liquidityPositionIDNext;
        liquidityPositions[positionID] = LiquidityPosition({
            margin: _margin,
            liquidity: _liquidity,
            entryUnrealizedLoss: unrealizedLoss,
            entryRealizedProfitGrowthX64: globalPositionCache.realizedProfitGrowthX64,
            entryTime: blockTimestamp,
            account: _account
        });

        emit LiquidityPositionOpened(
            _account,
            positionID,
            _margin,
            _liquidity,
            unrealizedLoss,
            globalPositionCache.realizedProfitGrowthX64
        );

        _changePriceVertices();

        // callback for reward farm
        callback.onLiquidityPositionChanged(_account, int256(uint256(_liquidity)));
    }

    /// @inheritdoc IPoolLiquidityPosition
    function closeLiquidityPosition(uint96 _positionID, address _receiver) external override nonReentrant {
        _onlyRouter();
        _validateLiquidityPosition(_positionID);

        _sampleAndAdjustFundingRate();

        GlobalLiquidityPosition memory globalPositionCache = globalLiquidityPosition;
        LiquidityPosition memory positionCache = liquidityPositions[_positionID];

        if (
            globalPositionCache.liquidity == positionCache.liquidity &&
            (globalPositionCache.netSize | globalPositionCache.liquidationBufferNetSize) > 0
        ) revert LastLiquidityPositionCannotBeClosed();

        (
            uint64 blockTimestamp,
            uint256 unrealizedLoss,
            GlobalUnrealizedLossMetrics memory globalMetricsCache
        ) = _updateUnrealizedLossMetrics(globalPositionCache, 0);

        uint256 positionRealizedProfit = LiquidityPositionUtil.calculateRealizedProfit(
            positionCache,
            globalPositionCache
        );
        uint256 marginAfter = positionCache.margin + positionRealizedProfit;

        uint128 positionUnrealizedLoss = LiquidityPositionUtil.calculatePositionUnrealizedLoss(
            positionCache,
            globalMetricsCache,
            globalPositionCache.liquidity,
            unrealizedLoss
        );

        uint64 liquidationExecutionFee = tokenConfig.liquidationExecutionFee;
        _validateLiquidityPositionRiskRate(marginAfter, liquidationExecutionFee, positionUnrealizedLoss, false);

        LiquidityPositionUtil.updateUnrealizedLossMetrics(
            globalUnrealizedLossMetrics,
            unrealizedLoss,
            blockTimestamp,
            -int256(uint256(positionCache.liquidity)),
            positionCache.entryTime,
            positionCache.entryUnrealizedLoss
        );
        _emitGlobalUnrealizedLossMetricsChangedEvent();

        unchecked {
            // never underflow because of the validation above
            marginAfter -= positionUnrealizedLoss;
            _transferOutAndUpdateBalance(_receiver, marginAfter);

            // Update global liquidity position
            globalLiquidityPosition.liquidity = globalPositionCache.liquidity - positionCache.liquidity;
        }

        int256 riskBufferFundAfter = globalRiskBufferFund.riskBufferFund + int256(uint256(positionUnrealizedLoss));
        globalRiskBufferFund.riskBufferFund = riskBufferFundAfter;
        emit GlobalRiskBufferFundChanged(riskBufferFundAfter);

        delete liquidityPositions[_positionID];

        emit LiquidityPositionClosed(
            _positionID,
            marginAfter.toUint128(),
            positionUnrealizedLoss,
            positionRealizedProfit,
            _receiver
        );

        _changePriceVertices();

        // callback for reward farm
        callback.onLiquidityPositionChanged(positionCache.account, -int256(uint256(positionCache.liquidity)));
    }

    /// @inheritdoc IPoolLiquidityPosition
    function adjustLiquidityPositionMargin(
        uint96 _positionID,
        int128 _marginDelta,
        address _receiver
    ) external override nonReentrant {
        _onlyRouter();
        _validateLiquidityPosition(_positionID);

        _sampleAndAdjustFundingRate();

        if (_marginDelta > 0) _validateTransferInAndUpdateBalance(uint128(_marginDelta));

        GlobalLiquidityPosition memory globalPositionCache = globalLiquidityPosition;
        // prettier-ignore
        (
            /* uint64 blockTimestamp */,
            uint256 unrealizedLoss,
            GlobalUnrealizedLossMetrics memory globalMetricsCache
        ) = _updateUnrealizedLossMetrics(globalPositionCache, 0);

        LiquidityPosition memory positionCache = liquidityPositions[_positionID];
        uint256 positionRealizedProfit = LiquidityPositionUtil.calculateRealizedProfit(
            positionCache,
            globalPositionCache
        );
        uint256 marginAfter = positionCache.margin + positionRealizedProfit;
        if (_marginDelta >= 0) {
            marginAfter += uint128(_marginDelta);
        } else {
            // If marginDelta is equal to type(int128).min, it will revert here
            if (marginAfter < uint128(-_marginDelta)) revert InsufficientMargin();
            // prettier-ignore
            unchecked { marginAfter -= uint128(-_marginDelta); }
        }

        uint64 liquidationExecutionFee = tokenConfig.liquidationExecutionFee;
        uint128 positionUnrealizedLoss = LiquidityPositionUtil.calculatePositionUnrealizedLoss(
            positionCache,
            globalMetricsCache,
            globalPositionCache.liquidity,
            unrealizedLoss
        );
        _validateLiquidityPositionRiskRate(marginAfter, liquidationExecutionFee, positionUnrealizedLoss, false);

        if (_marginDelta < 0) {
            _validateLeverage(marginAfter, positionCache.liquidity, tokenConfig.maxLeveragePerLiquidityPosition);
            _transferOutAndUpdateBalance(_receiver, uint128(-_marginDelta));
        }

        // Update position
        LiquidityPosition storage position = liquidityPositions[_positionID];
        position.margin = marginAfter.toUint128();
        position.entryRealizedProfitGrowthX64 = globalPositionCache.realizedProfitGrowthX64;

        emit LiquidityPositionMarginAdjusted(
            _positionID,
            _marginDelta,
            marginAfter.toUint128(),
            globalPositionCache.realizedProfitGrowthX64,
            _receiver
        );
    }

    /// @inheritdoc IPoolLiquidityPosition
    function liquidateLiquidityPosition(uint96 _positionID, address _feeReceiver) external override nonReentrant {
        _onlyLiquidityPositionLiquidator();

        _validateLiquidityPosition(_positionID);

        _sampleAndAdjustFundingRate();

        GlobalLiquidityPosition memory globalPositionCache = globalLiquidityPosition;
        // prettier-ignore
        (
            uint64 blockTimestamp,
            uint256 unrealizedLoss,
            GlobalUnrealizedLossMetrics memory globalMetricsCache
        ) = _updateUnrealizedLossMetrics(globalPositionCache, 0);

        LiquidityPosition memory positionCache = liquidityPositions[_positionID];

        uint256 positionRealizedProfit = LiquidityPositionUtil.calculateRealizedProfit(
            positionCache,
            globalPositionCache
        );
        uint256 marginAfter = positionCache.margin + positionRealizedProfit;

        uint128 positionUnrealizedLoss = LiquidityPositionUtil.calculatePositionUnrealizedLoss(
            positionCache,
            globalMetricsCache,
            globalPositionCache.liquidity,
            unrealizedLoss
        );
        uint64 liquidationExecutionFee = tokenConfig.liquidationExecutionFee;
        _validateLiquidityPositionRiskRate(marginAfter, liquidationExecutionFee, positionUnrealizedLoss, true);

        unchecked {
            if (marginAfter < liquidationExecutionFee) {
                liquidationExecutionFee = uint64(marginAfter);
                marginAfter = 0;
            } else marginAfter -= liquidationExecutionFee;
            _transferOutAndUpdateBalance(_feeReceiver, liquidationExecutionFee);
        }

        LiquidityPositionUtil.updateUnrealizedLossMetrics(
            globalUnrealizedLossMetrics,
            unrealizedLoss,
            blockTimestamp,
            -int256(uint256(positionCache.liquidity)),
            positionCache.entryTime,
            positionCache.entryUnrealizedLoss
        );
        _emitGlobalUnrealizedLossMetricsChangedEvent();

        // Update global liquidity position
        // prettier-ignore
        unchecked { globalLiquidityPosition.liquidity = globalPositionCache.liquidity - positionCache.liquidity; }

        int256 riskBufferFundAfter = globalRiskBufferFund.riskBufferFund + marginAfter.toInt256();
        globalRiskBufferFund.riskBufferFund = riskBufferFundAfter;
        emit GlobalRiskBufferFundChanged(riskBufferFundAfter);

        delete liquidityPositions[_positionID];

        emit LiquidityPositionLiquidated(
            msg.sender,
            _positionID,
            positionRealizedProfit,
            marginAfter,
            liquidationExecutionFee,
            _feeReceiver
        );

        _changePriceVertices();

        // callback for reward farm
        callback.onLiquidityPositionChanged(positionCache.account, -int256(uint256(positionCache.liquidity)));
    }

    /// @inheritdoc IPoolLiquidityPosition
    function govUseRiskBufferFund(address _receiver, uint128 _riskBufferFundDelta) external override nonReentrant {
        if (msg.sender != poolFactory.gov()) revert InvalidCaller(poolFactory.gov());

        _sampleAndAdjustFundingRate();

        _updateUnrealizedLossMetrics(globalLiquidityPosition, 0);

        int256 riskBufferFundAfter = LiquidityPositionUtil.govUseRiskBufferFund(
            globalLiquidityPosition,
            globalRiskBufferFund,
            _chooseIndexPriceX96(globalLiquidityPosition.side),
            _riskBufferFundDelta
        );
        _transferOutAndUpdateBalance(_receiver, _riskBufferFundDelta);
        emit GlobalRiskBufferFundGovUsed(_receiver, _riskBufferFundDelta);
        emit GlobalRiskBufferFundChanged(riskBufferFundAfter);
    }

    /// @inheritdoc IPoolLiquidityPosition
    function increaseRiskBufferFundPosition(address _account, uint128 _liquidityDelta) external override nonReentrant {
        _onlyRouter();

        _sampleAndAdjustFundingRate();

        _validateTransferInAndUpdateBalance(_liquidityDelta);

        _updateUnrealizedLossMetrics(globalLiquidityPosition, 0);

        (uint128 positionLiquidityAfter, uint64 unlockTimeAfter, int256 riskBufferFundAfter) = LiquidityPositionUtil
            .increaseRiskBufferFundPosition(globalRiskBufferFund, riskBufferFundPositions, _account, _liquidityDelta);

        emit RiskBufferFundPositionIncreased(_account, positionLiquidityAfter, unlockTimeAfter);
        emit GlobalRiskBufferFundChanged(riskBufferFundAfter);

        // callback for reward farm
        callback.onRiskBufferFundPositionChanged(_account, positionLiquidityAfter);
    }

    /// @inheritdoc IPoolLiquidityPosition
    function decreaseRiskBufferFundPosition(
        address _account,
        uint128 _liquidityDelta,
        address _receiver
    ) external override nonReentrant {
        _onlyRouter();

        _sampleAndAdjustFundingRate();

        _updateUnrealizedLossMetrics(globalLiquidityPosition, 0);

        (uint128 positionLiquidityAfter, int256 riskBufferFundAfter) = LiquidityPositionUtil
            .decreaseRiskBufferFundPosition(
                globalLiquidityPosition,
                globalRiskBufferFund,
                riskBufferFundPositions,
                _chooseIndexPriceX96(globalLiquidityPosition.side),
                _account,
                _liquidityDelta
            );
        _transferOutAndUpdateBalance(_receiver, _liquidityDelta);

        emit RiskBufferFundPositionDecreased(_account, positionLiquidityAfter, _receiver);
        emit GlobalRiskBufferFundChanged(riskBufferFundAfter);

        // callback for reward farm
        callback.onRiskBufferFundPositionChanged(_account, positionLiquidityAfter);
    }

    // ==================== Position Methods ====================

    /// @inheritdoc IPoolPosition
    function increasePosition(
        address _account,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta
    ) external override nonReentrant returns (uint160 tradePriceX96) {
        _side.requireValid();
        _onlyRouter();

        _sampleAndAdjustFundingRate();

        Position memory positionCache = positions[_account][_side];
        if (positionCache.size == 0) {
            if (_sizeDelta == 0) revert PositionNotFound(_account, _side);

            _validateMargin(_marginDelta, tokenConfig.minMarginPerPosition);
        }

        if (_marginDelta > 0) _validateTransferInAndUpdateBalance(_marginDelta);

        GlobalLiquidityPosition memory globalLiquidityPositionCache = globalLiquidityPosition;
        _validateGlobalLiquidity(globalLiquidityPositionCache.liquidity);

        _updateUnrealizedLossMetrics(globalLiquidityPositionCache, 0);

        uint128 tradingFee;
        TradingFeeState memory tradingFeeState = _buildTradingFeeState(_account);
        if (_sizeDelta > 0) {
            tradePriceX96 = PriceUtil.updatePriceState(
                globalLiquidityPosition,
                priceState0,
                _side,
                _sizeDelta,
                _chooseIndexPriceX96(_side),
                false
            );

            tradingFee = _adjustGlobalLiquidityPosition(
                globalLiquidityPositionCache,
                tradingFeeState,
                _account,
                _side,
                tradePriceX96,
                _sizeDelta,
                0
            );
        }

        int192 globalFundingRateGrowthX96 = PositionUtil.chooseFundingRateGrowthX96(globalPosition, _side);
        int256 fundingFee = PositionUtil.calculateFundingFee(
            globalFundingRateGrowthX96,
            positionCache.entryFundingRateGrowthX96,
            positionCache.size
        );

        int256 marginAfter = int256(uint256(positionCache.margin) + _marginDelta);
        marginAfter += fundingFee - int256(uint256(tradingFee));

        uint160 entryPriceAfterX96 = PositionUtil.calculateNextEntryPriceX96(
            _side,
            positionCache.size,
            positionCache.entryPriceX96,
            _sizeDelta,
            tradePriceX96
        );
        uint128 sizeAfter = positionCache.size + _sizeDelta;

        _validatePositionLiquidateMaintainMarginRate(
            marginAfter,
            _side,
            sizeAfter,
            entryPriceAfterX96,
            _chooseIndexPriceX96(_side.flip()), // Use the closing price to validate the margin rate
            tradingFeeState.tradingFeeRate,
            false
        );
        uint128 marginAfterUint128 = uint256(marginAfter).toUint128();

        if (_sizeDelta > 0) {
            _validateLeverage(
                marginAfterUint128,
                PositionUtil.calculateLiquidity(sizeAfter, entryPriceAfterX96),
                tokenConfig.maxLeveragePerPosition
            );
            _increaseGlobalPosition(_side, _sizeDelta);
        }

        Position storage position = positions[_account][_side];
        position.margin = marginAfterUint128;
        position.size = sizeAfter;
        position.entryPriceX96 = entryPriceAfterX96;
        position.entryFundingRateGrowthX96 = globalFundingRateGrowthX96;
        emit PositionIncreased(
            _account,
            _side,
            _marginDelta,
            marginAfterUint128,
            sizeAfter,
            tradePriceX96,
            entryPriceAfterX96,
            fundingFee,
            tradingFee
        );

        // callback for reward farm
        callback.onPositionChanged(_account, _side, sizeAfter, entryPriceAfterX96);
    }

    /// @inheritdoc IPoolPosition
    function decreasePosition(
        address _account,
        Side _side,
        uint128 _marginDelta,
        uint128 _sizeDelta,
        address _receiver
    ) external override nonReentrant returns (uint160 tradePriceX96) {
        _onlyRouter();

        _sampleAndAdjustFundingRate();

        Position memory positionCache = positions[_account][_side];
        if (positionCache.size == 0) revert PositionNotFound(_account, _side);

        if (positionCache.size < _sizeDelta) revert InsufficientSizeToDecrease(positionCache.size, _sizeDelta);

        GlobalLiquidityPosition memory globalLiquidityPositionCache = globalLiquidityPosition;
        _validateGlobalLiquidity(globalLiquidityPositionCache.liquidity);

        _updateUnrealizedLossMetrics(globalLiquidityPositionCache, 0);

        uint160 decreaseIndexPriceX96 = _chooseIndexPriceX96(_side.flip());

        uint128 tradingFee;
        uint128 sizeAfter = positionCache.size;
        int256 realizedPnLDelta;
        TradingFeeState memory tradingFeeState = _buildTradingFeeState(_account);
        if (_sizeDelta > 0) {
            // never underflow because of the validation above
            // prettier-ignore
            unchecked { sizeAfter = positionCache.size - _sizeDelta; }

            tradePriceX96 = PriceUtil.updatePriceState(
                globalLiquidityPosition,
                priceState0,
                _side.flip(),
                _sizeDelta,
                decreaseIndexPriceX96,
                false
            );

            tradingFee = _adjustGlobalLiquidityPosition(
                globalLiquidityPositionCache,
                tradingFeeState,
                _account,
                _side.flip(),
                tradePriceX96,
                _sizeDelta,
                0
            );
            realizedPnLDelta = PositionUtil.calculateUnrealizedPnL(
                _side,
                _sizeDelta,
                positionCache.entryPriceX96,
                tradePriceX96
            );
        }

        int192 globalFundingRateGrowthX96 = PositionUtil.chooseFundingRateGrowthX96(globalPosition, _side);
        int256 fundingFee = PositionUtil.calculateFundingFee(
            globalFundingRateGrowthX96,
            positionCache.entryFundingRateGrowthX96,
            positionCache.size
        );

        int256 marginAfter = int256(uint256(positionCache.margin));
        marginAfter += realizedPnLDelta + fundingFee - int256(uint256(tradingFee) + _marginDelta);
        if (marginAfter < 0) revert InsufficientMargin();

        uint128 marginAfterUint128 = uint256(marginAfter).toUint128();
        if (sizeAfter > 0) {
            _validatePositionLiquidateMaintainMarginRate(
                marginAfter,
                _side,
                sizeAfter,
                positionCache.entryPriceX96,
                decreaseIndexPriceX96,
                tradingFeeState.tradingFeeRate,
                false
            );
            if (_marginDelta > 0)
                _validateLeverage(
                    marginAfterUint128,
                    PositionUtil.calculateLiquidity(sizeAfter, positionCache.entryPriceX96),
                    tokenConfig.maxLeveragePerPosition
                );

            // Update position
            Position storage position = positions[_account][_side];
            position.margin = marginAfterUint128;
            position.size = sizeAfter;
            position.entryFundingRateGrowthX96 = globalFundingRateGrowthX96;
        } else {
            // If the position is closed, the marginDelta needs to be added back to ensure that the
            // remaining margin of the position is 0.
            _marginDelta += marginAfterUint128;
            marginAfterUint128 = 0;

            // Delete position
            delete positions[_account][_side];
        }

        if (_marginDelta > 0) _transferOutAndUpdateBalance(_receiver, _marginDelta);

        if (_sizeDelta > 0) _decreaseGlobalPosition(_side, _sizeDelta);

        emit PositionDecreased(
            _account,
            _side,
            _marginDelta,
            marginAfterUint128,
            sizeAfter,
            tradePriceX96,
            realizedPnLDelta,
            fundingFee,
            tradingFee,
            _receiver
        );

        // callback for reward farm
        callback.onPositionChanged(_account, _side, sizeAfter, positionCache.entryPriceX96);
    }

    /// @inheritdoc IPoolPosition
    function liquidatePosition(address _account, Side _side, address _feeReceiver) external override nonReentrant {
        _onlyPositionLiquidator();

        _sampleAndAdjustFundingRate();

        Position memory positionCache = positions[_account][_side];
        if (positionCache.size == 0) revert PositionNotFound(_account, _side);

        GlobalLiquidityPosition memory globalLiquidityPositionCache = globalLiquidityPosition;
        _validateGlobalLiquidity(globalLiquidityPositionCache.liquidity);

        _updateUnrealizedLossMetrics(globalLiquidityPositionCache, 0);

        uint160 decreaseIndexPriceX96 = _chooseIndexPriceX96(_side.flip());

        TradingFeeState memory tradingFeeState = _buildTradingFeeState(_account);
        int256 requiredFundingFee = PositionUtil.calculateFundingFee(
            PositionUtil.chooseFundingRateGrowthX96(globalPosition, _side),
            positionCache.entryFundingRateGrowthX96,
            positionCache.size
        );

        _validatePositionLiquidateMaintainMarginRate(
            int256(uint256(positionCache.margin)) + requiredFundingFee,
            _side,
            positionCache.size,
            positionCache.entryPriceX96,
            decreaseIndexPriceX96,
            tradingFeeState.tradingFeeRate,
            true
        );

        // try to update price state
        PriceUtil.updatePriceState(
            globalLiquidityPosition,
            priceState0,
            _side.flip(),
            positionCache.size,
            decreaseIndexPriceX96,
            true
        );

        _liquidatePosition(
            globalLiquidityPositionCache,
            positionCache,
            tradingFeeState,
            _account,
            _side,
            decreaseIndexPriceX96,
            requiredFundingFee,
            _feeReceiver
        );

        // callback for reward farm
        callback.onPositionChanged(_account, _side, 0, 0);
    }

    /// @inheritdoc IPool
    function priceState()
        external
        view
        override
        returns (
            uint128 maxPriceImpactLiquidity,
            uint128 premiumRateX96,
            PriceVertex[7] memory priceVertices,
            uint8 pendingVertexIndex,
            uint8 liquidationVertexIndex,
            uint8 currentVertexIndex,
            uint128[7] memory liquidationBufferNetSizes
        )
    {
        return (
            priceState0.maxPriceImpactLiquidity,
            priceState0.premiumRateX96,
            priceState0.priceVertices,
            priceState0.pendingVertexIndex,
            priceState0.liquidationVertexIndex,
            priceState0.currentVertexIndex,
            priceState0.liquidationBufferNetSizes
        );
    }

    /// @inheritdoc IPool
    function marketPriceX96(Side _side) external view override returns (uint160 _marketPriceX96) {
        _marketPriceX96 = PriceUtil.calculateMarketPriceX96(
            globalLiquidityPosition.side,
            _side,
            _chooseIndexPriceX96(_side),
            priceState0.premiumRateX96
        );
    }

    /// @inheritdoc IPool
    /// @dev This function does not include the nonReentrant modifier because it is intended
    /// to be called internally by the contract itself.
    function changePriceVertex(uint8 _startExclusive, uint8 _endInclusive) external override {
        if (msg.sender != address(this)) revert InvalidCaller(address(this));

        unchecked {
            // If the vertex represented by end is the same as the vertex represented by end + 1,
            // then the vertices in the range (start, LATEST_VERTEX] need to be updated
            if (_endInclusive < Constants.LATEST_VERTEX) {
                PriceVertex memory previous = priceState0.priceVertices[_endInclusive];
                PriceVertex memory next = priceState0.priceVertices[_endInclusive + 1];
                if (previous.size >= next.size || previous.premiumRateX96 >= next.premiumRateX96)
                    _endInclusive = Constants.LATEST_VERTEX;
            }
        }

        _changePriceVertex(_startExclusive, _endInclusive);
    }

    /// @inheritdoc IPool
    function onChangeTokenConfig() external override nonReentrant {
        if (msg.sender != address(poolFactory)) revert InvalidCaller(address(poolFactory));

        _sampleAndAdjustFundingRate();

        _updateUnrealizedLossMetrics(globalLiquidityPosition, 0);

        PoolUtil.changeTokenConfig(tokenConfig, tokenFeeRateConfig, priceState0, poolFactory, token);

        _changePriceVertices();

        priceFeed = poolFactory.priceFeed();
    }

    /// @inheritdoc IPool
    function sampleAndAdjustFundingRate() external override nonReentrant {
        _sampleAndAdjustFundingRate();

        _updateUnrealizedLossMetrics(globalLiquidityPosition, 0);
    }

    /// @inheritdoc IPool
    function collectProtocolFee() external override nonReentrant {
        _sampleAndAdjustFundingRate();

        _updateUnrealizedLossMetrics(globalLiquidityPosition, 0);

        uint128 protocolFeeCopy = protocolFee;
        delete protocolFee;

        _transferOutAndUpdateBalance(address(feeDistributor), protocolFeeCopy);
        feeDistributor.depositFee(protocolFeeCopy);
        emit ProtocolFeeCollected(protocolFeeCopy);
    }

    /// @inheritdoc IPool
    function collectReferralFee(
        uint256 _referralToken,
        address _receiver
    ) external override nonReentrant returns (uint256 amount) {
        _onlyRouter();

        _sampleAndAdjustFundingRate();

        _updateUnrealizedLossMetrics(globalLiquidityPosition, 0);

        amount = referralFees[_referralToken];
        delete referralFees[_referralToken];

        _transferOutAndUpdateBalance(_receiver, amount);
        emit ReferralFeeCollected(_referralToken, _receiver, amount);
    }

    function _onlyRouter() private view {
        if (msg.sender != address(router)) revert InvalidCaller(address(router));
    }

    function _onlyLiquidityPositionLiquidator() private view {
        if (!poolFactory.hasRole(Constants.ROLE_LIQUIDITY_POSITION_LIQUIDATOR, msg.sender))
            revert CallerNotLiquidator();
    }

    function _onlyPositionLiquidator() private view {
        if (!poolFactory.hasRole(Constants.ROLE_POSITION_LIQUIDATOR, msg.sender)) revert CallerNotLiquidator();
    }

    function _validateTransferInAndUpdateBalance(uint128 _amount) private {
        uint128 balanceAfter = usd.balanceOf(address(this)).toUint128();
        if (balanceAfter - usdBalance < _amount) revert InsufficientBalance(usdBalance, _amount);
        usdBalance += _amount;
    }

    function _transferOutAndUpdateBalance(address _to, uint256 _amount) private {
        usdBalance = (usdBalance - _amount).toUint128();
        usd.safeTransfer(_to, _amount);
    }

    function _validateLeverage(uint256 _margin, uint128 _liquidity, uint32 _maxLeverage) private pure {
        if (_margin * _maxLeverage < _liquidity) revert LeverageTooHigh(_margin, _liquidity, _maxLeverage);
    }

    function _validateMargin(uint128 _margin, uint64 _minMargin) private pure {
        if (_margin < _minMargin) revert InsufficientMargin();
    }

    function _validateLiquidityPosition(uint96 _positionID) private view {
        if (liquidityPositions[_positionID].liquidity == 0) revert LiquidityPositionNotFound(_positionID);
    }

    /// @dev Validate the position risk rate
    /// @param _margin The margin of the position
    /// @param _liquidationExecutionFee The liquidation execution fee paid by the position
    /// @param _positionUnrealizedLoss The unrealized loss incurred by the position at the time of closing
    /// @param _liquidatablePosition Whether it is a liquidatable position, if true, the position must be liquidatable,
    /// otherwise the position must be non-liquidatable
    function _validateLiquidityPositionRiskRate(
        uint256 _margin,
        uint64 _liquidationExecutionFee,
        uint128 _positionUnrealizedLoss,
        bool _liquidatablePosition
    ) private view {
        unchecked {
            if (!_liquidatablePosition) {
                if (
                    _margin < (uint256(_liquidationExecutionFee) + _positionUnrealizedLoss) ||
                    Math.mulDiv(
                        _margin - _liquidationExecutionFee,
                        tokenConfig.maxRiskRatePerLiquidityPosition,
                        Constants.BASIS_POINTS_DIVISOR
                    ) <=
                    _positionUnrealizedLoss
                ) revert RiskRateTooHigh(_margin, _liquidationExecutionFee, _positionUnrealizedLoss);
            } else {
                if (
                    _margin > (uint256(_liquidationExecutionFee) + _positionUnrealizedLoss) &&
                    Math.mulDiv(
                        _margin - _liquidationExecutionFee,
                        tokenConfig.maxRiskRatePerLiquidityPosition,
                        Constants.BASIS_POINTS_DIVISOR
                    ) >
                    _positionUnrealizedLoss
                ) revert RiskRateTooLow(_margin, _liquidationExecutionFee, _positionUnrealizedLoss);
            }
        }
    }

    function _changePriceVertices() private {
        uint8 currentVertexIndex = priceState0.currentVertexIndex;
        priceState0.pendingVertexIndex = currentVertexIndex;

        _changePriceVertex(currentVertexIndex, Constants.LATEST_VERTEX);
    }

    /// @dev Change the price vertex
    /// @param _startExclusive The start index of the price vertex to be changed, exclusive
    /// @param _endInclusive The end index of the price vertex to be changed, inclusive
    function _changePriceVertex(uint8 _startExclusive, uint8 _endInclusive) private {
        uint160 indexPriceX96 = priceFeed.getMaxPriceX96(token);
        uint128 liquidity = uint128(Math.min(globalLiquidityPosition.liquidity, priceState0.maxPriceImpactLiquidity));

        unchecked {
            for (uint8 index = _startExclusive + 1; index <= _endInclusive; ++index) {
                (uint32 balanceRate, uint32 premiumRate) = poolFactory.tokenPriceVertexConfigs(token, index);
                (uint128 sizeAfter, uint128 premiumRateAfterX96) = _calculatePriceVertex(
                    balanceRate,
                    premiumRate,
                    liquidity,
                    indexPriceX96
                );
                if (index > 1) {
                    PriceVertex memory previous = priceState0.priceVertices[index - 1];
                    if (previous.size >= sizeAfter || previous.premiumRateX96 >= premiumRateAfterX96)
                        (sizeAfter, premiumRateAfterX96) = (previous.size, previous.premiumRateX96);
                }

                priceState0.priceVertices[index].size = sizeAfter;
                priceState0.priceVertices[index].premiumRateX96 = premiumRateAfterX96;
                emit PriceVertexChanged(index, sizeAfter, premiumRateAfterX96);

                // If the vertex represented by end is the same as the vertex represented by end + 1,
                // then the vertices in range (start, LATEST_VERTEX] need to be updated
                if (index == _endInclusive && _endInclusive < Constants.LATEST_VERTEX) {
                    PriceVertex memory next = priceState0.priceVertices[index + 1];
                    if (sizeAfter >= next.size || premiumRateAfterX96 >= next.premiumRateX96)
                        _endInclusive = Constants.LATEST_VERTEX;
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
        unchecked {
            uint256 balanceRateX96 = (Constants.Q96 * _balanceRate) / Constants.BASIS_POINTS_DIVISOR;
            size = Math.mulDiv(balanceRateX96, _liquidity, _indexPriceX96).toUint128();

            premiumRateX96 = uint128((Constants.Q96 * _premiumRate) / Constants.BASIS_POINTS_DIVISOR);
        }
    }

    function _updateUnrealizedLossMetrics(
        GlobalLiquidityPosition memory _globalPositionCache,
        int256 _liquidityDelta
    ) private returns (uint64 blockTimestamp, uint256 unrealizedLoss, GlobalUnrealizedLossMetrics memory metricsCache) {
        blockTimestamp = _blockTimestamp();
        unrealizedLoss = LiquidityPositionUtil.calculateUnrealizedLoss(
            _globalPositionCache.side,
            _globalPositionCache.netSize + _globalPositionCache.liquidationBufferNetSize,
            _globalPositionCache.entryPriceX96,
            _chooseIndexPriceX96(_globalPositionCache.side),
            globalRiskBufferFund.riskBufferFund
        );
        LiquidityPositionUtil.updateUnrealizedLossMetrics(
            globalUnrealizedLossMetrics,
            unrealizedLoss,
            blockTimestamp,
            _liquidityDelta,
            blockTimestamp,
            unrealizedLoss
        );

        metricsCache = _emitGlobalUnrealizedLossMetricsChangedEvent();
    }

    function _emitGlobalUnrealizedLossMetricsChangedEvent()
        private
        returns (GlobalUnrealizedLossMetrics memory metricsCache)
    {
        metricsCache = globalUnrealizedLossMetrics;
        emit GlobalUnrealizedLossMetricsChanged(
            metricsCache.lastZeroLossTime,
            metricsCache.liquidity,
            metricsCache.liquidityTimesUnrealizedLoss
        );
    }

    /// @dev Choose the index price function, which returns the maximum or minimum price index
    /// based on the given side (Long or Short)
    /// @param _side The side of the position, long for increasing long position or decreasing short position,
    /// short for increasing short position or decreasing long position
    function _chooseIndexPriceX96(Side _side) private view returns (uint160) {
        return _side.isLong() ? priceFeed.getMaxPriceX96(token) : priceFeed.getMinPriceX96(token);
    }

    function _calculateFundingRateTime(uint64 _timestamp) private pure returns (uint64) {
        // prettier-ignore
        unchecked { return _timestamp - (_timestamp % Constants.ADJUST_FUNDING_RATE_INTERVAL); }
    }

    /// @notice Validate the position has not reached the liquidation margin rate
    /// @param _margin The margin of the position
    /// @param _side The side of the position
    /// @param _size The size of the position
    /// @param _entryPriceX96 The entry price of the position, as a Q64.96
    /// @param _decreasePriceX96 The price at which the position is decreased, as a Q64.96
    /// @param _tradingFeeRate The trading fee rate for trader increase or decrease positions,
    /// denominated in ten thousandths of a bip (i.e. 1e-8)
    /// param _liquidatablePosition Whether it is a liquidatable position, if true, the position must be liquidatable,
    /// otherwise the position must be non-liquidatable
    function _validatePositionLiquidateMaintainMarginRate(
        int256 _margin,
        Side _side,
        uint128 _size,
        uint160 _entryPriceX96,
        uint160 _decreasePriceX96,
        uint32 _tradingFeeRate,
        bool _liquidatablePosition
    ) private view {
        int256 unrealizedPnL = PositionUtil.calculateUnrealizedPnL(_side, _size, _entryPriceX96, _decreasePriceX96);
        uint256 maintenanceMargin = PositionUtil.calculateMaintenanceMargin(
            _size,
            _entryPriceX96,
            _decreasePriceX96,
            tokenConfig.liquidationFeeRatePerPosition,
            _tradingFeeRate,
            tokenConfig.liquidationExecutionFee
        );
        int256 marginAfter = _margin + unrealizedPnL;
        if (!_liquidatablePosition) {
            if (_margin <= 0 || marginAfter <= 0 || maintenanceMargin >= uint256(marginAfter))
                revert MarginRateTooHigh(_margin, unrealizedPnL, maintenanceMargin);
        } else {
            if (_margin > 0 && marginAfter > 0 && maintenanceMargin < uint256(marginAfter))
                revert MarginRateTooLow(_margin, unrealizedPnL, maintenanceMargin);
        }
    }

    function _liquidatePosition(
        GlobalLiquidityPosition memory _globalLiquidityPositionCache,
        Position memory _positionCache,
        TradingFeeState memory _tradingFeeState,
        address _account,
        Side _side,
        uint160 decreaseIndexPriceX96,
        int256 requiredFundingFee,
        address _feeReceiver
    ) private {
        // transfer liquidation fee directly to fee receiver
        _transferOutAndUpdateBalance(_feeReceiver, tokenConfig.liquidationExecutionFee);

        (uint160 liquidationPriceX96, int256 adjustedFundingFee) = PositionUtil.calculateLiquidationPriceX96(
            _positionCache,
            previousGlobalFundingRate,
            _side,
            requiredFundingFee,
            tokenConfig.liquidationFeeRatePerPosition,
            _tradingFeeState.tradingFeeRate,
            tokenConfig.liquidationExecutionFee
        );

        uint128 liquidationFee = PositionUtil.calculateLiquidationFee(
            _positionCache.size,
            _positionCache.entryPriceX96,
            tokenConfig.liquidationFeeRatePerPosition
        );
        int256 riskBufferFundDelta = int256(uint256(liquidationFee));

        if (requiredFundingFee != adjustedFundingFee)
            riskBufferFundDelta += _adjustFundingRateByLiquidation(_side, requiredFundingFee, adjustedFundingFee);

        uint128 tradingFee = _adjustGlobalLiquidityPosition(
            _globalLiquidityPositionCache,
            _tradingFeeState,
            _account,
            _side.flip(),
            liquidationPriceX96,
            _positionCache.size,
            riskBufferFundDelta
        );

        _decreaseGlobalPosition(_side, _positionCache.size);

        delete positions[_account][_side];

        emit PositionLiquidated(
            msg.sender,
            _account,
            _side,
            decreaseIndexPriceX96,
            liquidationPriceX96,
            adjustedFundingFee,
            tradingFee,
            liquidationFee,
            tokenConfig.liquidationExecutionFee,
            _feeReceiver
        );
    }

    function _adjustGlobalLiquidityPosition(
        GlobalLiquidityPosition memory _positionCache,
        TradingFeeState memory _tradingFeeState,
        address _account,
        Side _side,
        uint160 _tradePriceX96,
        uint128 _sizeDelta,
        int256 _riskBufferFundDelta
    ) private returns (uint128 tradingFee) {
        (int256 realizedPnL, uint160 entryPriceAfterX96) = LiquidityPositionUtil
            .calculateRealizedPnLAndNextEntryPriceX96(_positionCache, _side, _tradePriceX96, _sizeDelta);

        globalLiquidityPosition.entryPriceX96 = entryPriceAfterX96;
        emit GlobalLiquidityPositionNetPositionAdjusted(
            globalLiquidityPosition.netSize,
            globalLiquidityPosition.liquidationBufferNetSize,
            entryPriceAfterX96,
            globalLiquidityPosition.side
        );

        uint128 liquidityFee;
        uint128 riskBufferFundFee;
        (tradingFee, liquidityFee, riskBufferFundFee) = _calculateFee(
            _tradingFeeState,
            _account,
            _sizeDelta,
            _tradePriceX96
        );

        int256 riskBufferFundRealizedPnLDelta = _riskBufferFundDelta + realizedPnL + riskBufferFundFee.toInt256();

        int256 riskBufferFundAfter = globalRiskBufferFund.riskBufferFund + riskBufferFundRealizedPnLDelta;
        globalRiskBufferFund.riskBufferFund = riskBufferFundAfter;
        emit GlobalRiskBufferFundChanged(riskBufferFundAfter);

        uint256 realizedProfitGrowthAfterX64 = _positionCache.realizedProfitGrowthX64 +
            (uint256(liquidityFee) << 64) /
            _positionCache.liquidity;
        globalLiquidityPosition.realizedProfitGrowthX64 = realizedProfitGrowthAfterX64;
        emit GlobalLiquidityPositionRealizedProfitGrowthChanged(realizedProfitGrowthAfterX64);
    }

    function _calculateFee(
        TradingFeeState memory _tradingFeeState,
        address _account,
        uint128 _sizeDelta,
        uint160 _tradePriceX96
    ) private returns (uint128 tradingFee, uint128 liquidityFee, uint128 riskBufferFundFee) {
        unchecked {
            tradingFee = PositionUtil.calculateTradingFee(_sizeDelta, _tradePriceX96, _tradingFeeState.tradingFeeRate);
            liquidityFee = _splitFee(tradingFee, tokenFeeRateConfig.liquidityFeeRate);

            uint128 _protocolFee = _splitFee(tradingFee, tokenFeeRateConfig.protocolFeeRate);
            protocolFee += _protocolFee; // overflow is desired
            emit ProtocolFeeIncreased(_protocolFee);

            riskBufferFundFee = tradingFee - liquidityFee - _protocolFee;

            if (_tradingFeeState.referralToken > 0) {
                uint128 referralFee = _splitFee(tradingFee, _tradingFeeState.referralReturnFeeRate);
                referralFees[_tradingFeeState.referralToken] += referralFee; // overflow is desired

                uint128 referralParentFee = _splitFee(tradingFee, _tradingFeeState.referralParentReturnFeeRate);
                referralFees[_tradingFeeState.referralParentToken] += referralParentFee; // overflow is desired

                emit ReferralFeeIncreased(
                    _account,
                    _tradingFeeState.referralToken,
                    referralFee,
                    _tradingFeeState.referralParentToken,
                    referralParentFee
                );

                riskBufferFundFee -= referralFee + referralParentFee;
            }
        }
    }

    function _splitFee(uint128 _tradingFee, uint32 _feeRate) private pure returns (uint128 amount) {
        // prettier-ignore
        unchecked { amount = uint128((uint256(_tradingFee) * _feeRate) / Constants.BASIS_POINTS_DIVISOR); }
    }

    function _buildTradingFeeState(address _account) private view returns (TradingFeeState memory state) {
        (state.referralToken, state.referralParentToken) = EFC.referrerTokens(_account);

        if (state.referralToken == 0) state.tradingFeeRate = tokenFeeRateConfig.tradingFeeRate;
        else {
            state.tradingFeeRate = uint32(
                Math.mulDivUp(
                    tokenFeeRateConfig.tradingFeeRate,
                    tokenFeeRateConfig.referralDiscountRate,
                    Constants.BASIS_POINTS_DIVISOR
                )
            );

            state.referralReturnFeeRate = tokenFeeRateConfig.referralReturnFeeRate;
            state.referralParentReturnFeeRate = tokenFeeRateConfig.referralParentReturnFeeRate;
        }
    }

    function _validateGlobalLiquidity(uint128 _globalLiquidity) private pure {
        if (_globalLiquidity == 0) revert InsufficientGlobalLiquidity();
    }

    function _increaseGlobalPosition(Side _side, uint128 _size) private {
        if (_side.isLong()) globalPosition.longSize += _size;
        else globalPosition.shortSize += _size;
    }

    function _decreaseGlobalPosition(Side _side, uint128 _size) private {
        unchecked {
            if (_side.isLong()) globalPosition.longSize -= _size;
            else globalPosition.shortSize -= _size;
        }
    }

    function _sampleAndAdjustFundingRate() private {
        (bool shouldAdjustFundingRate, int256 fundingRateDeltaX96) = FundingRateUtil.samplePremiumRate(
            globalFundingRateSample,
            globalLiquidityPosition,
            priceState0,
            tokenConfig.interestRate,
            _blockTimestamp()
        );

        if (shouldAdjustFundingRate) {
            GlobalPosition memory globalPositionCache = globalPosition;

            (int256 clampedDeltaX96, int192 longGrowthAfterX96, int192 shortGrowthAfterX96) = FundingRateUtil
                .calculateFundingRateGrowthX96(
                    globalRiskBufferFund,
                    globalPositionCache,
                    fundingRateDeltaX96,
                    tokenConfig.maxFundingRate,
                    priceFeed.getMaxPriceX96(token)
                );

            _snapshotAndAdjustGlobalFundingRate(
                globalPositionCache,
                clampedDeltaX96,
                longGrowthAfterX96,
                shortGrowthAfterX96
            );
        }
    }

    function _adjustFundingRateByLiquidation(
        Side _side,
        int256 _requiredFundingFee,
        int256 _adjustedFundingFee
    ) private returns (int256 riskBufferFundLoss) {
        int256 insufficientFundingFee = _adjustedFundingFee - _requiredFundingFee;
        GlobalPosition memory globalPositionCache = globalPosition;
        uint128 oppositeSize = _side.isLong() ? globalPositionCache.shortSize : globalPositionCache.longSize;
        if (oppositeSize > 0) {
            int192 insufficientFundingRateGrowthDeltaX96 = Math
                .mulDiv(uint256(insufficientFundingFee), Constants.Q96, oppositeSize)
                .toInt256()
                .toInt192();
            int192 longFundingRateGrowthAfterX96 = globalPositionCache.longFundingRateGrowthX96;
            int192 shortFundingRateGrowthAfterX96 = globalPositionCache.shortFundingRateGrowthX96;
            if (_side.isLong()) shortFundingRateGrowthAfterX96 -= insufficientFundingRateGrowthDeltaX96;
            else longFundingRateGrowthAfterX96 -= insufficientFundingRateGrowthDeltaX96;
            _snapshotAndAdjustGlobalFundingRate(
                globalPositionCache,
                0,
                longFundingRateGrowthAfterX96,
                shortFundingRateGrowthAfterX96
            );
        } else riskBufferFundLoss = -insufficientFundingFee;
    }

    function _snapshotAndAdjustGlobalFundingRate(
        GlobalPosition memory _positionCache,
        int256 _fundingRateDeltaX96,
        int192 _longFundingRateGrowthAfterX96,
        int192 _shortFundingRateGrowthAfterX96
    ) private {
        // snapshot previous global funding rate
        previousGlobalFundingRate.longFundingRateGrowthX96 = _positionCache.longFundingRateGrowthX96;
        previousGlobalFundingRate.shortFundingRateGrowthX96 = _positionCache.shortFundingRateGrowthX96;

        globalPosition.longFundingRateGrowthX96 = _longFundingRateGrowthAfterX96;
        globalPosition.shortFundingRateGrowthX96 = _shortFundingRateGrowthAfterX96;
        emit FundingRateGrowthAdjusted(
            _fundingRateDeltaX96,
            _longFundingRateGrowthAfterX96,
            _shortFundingRateGrowthAfterX96,
            globalFundingRateSample.lastAdjustFundingRateTime
        );
    }

    function _blockTimestamp() private view returns (uint64) {
        return block.timestamp.toUint64();
    }
}
