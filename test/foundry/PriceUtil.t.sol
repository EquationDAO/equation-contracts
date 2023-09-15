// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import "../../contracts/types/Side.sol";
import "../../contracts/libraries/SafeCast.sol";
import "../../contracts/libraries/PriceUtil.sol";

contract PriceUtilTest is Test {
    using SafeCast for *;

    uint160 indexPriceX96;
    IPool.PriceState priceState;
    IPool.GlobalLiquidityPosition globalPosition;

    struct CalculateAX96AndBX96Params {
        Side globalSide;
        IPool.PriceVertex from;
        IPool.PriceVertex to;
        uint256 aX96;
        int256 bX96;
    }

    struct CalculateReachedAndSizeUsedParams {
        bool improveBalance;
        uint128 sizeCurrent;
        uint128 sizeTo;
        uint128 sizeLeft;
        bool reached;
        uint256 sizeUsed;
    }

    struct CalculatePremiumRateAfterX96Params {
        IPool.PriceVertex from;
        IPool.PriceVertex to;
        Side side;
        bool improveBalance;
        uint128 sizeCurrent;
        bool reached;
        uint128 sizeUsed;
        int256 premiumRateAfterX96;
    }

    struct SimulateMoveParams {
        Side side;
        uint128 sizeLeft;
        uint160 indexPriceX96;
        bool improveBalance;
        IPool.PriceVertex from;
        IPool.PriceVertex current;
        IPool.PriceVertex to;
        uint160 tradePriceX96;
        uint128 sizeUsed;
        bool reached;
        int256 premiumRateAfterX96;
    }

    struct UpdatePriceStateCase {
        uint256 id;
        // inputs
        Side side;
        uint128 sizeDelta;
        // outputs
        Side globalSideExpect;
        uint160 tradePriceX96Expect;
        uint128 netSizeExpect;
        uint128 bufferSizeExpect;
        uint128 prX96Expect;
        uint8 pendingVertexIndexExpect;
        uint8 currentVertexIndexExpect;
    }

    function setUp() public {
        // eth-usdc, current price is 2000
        indexPriceX96 = Math.mulDiv(2000, Constants.Q96, 1e12).toUint160();

        globalPosition.liquidity = 3923892901;

        priceState.maxPriceImpactLiquidity = 1_000_000;
        priceState.liquidationVertexIndex = 4;
        priceState.priceVertices = [
            IPool.PriceVertex(0, 0),
            IPool.PriceVertex(39238929010000000, Math.mulDiv(5, Constants.Q96, 10000).toUint128()), // 0.05%
            IPool.PriceVertex(58858393515000000, Math.mulDiv(10, Constants.Q96, 10000).toUint128()), // 0.1%
            IPool.PriceVertex(78477858020000000, Math.mulDiv(15, Constants.Q96, 10000).toUint128()), // 0.15%
            IPool.PriceVertex(98097322525000000, Math.mulDiv(20, Constants.Q96, 10000).toUint128()), // 0.2%
            IPool.PriceVertex(196194645050000000, Math.mulDiv(100, Constants.Q96, 10000).toUint128()), // 1%
            IPool.PriceVertex(1961946450500000000, Math.mulDiv(2000, Constants.Q96, 10000).toUint128()) // 20%
        ];
    }

    // test updatePriceState, starting from opening long positions, each op moves pr exactly on certain vertex
    function test_updatePriceState_startFromLonging_onPoint() public {
        // ----------------------------------------------------------------
        // move step by step until the limit reached
        // ----------------------------------------------------------------
        UpdatePriceStateCase[6] memory longCases = [
            UpdatePriceStateCase({
                id: 1,
                side: LONG,
                sizeDelta: priceState.priceVertices[1].size, // move exactly to v[1] by longing
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158495939109785807356,
                netSizeExpect: priceState.priceVertices[1].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[1].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 2,
                side: LONG,
                sizeDelta: priceState.priceVertices[2].size - priceState.priceVertices[1].size, // continue move to v2
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158575167272300071694,
                netSizeExpect: priceState.priceVertices[2].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[2].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 3,
                side: LONG,
                sizeDelta: priceState.priceVertices[3].size - priceState.priceVertices[2].size, // continue move to v3
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158654395434814336031,
                netSizeExpect: priceState.priceVertices[3].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[3].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 4,
                side: LONG,
                sizeDelta: priceState.priceVertices[4].size - priceState.priceVertices[3].size, // continue move to v4
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158733623597328600369,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 5,
                side: LONG,
                sizeDelta: priceState.priceVertices[5].size - priceState.priceVertices[4].size, // continue move to v5
                globalSideExpect: SHORT,
                tradePriceX96Expect: 159407062978699847239,
                netSizeExpect: priceState.priceVertices[5].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[5].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            }),
            UpdatePriceStateCase({
                id: 6,
                side: LONG,
                sizeDelta: priceState.priceVertices[6].size - priceState.priceVertices[5].size, // continue move to v6
                globalSideExpect: SHORT,
                tradePriceX96Expect: 175094239156524186082,
                netSizeExpect: priceState.priceVertices[6].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[6].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 6
            })
        ];

        uint256 snapshotAtV4;
        for (uint i = 0; i < longCases.length; ++i) {
            expectEmitPremiumChangedEvent(longCases[i].prX96Expect);
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                longCases[i].side,
                longCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(longCases[i], tradePriceX96);
            if (i == 3) snapshotAtV4 = vm.snapshot(); // choose a point to take snapshot for later liquidation tests
        }

        // ----------------------------------------------------------------
        // continue to long, expect to revert
        // ----------------------------------------------------------------
        vm.expectRevert(PriceUtil.MaxPremiumRateExceeded.selector);
        PriceUtil.updatePriceState(globalPosition, priceState, LONG, 1, indexPriceX96, false);

        // ----------------------------------------------------------------
        // move back to (0, 0) step by step
        // price is a bit worse than long by 1
        // ----------------------------------------------------------------
        UpdatePriceStateCase[6] memory shortCases = [
            UpdatePriceStateCase({
                id: 7,
                side: SHORT,
                sizeDelta: priceState.priceVertices[6].size - priceState.priceVertices[5].size,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 175094239156524186081,
                netSizeExpect: priceState.priceVertices[5].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[5].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            }),
            UpdatePriceStateCase({
                id: 8,
                side: SHORT,
                sizeDelta: priceState.priceVertices[5].size - priceState.priceVertices[4].size,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 159407062978699847238,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 9,
                side: SHORT,
                sizeDelta: priceState.priceVertices[4].size - priceState.priceVertices[3].size,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158733623597328600368,
                netSizeExpect: priceState.priceVertices[3].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[3].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 10,
                side: SHORT,
                sizeDelta: priceState.priceVertices[3].size - priceState.priceVertices[2].size,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158654395434814336030,
                netSizeExpect: priceState.priceVertices[2].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[2].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 11,
                side: SHORT,
                sizeDelta: priceState.priceVertices[2].size - priceState.priceVertices[1].size,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158575167272300071693,
                netSizeExpect: priceState.priceVertices[1].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[1].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 12,
                side: SHORT,
                sizeDelta: priceState.priceVertices[1].size - priceState.priceVertices[0].size,
                globalSideExpect: SHORT, // lp would have no position, but side wont be updated
                tradePriceX96Expect: 158495939109785807355,
                netSizeExpect: 0,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[0].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 0
            })
        ];

        for (uint i = 0; i < shortCases.length; ++i) {
            expectEmitPremiumChangedEvent(shortCases[i].prX96Expect);
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                shortCases[i].side,
                shortCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(shortCases[i], tradePriceX96);
        }

        // ----------------------------------------------------------------
        // move cross (0, 0) to another side
        // ----------------------------------------------------------------
        PriceUtil.updatePriceState(globalPosition, priceState, SHORT, 1, indexPriceX96, false);
        assertEq(Side.unwrap(globalPosition.side), Side.unwrap(LONG), "side");
        assertEq(globalPosition.netSize, 1, "netSize");
        assertEq(priceState.currentVertexIndex, 1, "currentVertexIndex");
        assertEq(priceState.pendingVertexIndex, 0, "pendingVertexIndex");

        // ----------------------------------------------------------------
        // move a single step and cross (0, 0) without using
        // liquidation buffer
        // ----------------------------------------------------------------
        vm.revertTo(snapshotAtV4);
        UpdatePriceStateCase memory crossCase = UpdatePriceStateCase({
            id: 90,
            side: SHORT,
            sizeDelta: priceState.priceVertices[4].size + priceState.priceVertices[1].size,
            globalSideExpect: LONG, // lp should have an opposite position which is long
            tradePriceX96Expect: 158541212345508244119,
            netSizeExpect: priceState.priceVertices[1].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[1].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 1
        });
        expectEmitPremiumChangedEvent(crossCase.prX96Expect);
        uint160 tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            crossCase.side,
            crossCase.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(crossCase, tradePriceX96);

        // ----------------------------------------------------------------
        // move a single step and cross (0, 0) to the limit
        // expect to revert
        // ----------------------------------------------------------------
        vm.revertTo(snapshotAtV4);
        UpdatePriceStateCase memory crossAndRevertCase = UpdatePriceStateCase({
            id: 290,
            side: SHORT,
            sizeDelta: priceState.priceVertices[4].size + priceState.priceVertices[6].size,
            globalSideExpect: LONG,
            tradePriceX96Expect: 144149982540238657655,
            netSizeExpect: priceState.priceVertices[6].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[6].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 6
        });

        expectEmitPremiumChangedEvent(crossAndRevertCase.prX96Expect);
        tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            crossAndRevertCase.side,
            crossAndRevertCase.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(crossAndRevertCase, tradePriceX96);

        vm.expectRevert(PriceUtil.MaxPremiumRateExceeded.selector);
        PriceUtil.updatePriceState(globalPosition, priceState, SHORT, 1, indexPriceX96, false);

        // ----------------------------------------------------------------
        // liquidation tests.
        // Now price is in v4 and lp has a short position
        // liquidation that should use the liquidation buffer
        // ----------------------------------------------------------------
        vm.revertTo(snapshotAtV4);
        UpdatePriceStateCase[2] memory liquidationCases = [
            UpdatePriceStateCase({
                id: 100,
                side: LONG,
                sizeDelta: 100,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 0,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 100,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 110,
                side: LONG,
                sizeDelta: 100,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 0,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 200,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            })
        ];

        for (uint i; i < liquidationCases.length; ++i) {
            expectEmitLiquidationBufferNetSizeChanged(4, liquidationCases[i].bufferSizeExpect);
            expectEmitPremiumChangedEvent(liquidationCases[i].prX96Expect);
            // in these cases, tradePrice is always 0
            PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                liquidationCases[i].side,
                liquidationCases[i].sizeDelta,
                indexPriceX96,
                true
            );
            checkResult(liquidationCases[i], 0);
        }

        uint256 snapshotWithBuffer = vm.snapshot();

        // ----------------------------------------------------------------
        // use buffer size when open new position or liquidation
        // ----------------------------------------------------------------
        UpdatePriceStateCase[4] memory useBufferCases = [
            UpdatePriceStateCase({
                id: 120,
                side: SHORT,
                sizeDelta: 50,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158773237678585732537,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 150,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 121,
                side: SHORT,
                sizeDelta: 50,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158773237678585732537,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 100,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 123,
                side: SHORT,
                sizeDelta: 100,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158773237678585732537,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 124,
                side: SHORT,
                sizeDelta: priceState.priceVertices[4].size,
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158591012904802924560,
                netSizeExpect: 0,
                bufferSizeExpect: 0,
                prX96Expect: 0,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 0
            })
        ];
        for (uint i; i < useBufferCases.length; ++i) {
            if (i < 3) expectEmitLiquidationBufferNetSizeChanged(4, useBufferCases[i].bufferSizeExpect);
            expectEmitPremiumChangedEvent(useBufferCases[i].prX96Expect);
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                useBufferCases[i].side,
                useBufferCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(useBufferCases[i], tradePriceX96);
        }

        // ----------------------------------------------------------------
        // use buffer cases run again, but treat as liquidation
        // ----------------------------------------------------------------
        vm.revertTo(snapshotWithBuffer);

        for (uint i; i < useBufferCases.length; ++i) {
            useBufferCases[i].id += 100;
            if (i < 3) expectEmitLiquidationBufferNetSizeChanged(4, useBufferCases[i].bufferSizeExpect);
            expectEmitPremiumChangedEvent(useBufferCases[i].prX96Expect);
            tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                useBufferCases[i].side,
                useBufferCases[i].sizeDelta,
                indexPriceX96,
                true
            );
            checkResult(useBufferCases[i], tradePriceX96);
        }

        // ----------------------------------------------------------------
        // use buffer size and cross the (0, 0)
        // ----------------------------------------------------------------
        vm.revertTo(snapshotWithBuffer);
        UpdatePriceStateCase memory useBufferCase2 = UpdatePriceStateCase({
            id: 160,
            side: SHORT,
            sizeDelta: priceState.priceVertices[4].size + priceState.priceVertices[1].size + 200,
            globalSideExpect: LONG,
            tradePriceX96Expect: 158541212345508244457,
            netSizeExpect: priceState.priceVertices[1].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[1].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 1
        });
        expectEmitLiquidationBufferNetSizeChanged(4, 0);
        expectEmitPremiumChangedEvent(useBufferCase2.prX96Expect);
        tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            useBufferCase2.side,
            useBufferCase2.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(useBufferCase2, tradePriceX96);

        // ----------------------------------------------------------------
        // revert to v4 which has buffer size, update liquidation buffer index
        // price continues to move by liquidation
        // and when back, two buffers should all be used
        // ----------------------------------------------------------------
        vm.revertTo(snapshotWithBuffer);
        priceState.liquidationVertexIndex = 5;
        expectEmitLiquidationBufferNetSizeChanged(5, 100);
        expectEmitPremiumChangedEvent(priceState.priceVertices[5].premiumRateX96);
        PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            LONG,
            priceState.priceVertices[5].size - priceState.priceVertices[4].size + 100,
            indexPriceX96,
            true
        );
        assertEq(priceState.premiumRateX96, priceState.priceVertices[5].premiumRateX96, "priceState.premiumRateX96");
        assertEq(priceState.liquidationBufferNetSizes[4], 200, "priceState.liquidationBufferNetSizes[4]");
        assertEq(priceState.liquidationBufferNetSizes[5], 100, "priceState.liquidationBufferNetSizes[5]");
        assertEq(globalPosition.liquidationBufferNetSize, 300, "globalPosition.liquidationBufferNetSize");
        assertEq(globalPosition.netSize, priceState.priceVertices[5].size, "globalPosition.netSize");

        UpdatePriceStateCase memory useBufferCase3 = UpdatePriceStateCase({
            id: 170,
            side: SHORT,
            sizeDelta: priceState.priceVertices[5].size - priceState.priceVertices[3].size + 300,
            globalSideExpect: SHORT,
            tradePriceX96Expect: 159294823081804639173,
            netSizeExpect: priceState.priceVertices[3].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[3].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 3
        });
        expectEmitLiquidationBufferNetSizeChanged(5, 0);
        expectEmitLiquidationBufferNetSizeChanged(4, 0);
        expectEmitPremiumChangedEvent(useBufferCase3.prX96Expect);
        tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            useBufferCase3.side,
            useBufferCase3.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(useBufferCase3, tradePriceX96);
        assertEq(priceState.liquidationBufferNetSizes[4], 0, "priceState.liquidationBufferNetSizes[4]");
        assertEq(priceState.liquidationBufferNetSizes[5], 0, "priceState.liquidationBufferNetSizes[5]");
    }

    // test updatePriceState, starting from opening short positions, each op moves pr exactly on certain vertex
    function test_updatePriceState_startFromShorting_onPoint() public {
        // ----------------------------------------------------------------
        // move step by step until the limit reached
        // ----------------------------------------------------------------
        UpdatePriceStateCase[6] memory shortCases = [
            UpdatePriceStateCase({
                id: 1,
                side: SHORT,
                sizeDelta: priceState.priceVertices[1].size, // move exactly to v[1] by longing
                globalSideExpect: LONG,
                tradePriceX96Expect: 158416710947271543018,
                netSizeExpect: priceState.priceVertices[1].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[1].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 2,
                side: SHORT,
                sizeDelta: priceState.priceVertices[2].size - priceState.priceVertices[1].size, // continue move to v2
                globalSideExpect: LONG,
                tradePriceX96Expect: 158337482784757278680,
                netSizeExpect: priceState.priceVertices[2].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[2].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 3,
                side: SHORT,
                sizeDelta: priceState.priceVertices[3].size - priceState.priceVertices[2].size, // continue move to v3
                globalSideExpect: LONG,
                tradePriceX96Expect: 158258254622243014343,
                netSizeExpect: priceState.priceVertices[3].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[3].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 4,
                side: SHORT,
                sizeDelta: priceState.priceVertices[4].size - priceState.priceVertices[3].size, // continue move to v4
                globalSideExpect: LONG,
                tradePriceX96Expect: 158179026459728750005,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 5,
                side: SHORT,
                sizeDelta: priceState.priceVertices[5].size - priceState.priceVertices[4].size, // continue move to v5
                globalSideExpect: LONG,
                tradePriceX96Expect: 157505587078357503135,
                netSizeExpect: priceState.priceVertices[5].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[5].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            }),
            UpdatePriceStateCase({
                id: 6,
                side: SHORT,
                sizeDelta: priceState.priceVertices[6].size - priceState.priceVertices[5].size, // continue move to v6
                globalSideExpect: LONG,
                tradePriceX96Expect: 141818410900533164292,
                netSizeExpect: priceState.priceVertices[6].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[6].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 6
            })
        ];

        uint256 snapshotAtV4;
        for (uint i = 0; i < shortCases.length; ++i) {
            expectEmitPremiumChangedEvent(shortCases[i].prX96Expect);
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                shortCases[i].side,
                shortCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(shortCases[i], tradePriceX96);
            if (i == 3) snapshotAtV4 = vm.snapshot(); // choose a point to take snapshot for later liquidation tests
        }
        uint256 snapshotAtV6 = vm.snapshot();

        // ----------------------------------------------------------------
        // continue to short, expect to revert
        // ----------------------------------------------------------------
        vm.expectRevert(PriceUtil.MaxPremiumRateExceeded.selector);
        PriceUtil.updatePriceState(globalPosition, priceState, SHORT, 1, indexPriceX96, false);

        // ----------------------------------------------------------------
        // move back to (0, 0) step by step
        // ----------------------------------------------------------------
        UpdatePriceStateCase[6] memory longCases = [
            UpdatePriceStateCase({
                id: 97,
                side: LONG,
                sizeDelta: priceState.priceVertices[6].size - priceState.priceVertices[5].size,
                globalSideExpect: LONG,
                tradePriceX96Expect: 141818410900533164293,
                netSizeExpect: priceState.priceVertices[5].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[5].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            }),
            UpdatePriceStateCase({
                id: 98,
                side: LONG,
                sizeDelta: priceState.priceVertices[5].size - priceState.priceVertices[4].size,
                globalSideExpect: LONG,
                tradePriceX96Expect: 157505587078357503136,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 99,
                side: LONG,
                sizeDelta: priceState.priceVertices[4].size - priceState.priceVertices[3].size,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158179026459728750006,
                netSizeExpect: priceState.priceVertices[3].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[3].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 197,
                side: LONG,
                sizeDelta: priceState.priceVertices[3].size - priceState.priceVertices[2].size,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158258254622243014344,
                netSizeExpect: priceState.priceVertices[2].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[2].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 198,
                side: LONG,
                sizeDelta: priceState.priceVertices[2].size - priceState.priceVertices[1].size,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158337482784757278681,
                netSizeExpect: priceState.priceVertices[1].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[1].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 199,
                side: LONG,
                sizeDelta: priceState.priceVertices[1].size - priceState.priceVertices[0].size,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158416710947271543019,
                netSizeExpect: priceState.priceVertices[0].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[0].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 0
            })
        ];

        for (uint i = 0; i < longCases.length; ++i) {
            expectEmitPremiumChangedEvent(longCases[i].prX96Expect);
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                longCases[i].side,
                longCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(longCases[i], tradePriceX96);
        }

        // ----------------------------------------------------------------
        // move cross (0, 0) to another side
        // ----------------------------------------------------------------
        PriceUtil.updatePriceState(globalPosition, priceState, LONG, 1, indexPriceX96, false);
        assertEq(Side.unwrap(globalPosition.side), Side.unwrap(SHORT), "side");
        assertEq(globalPosition.netSize, 1, "netSize");
        assertEq(priceState.currentVertexIndex, 1, "currentVertexIndex");
        assertEq(priceState.pendingVertexIndex, 0, "pendingVertexIndex");

        // ----------------------------------------------------------------
        // move a single step and cross (0, 0) without using
        // liquidation buffer
        // ----------------------------------------------------------------
        vm.revertTo(snapshotAtV4);
        UpdatePriceStateCase memory crossCase = UpdatePriceStateCase({
            id: 9,
            side: LONG,
            sizeDelta: priceState.priceVertices[4].size + priceState.priceVertices[1].size,
            globalSideExpect: SHORT, // lp should have an opposite position which is short
            tradePriceX96Expect: 158371437711549106255,
            netSizeExpect: priceState.priceVertices[1].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[1].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 1
        });
        expectEmitPremiumChangedEvent(crossCase.prX96Expect);
        uint160 tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            crossCase.side,
            crossCase.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(crossCase, tradePriceX96);

        // ----------------------------------------------------------------
        // move a single step and cross (0, 0) to the limit
        // expect to revert
        // ----------------------------------------------------------------
        vm.revertTo(snapshotAtV4);
        UpdatePriceStateCase memory crossAndRevertCase = UpdatePriceStateCase({
            id: 290,
            side: LONG,
            sizeDelta: priceState.priceVertices[4].size + priceState.priceVertices[6].size,
            globalSideExpect: SHORT,
            tradePriceX96Expect: 172762667516818692719,
            netSizeExpect: priceState.priceVertices[6].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[6].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 6
        });

        expectEmitPremiumChangedEvent(crossAndRevertCase.prX96Expect);
        tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            crossAndRevertCase.side,
            crossAndRevertCase.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(crossAndRevertCase, tradePriceX96);

        vm.expectRevert(PriceUtil.MaxPremiumRateExceeded.selector);
        PriceUtil.updatePriceState(globalPosition, priceState, LONG, 1, indexPriceX96, false);

        // ----------------------------------------------------------------
        // liquidation tests.
        // Now price is in v4 and lp has a long position
        // liquidation that should use the liquidation buffer
        // ----------------------------------------------------------------
        vm.revertTo(snapshotAtV4);
        UpdatePriceStateCase[2] memory liquidationCases = [
            UpdatePriceStateCase({
                id: 10,
                side: SHORT,
                sizeDelta: 100,
                globalSideExpect: LONG,
                tradePriceX96Expect: 0,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 100,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 11,
                side: SHORT,
                sizeDelta: 100,
                globalSideExpect: LONG,
                tradePriceX96Expect: 0,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 200,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            })
        ];
        for (uint i; i < liquidationCases.length; ++i) {
            expectEmitLiquidationBufferNetSizeChanged(4, liquidationCases[i].bufferSizeExpect);
            expectEmitPremiumChangedEvent(liquidationCases[i].prX96Expect);
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                liquidationCases[i].side,
                liquidationCases[i].sizeDelta,
                indexPriceX96,
                true
            );
            checkResult(liquidationCases[i], tradePriceX96);
        }

        uint256 snapshotWithBuffer = vm.snapshot();

        // ----------------------------------------------------------------
        // use buffer size when open new position or liquidation
        // ----------------------------------------------------------------
        UpdatePriceStateCase[4] memory useBufferCases = [
            UpdatePriceStateCase({
                id: 12,
                side: LONG,
                sizeDelta: 50,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158139412378471617837,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 150,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 13,
                side: LONG,
                sizeDelta: 50,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158139412378471617837,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 100,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 14,
                side: LONG,
                sizeDelta: 100,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158139412378471617837,
                netSizeExpect: priceState.priceVertices[4].size,
                bufferSizeExpect: 0,
                prX96Expect: priceState.priceVertices[4].premiumRateX96,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 15,
                side: LONG,
                sizeDelta: priceState.priceVertices[4].size,
                globalSideExpect: LONG,
                tradePriceX96Expect: 158321637152254425814,
                netSizeExpect: 0,
                bufferSizeExpect: 0,
                prX96Expect: 0,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 0
            })
        ];

        for (uint i; i < useBufferCases.length; ++i) {
            if (i < 3) expectEmitLiquidationBufferNetSizeChanged(4, useBufferCases[i].bufferSizeExpect);
            expectEmitPremiumChangedEvent(useBufferCases[i].prX96Expect);
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                useBufferCases[i].side,
                useBufferCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(useBufferCases[i], tradePriceX96);
        }

        // ----------------------------------------------------------------
        // use buffer cases run again, but treat as liquidation
        // ----------------------------------------------------------------
        vm.revertTo(snapshotWithBuffer);
        for (uint i; i < useBufferCases.length; ++i) {
            if (i < 3) expectEmitLiquidationBufferNetSizeChanged(4, useBufferCases[i].bufferSizeExpect);
            expectEmitPremiumChangedEvent(useBufferCases[i].prX96Expect);
            useBufferCases[i].id += 100;
            tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                useBufferCases[i].side,
                useBufferCases[i].sizeDelta,
                indexPriceX96,
                true
            );
            checkResult(useBufferCases[i], tradePriceX96);
        }

        // ----------------------------------------------------------------
        // use buffer size and cross the (0, 0)
        // ----------------------------------------------------------------
        vm.revertTo(snapshotWithBuffer);
        UpdatePriceStateCase memory useBufferCase2 = UpdatePriceStateCase({
            id: 16,
            side: LONG,
            sizeDelta: priceState.priceVertices[4].size + priceState.priceVertices[1].size + 200,
            globalSideExpect: SHORT,
            tradePriceX96Expect: 158371437711549105917,
            netSizeExpect: priceState.priceVertices[1].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[1].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 1
        });
        expectEmitLiquidationBufferNetSizeChanged(4, 0);
        expectEmitPremiumChangedEvent(useBufferCase2.prX96Expect);
        tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            useBufferCase2.side,
            useBufferCase2.sizeDelta,
            indexPriceX96,
            true
        );
        checkResult(useBufferCase2, tradePriceX96);

        // ----------------------------------------------------------------
        // revert to v4 which has buffer size, update liquidation buffer index
        // price continues to move by liquidation
        // and when back, two buffers should all be used
        // ----------------------------------------------------------------
        vm.revertTo(snapshotWithBuffer);
        priceState.liquidationVertexIndex = 6;
        expectEmitLiquidationBufferNetSizeChanged(6, 1500);
        expectEmitPremiumChangedEvent(priceState.priceVertices[6].premiumRateX96);
        PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            SHORT,
            priceState.priceVertices[6].size - priceState.priceVertices[4].size + 1500,
            indexPriceX96,
            true
        );
        assertEq(priceState.premiumRateX96, priceState.priceVertices[6].premiumRateX96, "priceState.premiumRateX96");
        assertEq(priceState.liquidationBufferNetSizes[4], 200, "priceState.liquidationBufferNetSizes[4]");
        assertEq(priceState.liquidationBufferNetSizes[5], 0, "priceState.liquidationBufferNetSizes[5]");
        assertEq(priceState.liquidationBufferNetSizes[6], 1500, "priceState.liquidationBufferNetSizes[6]");
        assertEq(globalPosition.liquidationBufferNetSize, 1700, "globalPosition.liquidationBufferNetSize");
        assertEq(globalPosition.netSize, priceState.priceVertices[6].size, "globalPosition.netSize");

        UpdatePriceStateCase memory useBufferCase3 = UpdatePriceStateCase({
            id: 170,
            side: LONG,
            sizeDelta: priceState.priceVertices[6].size - priceState.priceVertices[5].size + 1500,
            globalSideExpect: LONG,
            tradePriceX96Expect: 141818410900533151506,
            netSizeExpect: priceState.priceVertices[5].size,
            bufferSizeExpect: 200,
            prX96Expect: priceState.priceVertices[5].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 5
        });
        expectEmitLiquidationBufferNetSizeChanged(6, 0);
        expectEmitPremiumChangedEvent(useBufferCase3.prX96Expect);
        tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            useBufferCase3.side,
            useBufferCase3.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(useBufferCase3, tradePriceX96);
        assertEq(priceState.liquidationBufferNetSizes[6], 0, "priceState.liquidationBufferNetSizes[4]");
        assertEq(priceState.liquidationBufferNetSizes[5], 0, "priceState.liquidationBufferNetSizes[5]");
        assertEq(priceState.liquidationBufferNetSizes[4], 200, "priceState.liquidationBufferNetSizes[4]");

        UpdatePriceStateCase memory useBufferCase4 = UpdatePriceStateCase({
            id: 171,
            side: LONG,
            sizeDelta: priceState.priceVertices[5].size - priceState.priceVertices[3].size + 200,
            globalSideExpect: LONG,
            tradePriceX96Expect: 157617826975252711834,
            netSizeExpect: priceState.priceVertices[3].size,
            bufferSizeExpect: 0,
            prX96Expect: priceState.priceVertices[3].premiumRateX96,
            pendingVertexIndexExpect: 0,
            currentVertexIndexExpect: 3
        });
        expectEmitLiquidationBufferNetSizeChanged(4, 0);
        expectEmitPremiumChangedEvent(useBufferCase4.prX96Expect);
        tradePriceX96 = PriceUtil.updatePriceState(
            globalPosition,
            priceState,
            useBufferCase4.side,
            useBufferCase4.sizeDelta,
            indexPriceX96,
            false
        );
        checkResult(useBufferCase4, tradePriceX96);

        for (uint i; i < priceState.liquidationBufferNetSizes.length; ++i) {
            assertEq(priceState.liquidationBufferNetSizes[i], 0, "liquidation buffer");
        }

        // ----------------------------------------------------------------
        // liquidation, current vertex index > liquidation vertex index
        // should not update the current vertex index
        // ----------------------------------------------------------------
        vm.revertTo(snapshotAtV6);
        expectEmitLiquidationBufferNetSizeChanged(4, 100);
        expectEmitPremiumChangedEvent(priceState.priceVertices[6].premiumRateX96);
        PriceUtil.updatePriceState(globalPosition, priceState, SHORT, 100, indexPriceX96, true);
        assertEq(priceState.currentVertexIndex, 6, "current vertex index");
        assertEq(priceState.liquidationBufferNetSizes[4], 100);
    }

    // test updatePriceState, starting from opening long positions, each op moves pr to a random position
    function test_updatePriceState_startFromLonging() public {
        UpdatePriceStateCase[6] memory longCases = [
            UpdatePriceStateCase({
                id: 1,
                side: LONG,
                sizeDelta: 38138929010007018, // move to somewhere between v0 and v1
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158494828593007491044,
                netSizeExpect: 38138929010007018,
                bufferSizeExpect: 0,
                prX96Expect: 38503564478815856257104888,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 2,
                side: LONG,
                sizeDelta: 19719274506993885, // between v1 and v2
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158570988681632806283,
                netSizeExpect: 57858203517000903,
                bufferSizeExpect: 0,
                prX96Expect: 77208657481062130813881121,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 3,
                side: LONG,
                sizeDelta: 17619643503099099, // between v2 and v3
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158646318543284276592,
                netSizeExpect: 75477847020100002,
                bufferSizeExpect: 0,
                prX96Expect: 112784857302369080024670889,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 4,
                side: LONG,
                sizeDelta: 15619476506910376, // between v3 and v4
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158713432362868030175,
                netSizeExpect: 91097323527010378,
                bufferSizeExpect: 0,
                prX96Expect: 144322477074092316309449321,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 5,
                side: LONG,
                sizeDelta: 95097321523069629, // between v4 and v5
                globalSideExpect: SHORT,
                tradePriceX96Expect: 159299511605384935577,
                netSizeExpect: 186194645050080007,
                bufferSizeExpect: 0,
                prX96Expect: 727669739355339088803536364,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            }),
            UpdatePriceStateCase({
                id: 6,
                side: LONG,
                sizeDelta: 1665751805449927001, // between v5 and v6
                globalSideExpect: SHORT,
                tradePriceX96Expect: 174071341539492110073,
                netSizeExpect: 1851946450500007008,
                bufferSizeExpect: 0,
                prX96Expect: 14907862772137798226862148243,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 6
            })
        ];

        for (uint i = 0; i < longCases.length; ++i) {
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                longCases[i].side,
                longCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(longCases[i], tradePriceX96);
        }

        // step back
        // trade price got worse due to precision fault
        // cases are run in a reverse order
        UpdatePriceStateCase[6] memory shortCases = [
            UpdatePriceStateCase({
                id: 11,
                side: SHORT,
                sizeDelta: 38138929010007018, // move to somewhere between v0 and v1
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158494828593007491042,
                netSizeExpect: 0,
                bufferSizeExpect: 0,
                prX96Expect: 0,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 0
            }),
            UpdatePriceStateCase({
                id: 12,
                side: SHORT,
                sizeDelta: 19719274506993885, // between v1 and v2
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158570988681632806281,
                netSizeExpect: 38138929010007018,
                bufferSizeExpect: 0,
                prX96Expect: 38503564478815856257104888,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 13,
                side: SHORT,
                sizeDelta: 17619643503099099, // between v2 and v3
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158646318543284276590,
                netSizeExpect: 57858203517000903,
                bufferSizeExpect: 0,
                prX96Expect: 77208657481062130813881121,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 14,
                side: SHORT,
                sizeDelta: 15619476506910376, // between v3 and v4
                globalSideExpect: SHORT,
                tradePriceX96Expect: 158713432362868030173,
                netSizeExpect: 75477847020100002,
                bufferSizeExpect: 0,
                prX96Expect: 112784857302369080024670889,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 15,
                side: SHORT,
                sizeDelta: 95097321523069629, // between v4 and v5
                globalSideExpect: SHORT,
                tradePriceX96Expect: 159299511605384935575,
                netSizeExpect: 91097323527010378,
                bufferSizeExpect: 0,
                prX96Expect: 144322477074092316309449321,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 16,
                side: SHORT,
                sizeDelta: 1665751805449927001, // between v5 and v6
                globalSideExpect: SHORT,
                tradePriceX96Expect: 174071341539492110071,
                netSizeExpect: 186194645050080007,
                bufferSizeExpect: 0,
                prX96Expect: 727669739355339088803536364,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            })
        ];

        for (uint i = shortCases.length - 1; i > 0; --i) {
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                shortCases[i].side,
                shortCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(shortCases[i], tradePriceX96);
        }
    }

    // test updatePriceState, starting from opening short positions, each op moves pr to a random position
    function test_updatePriceState_startFromShorting() public {
        UpdatePriceStateCase[6] memory shortCases = [
            UpdatePriceStateCase({
                id: 1,
                side: SHORT,
                sizeDelta: 38138929010007018, // move to somewhere between v0 and v1
                globalSideExpect: LONG,
                tradePriceX96Expect: 158417821464049859330,
                netSizeExpect: 38138929010007018,
                bufferSizeExpect: 0,
                prX96Expect: 38503564478815856257104888,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 2,
                side: SHORT,
                sizeDelta: 19719274506993885, // between v1 and v2
                globalSideExpect: LONG,
                tradePriceX96Expect: 158341661375424544091,
                netSizeExpect: 57858203517000903,
                bufferSizeExpect: 0,
                prX96Expect: 77208657481062130813881121,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 3,
                side: SHORT,
                sizeDelta: 17619643503099099, // between v2 and v3
                globalSideExpect: LONG,
                tradePriceX96Expect: 158266331513773073782,
                netSizeExpect: 75477847020100002,
                bufferSizeExpect: 0,
                prX96Expect: 112784857302369080024670889,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 4,
                side: SHORT,
                sizeDelta: 15619476506910376, // between v3 and v4
                globalSideExpect: LONG,
                tradePriceX96Expect: 158199217694189320199,
                netSizeExpect: 91097323527010378,
                bufferSizeExpect: 0,
                prX96Expect: 144322477074092316309449321,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 5,
                side: SHORT,
                sizeDelta: 95097321523069629, // between v4 and v5
                globalSideExpect: LONG,
                tradePriceX96Expect: 157613138451672414797,
                netSizeExpect: 186194645050080007,
                bufferSizeExpect: 0,
                prX96Expect: 727669739355339088803536364,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            }),
            UpdatePriceStateCase({
                id: 6,
                side: SHORT,
                sizeDelta: 1665751805449927001, // between v5 and v6
                globalSideExpect: LONG,
                tradePriceX96Expect: 142841308517565240301,
                netSizeExpect: 1851946450500007008,
                bufferSizeExpect: 0,
                prX96Expect: 14907862772137798226862148243,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 6
            })
        ];

        for (uint i = 0; i < shortCases.length; ++i) {
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                shortCases[i].side,
                shortCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(shortCases[i], tradePriceX96);
        }

        // step back
        // trade price got worse due to precision fault
        // cases are run in a reverse order
        UpdatePriceStateCase[6] memory longCases = [
            UpdatePriceStateCase({
                id: 11,
                side: LONG,
                sizeDelta: 38138929010007018, // move to somewhere between v0 and v1
                globalSideExpect: LONG,
                tradePriceX96Expect: 158417821464049859332,
                netSizeExpect: 0,
                bufferSizeExpect: 0,
                prX96Expect: 0,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 0
            }),
            UpdatePriceStateCase({
                id: 12,
                side: LONG,
                sizeDelta: 19719274506993885, // between v1 and v2
                globalSideExpect: LONG,
                tradePriceX96Expect: 158341661375424544093,
                netSizeExpect: 38138929010007018,
                bufferSizeExpect: 0,
                prX96Expect: 38503564478815856257104888,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 1
            }),
            UpdatePriceStateCase({
                id: 13,
                side: LONG,
                sizeDelta: 17619643503099099, // between v2 and v3
                globalSideExpect: LONG,
                tradePriceX96Expect: 158266331513773073784,
                netSizeExpect: 57858203517000903,
                bufferSizeExpect: 0,
                prX96Expect: 77208657481062130813881121,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 2
            }),
            UpdatePriceStateCase({
                id: 14,
                side: LONG,
                sizeDelta: 15619476506910376, // between v3 and v4
                globalSideExpect: LONG,
                tradePriceX96Expect: 158199217694189320201,
                netSizeExpect: 75477847020100002,
                bufferSizeExpect: 0,
                prX96Expect: 112784857302369080024670889,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 3
            }),
            UpdatePriceStateCase({
                id: 15,
                side: LONG,
                sizeDelta: 95097321523069629, // between v4 and v5
                globalSideExpect: LONG,
                tradePriceX96Expect: 157613138451672414799,
                netSizeExpect: 91097323527010378,
                bufferSizeExpect: 0,
                prX96Expect: 144322477074092316309449321,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 4
            }),
            UpdatePriceStateCase({
                id: 16,
                side: LONG,
                sizeDelta: 1665751805449927001, // between v5 and v6
                globalSideExpect: LONG,
                tradePriceX96Expect: 142841308517565240303,
                netSizeExpect: 186194645050080007,
                bufferSizeExpect: 0,
                prX96Expect: 727669739355339088803536364,
                pendingVertexIndexExpect: 0,
                currentVertexIndexExpect: 5
            })
        ];

        for (uint i = longCases.length - 1; i > 0; --i) {
            uint160 tradePriceX96 = PriceUtil.updatePriceState(
                globalPosition,
                priceState,
                longCases[i].side,
                longCases[i].sizeDelta,
                indexPriceX96,
                false
            );
            checkResult(longCases[i], tradePriceX96);
        }
    }

    function expectEmitPremiumChangedEvent(uint128 prAfterX96) internal {
        vm.expectEmit(false, false, false, true);
        emit PriceUtil.PremiumRateChanged(prAfterX96);
    }

    function expectEmitLiquidationBufferNetSizeChanged(uint8 index, uint128 netSizeAfter) internal {
        vm.expectEmit(false, false, false, true);
        emit PriceUtil.LiquidationBufferNetSizeChanged(index, netSizeAfter);
    }

    function checkResult(UpdatePriceStateCase memory _case, uint160 tradePriceX96) internal {
        console.log("[CHECK] case %d", _case.id);
        assertEq(tradePriceX96, _case.tradePriceX96Expect, "tradePriceX96");
        assertEq(priceState.premiumRateX96, _case.prX96Expect, "prX96");
        assertEq(globalPosition.netSize, _case.netSizeExpect, "netSize");
        assertEq(globalPosition.liquidationBufferNetSize, _case.bufferSizeExpect, "bufferSize");
        assertEq(priceState.pendingVertexIndex, _case.pendingVertexIndexExpect, "pendingVertexIndex");
        assertEq(priceState.currentVertexIndex, _case.currentVertexIndexExpect, "currentVertexIndex");
        assertEq(Side.unwrap(globalPosition.side), Side.unwrap(_case.globalSideExpect), "side");
    }

    function test_CalculateAX96AndBX96() public {
        uint256 length = 18;
        CalculateAX96AndBX96Params[] memory items = new CalculateAX96AndBX96Params[](length);
        // global short && a > 0 && b = 0
        items[0] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(0, 0),
            IPool.PriceVertex(1, uint128(2 * Constants.Q96)),
            2 * Constants.Q96,
            0
        );
        // global long && a > 0 && b = 0
        items[1] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(0, 0),
            IPool.PriceVertex(1, uint128(2 * Constants.Q96)),
            2 * Constants.Q96,
            0
        );
        // global short && a > 0 && b > 0
        items[2] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(1, uint128(3 * Constants.Q96)),
            IPool.PriceVertex(2, uint128(5 * Constants.Q96)),
            2 * Constants.Q96,
            1 * int256(Constants.Q96)
        );
        // global long && a > 0 && b < 0
        items[3] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(1, uint128(3 * Constants.Q96)),
            IPool.PriceVertex(2, uint128(5 * Constants.Q96)),
            2 * Constants.Q96,
            -1 * int256(Constants.Q96)
        );
        // global short && a > 0 && b < 0
        items[4] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(1, uint128(1 * Constants.Q96)),
            IPool.PriceVertex(2, uint128(3 * Constants.Q96)),
            2 * Constants.Q96,
            -1 * int256(Constants.Q96)
        );
        // global long && a > 0 && b > 0
        items[5] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(1, uint128(1 * Constants.Q96)),
            IPool.PriceVertex(2, uint128(3 * Constants.Q96)),
            2 * Constants.Q96,
            1 * int256(Constants.Q96)
        );
        // global short && a > 0 && b > 0 (aX96 round up, bX96 round down)
        items[6] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(1, uint128(1 * Constants.Q96)),
            IPool.PriceVertex(5, uint128(3 * Constants.Q96) - 1),
            39614081257132168796771975168, // Constants.Q96 / 2
            39614081257132168796771975168 // Constants.Q96 / 2
        );
        // global long && a > 0 && b < 0 (aX96 round up, bX96 round down)
        items[7] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(1, uint128(1 * Constants.Q96)),
            IPool.PriceVertex(5, uint128(3 * Constants.Q96) - 1),
            39614081257132168796771975168, // Constants.Q96 / 2
            -39614081257132168796771975168 // -Constants.Q96 / 2
        );
        // global short && a = 0 && b > 0
        items[8] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(1, uint128(10 * Constants.Q96)),
            IPool.PriceVertex(2, uint128(10 * Constants.Q96)),
            0,
            10 * int256(Constants.Q96)
        );
        // global long && a = 0 && b < 0
        items[9] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(1, uint128(10 * Constants.Q96)),
            IPool.PriceVertex(2, uint128(10 * Constants.Q96)),
            0,
            -10 * int256(Constants.Q96)
        );
        // global short && a > 0 && b = 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[10] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(1, uint128(Constants.Q96 / 4)),
            IPool.PriceVertex(2, uint128(Constants.Q96 / 2)),
            19807040628566084398385987584, // 2 * Constants.Q96 / 4
            0
        );
        // global long && a > 0 && b = 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[11] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(1, uint128(Constants.Q96 / 4)),
            IPool.PriceVertex(2, uint128(Constants.Q96 / 2)),
            19807040628566084398385987584, // 2 * Constants.Q96 / 4
            0
        );
        // global short && a > 0 && b < 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[12] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(1, uint128(Constants.Q96 / 5)),
            IPool.PriceVertex(2, uint128(Constants.Q96 / 2)),
            23768448754279301278063185101, // 3 * Constants.Q96 / 10 + 1
            -7922816251426433759354395034 // -(Constants.Q96 / 10 + 1)
        );
        // global long && a > 0 && b > 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[13] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(1, uint128(Constants.Q96 / 5)),
            IPool.PriceVertex(2, uint128(Constants.Q96 / 2)),
            23768448754279301278063185101, // 3 * Constants.Q96 / 10 + 1
            7922816251426433759354395034 // Constants.Q96 / 10 + 1
        );
        // global short && a > 0 && b > 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[14] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(uint128(Constants.Q96 / 8), uint128(Constants.Q96 / 5)),
            IPool.PriceVertex(uint128(Constants.Q96 / 3), uint128(Constants.Q96 / 2)),
            2, // 36 / 25 + 1
            1584563250285286751870879006 // int256(Constants.Q96) / 50
        );
        // global long && a > 0 && b < 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[15] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(uint128(Constants.Q96 / 8), uint128(Constants.Q96 / 5)),
            IPool.PriceVertex(uint128(Constants.Q96 / 3), uint128(Constants.Q96 / 2)),
            2, // 36 / 25 + 1
            -1584563250285286751870879006 // -int256(Constants.Q96) / 50
        );
        // global short && a = 0 && b > 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[16] = CalculateAX96AndBX96Params(
            SHORT,
            IPool.PriceVertex(1, uint128(Constants.Q96 / 2)),
            IPool.PriceVertex(2, uint128(Constants.Q96 / 2)),
            0,
            int256(Constants.Q96) / 2
        );
        // global long && a = 0 && b < 0 (0 <= premiumRateX96 <= Constants.Q96)
        items[17] = CalculateAX96AndBX96Params(
            LONG,
            IPool.PriceVertex(1, uint128(Constants.Q96 / 2)),
            IPool.PriceVertex(2, uint128(Constants.Q96 / 2)),
            0,
            -int256(Constants.Q96) / 2
        );
        for (uint256 i = 0; i < length; i++) {
            CalculateAX96AndBX96Params memory item = items[i];
            (uint256 aX96, int256 bX96) = PriceUtil.calculateAX96AndBX96(item.globalSide, item.from, item.to);
            assertEq(aX96, item.aX96, string.concat("aX96: test case: ", vm.toString(i)));
            assertEq(bX96, item.bX96, string.concat("bX96: test case: ", vm.toString(i)));
        }
    }

    function testFuzz_CalculateAX96AndBX96(
        Side _globalSide,
        IPool.PriceVertex memory _from,
        IPool.PriceVertex memory _to
    ) public pure {
        _assumeForCalculateAX96AndBX96(_globalSide, _from, _to);
        PriceUtil.calculateAX96AndBX96(_globalSide, _from, _to);
    }

    function _assumeForCalculateAX96AndBX96(
        Side _globalSide,
        IPool.PriceVertex memory _from,
        IPool.PriceVertex memory _to
    ) private pure {
        vm.assume(_globalSide.isLong() || _globalSide.isShort());
        vm.assume(_from.size != _to.size);
        uint128 sizeDelta;
        if (_from.size > _to.size) {
            sizeDelta = _from.size - _to.size;
            vm.assume(_from.premiumRateX96 >= _to.premiumRateX96);
        } else {
            sizeDelta = _to.size - _from.size;
            vm.assume(_from.premiumRateX96 <= _to.premiumRateX96);
        }

        uint256 numeratorPart1X96 = uint256(_from.premiumRateX96) * _to.size;
        uint256 numeratorPart2X96 = uint256(_to.premiumRateX96) * _from.size;
        if (numeratorPart1X96 > numeratorPart2X96) {
            vm.assume((numeratorPart1X96 - numeratorPart2X96) / sizeDelta <= uint256(type(int256).max));
        } else {
            vm.assume((numeratorPart2X96 - numeratorPart1X96) / sizeDelta <= uint256(type(int256).max));
        }
    }

    function test_CalculateReachedAndSizeUsed() public {
        uint256 length = 6;
        CalculateReachedAndSizeUsedParams[] memory items = new CalculateReachedAndSizeUsedParams[](length);
        // improveBalance && sizeLeft < sizeCurrent - sizeTo
        items[0] = CalculateReachedAndSizeUsedParams({
            improveBalance: true,
            sizeCurrent: 50,
            sizeTo: 20,
            sizeLeft: 20,
            reached: false,
            sizeUsed: 20
        });
        // improveBalance && sizeLeft = sizeCurrent - sizeTo
        items[1] = CalculateReachedAndSizeUsedParams({
            improveBalance: true,
            sizeCurrent: 50,
            sizeTo: 20,
            sizeLeft: 30,
            reached: true,
            sizeUsed: 30
        });
        // improveBalance && sizeLeft > sizeCurrent - sizeTo
        items[2] = CalculateReachedAndSizeUsedParams({
            improveBalance: true,
            sizeCurrent: 50,
            sizeTo: 20,
            sizeLeft: 31,
            reached: true,
            sizeUsed: 30
        });
        // !improveBalance && sizeLeft < sizeTo - sizeCurrent
        items[3] = CalculateReachedAndSizeUsedParams({
            improveBalance: false,
            sizeCurrent: 50,
            sizeTo: 70,
            sizeLeft: 10,
            reached: false,
            sizeUsed: 10
        });
        // !improveBalance && sizeLeft = sizeTo - sizeCurrent
        items[4] = CalculateReachedAndSizeUsedParams({
            improveBalance: false,
            sizeCurrent: 50,
            sizeTo: 70,
            sizeLeft: 20,
            reached: true,
            sizeUsed: 20
        });
        // !improveBalance && sizeLeft > sizeTo - sizeCurrent
        items[5] = CalculateReachedAndSizeUsedParams({
            improveBalance: false,
            sizeCurrent: 50,
            sizeTo: 70,
            sizeLeft: 21,
            reached: true,
            sizeUsed: 20
        });
        for (uint256 i = 0; i < length; i++) {
            CalculateReachedAndSizeUsedParams memory item = items[i];
            PriceUtil.MoveStep memory _step;
            _step.improveBalance = item.improveBalance;
            _step.current.size = item.sizeCurrent;
            _step.to.size = item.sizeTo;
            _step.sizeLeft = item.sizeLeft;
            (bool reached, uint128 sizeUsed) = PriceUtil.calculateReachedAndSizeUsed(_step);
            assertEq(reached, item.reached, string.concat("reached: test case: ", vm.toString(i)));
            assertEq(sizeUsed, item.sizeUsed, string.concat("sizeUsed: test case: ", vm.toString(i)));
        }
    }

    function testFuzz_CalculateReachedAndSizeUsed(PriceUtil.MoveStep memory _step) public pure {
        _assumeCalculateReachedAndSizeUsed(_step);
        PriceUtil.calculateReachedAndSizeUsed(_step);
    }

    function _assumeCalculateReachedAndSizeUsed(PriceUtil.MoveStep memory _step) private pure {
        vm.assume(_step.sizeLeft > 0);
        if (_step.improveBalance) {
            vm.assume(_step.current.size > _step.to.size);
        } else {
            vm.assume(_step.current.size < _step.to.size);
        }
    }

    function test_CalculatePremiumRateAfterX96() public {
        // aX96 = 23768448755, bX96 = ±7922816251426433759354395034(global side: LONG(+) / SHORT(-))
        uint256 length = 8;
        CalculatePremiumRateAfterX96Params[] memory items = new CalculatePremiumRateAfterX96Params[](length);
        // long && reached && improveBalance (sizeUsed = sizeCurrent - to.size)
        items[0] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            side: LONG,
            improveBalance: true,
            sizeCurrent: 1.2e18,
            reached: true,
            sizeUsed: 0.2e18,
            premiumRateAfterX96: int256(Constants.Q96) / 5 // 15845632502852867518708790067
        });
        // long && reached && !improveBalance (sizeUsed = to.size - sizeCurrent)
        items[1] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            side: LONG,
            improveBalance: false,
            sizeCurrent: 1.2e18,
            reached: true,
            sizeUsed: 0.8e18,
            premiumRateAfterX96: int256(Constants.Q96) / 2 // 39614081257132168796771975168
        });
        // long && !reached && improveBalance (sizeUsed < sizeCurrent - to.size)
        items[2] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            side: LONG,
            improveBalance: true,
            sizeCurrent: 1.2e18,
            reached: false,
            sizeUsed: 0.1e18,
            premiumRateAfterX96: 18222477379073566240645604966
        });
        // long && !reached && !improveBalance (sizeUsed < to.size - sizeCurrent)
        items[3] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            side: LONG,
            improveBalance: false,
            sizeCurrent: 1.2e18,
            reached: false,
            sizeUsed: 0.5e18,
            premiumRateAfterX96: 32483546632073566240645604966
        });
        // short && reached && improveBalance (sizeUsed = sizeCurrent - to.size)
        items[4] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            side: SHORT,
            improveBalance: true,
            sizeCurrent: 1.2e18,
            reached: true,
            sizeUsed: 0.2e18,
            premiumRateAfterX96: int256(Constants.Q96) / 5 // 15845632502852867518708790067
        });
        // short && reached && !improveBalance (sizeUsed = to.size - sizeCurrent)
        items[5] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            side: SHORT,
            improveBalance: false,
            sizeCurrent: 1.2e18,
            reached: true,
            sizeUsed: 0.8e18,
            premiumRateAfterX96: int256(Constants.Q96) / 2 // 39614081257132168796771975168
        });
        // short && !reached && improveBalance (sizeUsed < sizeCurrent - to.size)
        items[6] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            side: SHORT,
            improveBalance: true,
            sizeCurrent: 1.2e18,
            reached: false,
            sizeUsed: 0.1e18,
            premiumRateAfterX96: 18222477379073566240645604966
        });
        // short && !reached && !improveBalance (sizeUsed < to.size - sizeCurrent)
        items[7] = CalculatePremiumRateAfterX96Params({
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 5)), // 15845632502852867518708790067
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 2)), // 39614081257132168796771975168
            side: SHORT,
            improveBalance: false,
            sizeCurrent: 1.2e18,
            reached: false,
            sizeUsed: 0.5e18,
            premiumRateAfterX96: 32483546632073566240645604966
        });
        for (uint256 i = 0; i < length; i++) {
            CalculatePremiumRateAfterX96Params memory item = items[i];
            PriceUtil.MoveStep memory _step;
            _step.from = item.from;
            _step.to = item.to;
            _step.side = item.side;
            _step.improveBalance = item.improveBalance;
            _step.current.size = item.sizeCurrent;
            int256 premiumRateAfterX96 = PriceUtil.calculatePremiumRateAfterX96(_step, item.reached, item.sizeUsed);
            assertEq(premiumRateAfterX96, item.premiumRateAfterX96, string.concat("test case: ", vm.toString(i)));
        }
    }

    function testFuzz_CalculatePremiumRateAfterX96(
        PriceUtil.MoveStep memory _step,
        bool _reached,
        uint128 _sizeUsed
    ) public pure {
        vm.assume(_step.side.isLong() || _step.side.isShort());
        _assumeCalculateReachedAndSizeUsed(_step);
        (bool reached, uint128 sizeUsed) = PriceUtil.calculateReachedAndSizeUsed(_step);
        _reached = reached;
        _sizeUsed = sizeUsed;
        if (!_reached) {
            Side globalSide = _step.improveBalance ? _step.side : _step.side.flip();
            _assumeForCalculateAX96AndBX96(globalSide, _step.from, _step.to);
            (uint256 aX96, int256 bX96) = PriceUtil.calculateAX96AndBX96(globalSide, _step.from, _step.to);
            if (_step.improveBalance) {
                vm.assume(_step.current.size > _step.to.size);
            } else {
                vm.assume(_step.current.size < _step.to.size);
            }
            uint256 targetSize = _step.improveBalance ? _step.current.size - _sizeUsed : _step.current.size + _sizeUsed;
            vm.assume(aX96 <= uint256(type(int256).max) / targetSize);
            if (globalSide.isLong()) bX96 = -bX96;
            vm.assume(bX96 <= type(int256).max - (aX96 * targetSize).toInt256());
        }
        PriceUtil.calculatePremiumRateAfterX96(_step, _reached, _sizeUsed);
    }

    function test_SimulateMove() public {
        // aX96 = 6602346877, bX96 = ±13204693752377389598923991723 (global side: LONG(-) / SHORT(+))
        uint256 length = 12;
        SimulateMoveParams[] memory items = new SimulateMoveParams[](length);
        // short && improveBalance && sizeLeft > sizeCurrent - sizeTo
        items[0] = SimulateMoveParams({
            side: SHORT,
            sizeLeft: 0.2e18 + 1,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: true,
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            tradePriceX96: 99695437830449291471, // 151 * Constants.Q96 / 120e9
            sizeUsed: 0.2e18,
            reached: true,
            premiumRateAfterX96: 19807040628566084398385987584
        });
        // short && improveBalance && sizeLeft = sizeCurrent - sizeTo
        items[1] = SimulateMoveParams({
            side: SHORT,
            sizeLeft: 0.2e18,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: true,
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            tradePriceX96: 99695437830449291471, // 151 * Constants.Q96 / 120e9
            sizeUsed: 0.2e18,
            reached: true,
            premiumRateAfterX96: 19807040628566084398385987584
        });
        // short && improveBalance && sizeLeft < sizeCurrent - sizeTo
        items[2] = SimulateMoveParams({
            side: SHORT,
            sizeLeft: 0.1e18,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: true,
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            tradePriceX96: 100025555174704944071,
            sizeUsed: 0.1e18,
            reached: false,
            premiumRateAfterX96: 20467275317077389598923991723
        });
        // long && improveBalance && sizeLeft > sizeCurrent - sizeTo
        items[3] = SimulateMoveParams({
            side: LONG,
            sizeLeft: 0.2e18 + 1,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: true,
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            tradePriceX96: 58760887198079383715,
            sizeUsed: 0.2e18,
            reached: true,
            premiumRateAfterX96: 19807040628566084398385987584
        });
        // long && improveBalance && sizeLeft = sizeCurrent - sizeTo
        items[4] = SimulateMoveParams({
            side: LONG,
            sizeLeft: 0.2e18,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: true,
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            tradePriceX96: 58760887198079383715,
            sizeUsed: 0.2e18,
            reached: true,
            premiumRateAfterX96: 19807040628566084398385987584
        });
        // long && improveBalance && sizeLeft < sizeCurrent - sizeTo
        items[5] = SimulateMoveParams({
            side: LONG,
            sizeLeft: 0.1e18,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: true,
            from: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            tradePriceX96: 58430769853823731115,
            sizeUsed: 0.1e18,
            reached: false,
            premiumRateAfterX96: 20467275317077389598923991723
        });
        // short && !improveBalance && sizeLeft > sizeTo - sizeCurrent
        items[6] = SimulateMoveParams({
            side: SHORT,
            sizeLeft: 0.8e18 + 1,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: false,
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            tradePriceX96: 55459713759985036315,
            sizeUsed: 0.8e18,
            reached: true,
            premiumRateAfterX96: 26409387504754779197847983445
        });
        // short && !improveBalance && sizeLeft = sizeTo - sizeCurrent
        items[7] = SimulateMoveParams({
            side: SHORT,
            sizeLeft: 0.8e18 + 1,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: false,
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            tradePriceX96: 55459713759985036315,
            sizeUsed: 0.8e18,
            reached: true,
            premiumRateAfterX96: 26409387504754779197847983445
        });
        // short && !improveBalance && sizeLeft < sizeTo - sizeCurrent
        items[8] = SimulateMoveParams({
            side: SHORT,
            sizeLeft: 0.5e18,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: false,
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            tradePriceX96: 56450065790723731114,
            sizeUsed: 0.5e18,
            reached: false,
            premiumRateAfterX96: 24428683443277389598923991723
        });
        // long && !improveBalance && sizeLeft > sizeTo - sizeCurrent
        items[9] = SimulateMoveParams({
            side: LONG,
            sizeLeft: 0.8e18 + 1,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: false,
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            tradePriceX96: 102996611268543638871,
            sizeUsed: 0.8e18,
            reached: true,
            premiumRateAfterX96: 26409387504754779197847983445
        });
        // long && !improveBalance && sizeLeft = sizeTo - sizeCurrent
        items[10] = SimulateMoveParams({
            side: LONG,
            sizeLeft: 0.8e18,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: false,
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            tradePriceX96: 102996611268543638871,
            sizeUsed: 0.8e18,
            reached: true,
            premiumRateAfterX96: 26409387504754779197847983445
        });
        // long && !improveBalance && sizeLeft < sizeTo - sizeCurrent
        items[11] = SimulateMoveParams({
            side: LONG,
            sizeLeft: 0.5e18,
            indexPriceX96: uint160((1000 * 1e6 * Constants.Q96) / 1e18), // 79228162514264337593
            improveBalance: false,
            from: IPool.PriceVertex(1e18, uint128(Constants.Q96 / 4)), // 19807040628566084398385987584
            current: IPool.PriceVertex(1.2e18, uint128((4 * Constants.Q96) / 15)), // 21127510003803823358278386756
            to: IPool.PriceVertex(2e18, uint128(Constants.Q96 / 3)), // 26409387504754779197847983445
            tradePriceX96: 102006259237804944072,
            sizeUsed: 0.5e18,
            reached: false,
            premiumRateAfterX96: 24428683443277389598923991723
        });
        for (uint256 i = 0; i < length; i++) {
            SimulateMoveParams memory item = items[i];
            PriceUtil.MoveStep memory _step = PriceUtil.MoveStep({
                side: item.side,
                sizeLeft: item.sizeLeft,
                indexPriceX96: item.indexPriceX96,
                improveBalance: item.improveBalance,
                from: item.from,
                current: item.current,
                to: item.to
            });
            (uint160 tradePriceX96, uint128 sizeUsed, bool reached, int256 premiumRateAfterX96) = PriceUtil
                .simulateMove(_step);
            assertEq(tradePriceX96, item.tradePriceX96, string.concat("tradePriceX96: test case: ", vm.toString(i)));
            assertEq(sizeUsed, item.sizeUsed, string.concat("sizeUsed: test case: ", vm.toString(i)));
            assertEq(reached, item.reached, string.concat("reached: test case: ", vm.toString(i)));
            assertEq(
                premiumRateAfterX96,
                item.premiumRateAfterX96,
                string.concat("premiumRateAfterX96: test case: ", vm.toString(i))
            );
        }
    }

    function testFuzz_SimulateMove(PriceUtil.MoveStep memory _step) public view {
        vm.assume(_step.side.isLong() || _step.side.isShort());
        vm.assume(_step.sizeLeft > 0);
        vm.assume(_step.indexPriceX96 > 0);
        _step.from.premiumRateX96 = uint128(bound(_step.from.premiumRateX96, 0, Constants.Q96));
        _step.current.premiumRateX96 = uint128(bound(_step.current.premiumRateX96, 0, Constants.Q96));
        _step.to.premiumRateX96 = uint128(bound(_step.to.premiumRateX96, 0, Constants.Q96));
        bool reached;
        uint128 sizeUsed;
        if (_step.improveBalance) {
            vm.assume(_step.current.size > _step.to.size);
        } else {
            vm.assume(_step.current.size < _step.to.size);
        }
        (reached, sizeUsed) = PriceUtil.calculateReachedAndSizeUsed(_step);
        if (!reached) {
            Side globalSide = _step.improveBalance ? _step.side : _step.side.flip();
            _assumeForCalculateAX96AndBX96(globalSide, _step.from, _step.to);
        }
        int256 premiumRateAfterX96 = PriceUtil.calculatePremiumRateAfterX96(_step, reached, sizeUsed);
        vm.assume(premiumRateAfterX96 >= 0 && premiumRateAfterX96 <= int256(Constants.Q96));
        int256 premiumRateBeforeX96 = _step.current.premiumRateX96.toInt256();
        vm.assume(premiumRateBeforeX96 >= 0 && premiumRateBeforeX96 <= int256(Constants.Q96));
        (, uint256 tradePriceX96Up) = Math.mulDiv2(
            _step.indexPriceX96,
            (_step.improveBalance && _step.side.isLong()) || (!_step.improveBalance && _step.side.isShort())
                ? ((int256(Constants.Q96) << 1) - premiumRateBeforeX96 - premiumRateAfterX96).toUint256()
                : ((int256(Constants.Q96) << 1) + premiumRateBeforeX96 + premiumRateAfterX96).toUint256(),
            Constants.Q96 << 1
        );
        vm.assume(tradePriceX96Up < type(uint160).max);

        PriceUtil.simulateMove(_step);
    }
}
