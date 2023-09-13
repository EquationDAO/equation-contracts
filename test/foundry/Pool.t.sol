// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import "../../contracts/core/Pool.sol";
import {PoolFactory, Router} from "../../contracts/core/PoolFactory.sol";
import {ERC20, ERC20Test} from "../../contracts/test/ERC20Test.sol";
import {MockEFC} from "../../contracts/test/MockEFC.sol";
import {MockPriceFeed} from "../../contracts/test/MockPriceFeed.sol";
import {MockFeeDistributor} from "../../contracts/test/MockFeeDistributor.sol";
import {MockRewardFarmCallback} from "../../contracts/test/MockRewardFarmCallback.sol";

contract PoolTest is Test {
    ERC20Test usd;
    PoolFactory private poolFactory;
    Pool private pool;
    address private router = address(1);

    function setUp() public {
        usd = new ERC20Test("USD", "USD", 6, 0);
        ERC20 token = new ERC20Test("Token", "TKN", 18, 0);

        MockPriceFeed priceFeed = new MockPriceFeed();
        priceFeed.setMinPriceX96(token, 143254262889779176880);
        priceFeed.setMaxPriceX96(token, 143254262889779176880);
        MockEFC EFC = new MockEFC();
        MockFeeDistributor feeDistributor = new MockFeeDistributor();
        MockRewardFarmCallback callback = new MockRewardFarmCallback();

        poolFactory = new PoolFactory(
            usd,
            IEFC(address(EFC)),
            Router(router),
            IPriceFeed(address(priceFeed)),
            IFeeDistributor(address(feeDistributor)),
            IRewardFarmCallback(address(callback))
        );
        poolFactory.concatPoolCreationCode(true, type(Pool).creationCode);

        IConfigurable.VertexConfig[] memory vertices = new IConfigurable.VertexConfig[](7);
        vertices[0] = IConfigurable.VertexConfig({balanceRate: 0, premiumRate: 0});
        vertices[1] = IConfigurable.VertexConfig({balanceRate: 4000000, premiumRate: 50000});
        vertices[2] = IConfigurable.VertexConfig({balanceRate: 6000000, premiumRate: 100000});
        vertices[3] = IConfigurable.VertexConfig({balanceRate: 8000000, premiumRate: 150000});
        vertices[4] = IConfigurable.VertexConfig({balanceRate: 10000000, premiumRate: 200000});
        vertices[5] = IConfigurable.VertexConfig({balanceRate: 20000000, premiumRate: 1000000});
        vertices[6] = IConfigurable.VertexConfig({balanceRate: 100000000, premiumRate: 10000000});
        poolFactory.enableToken(
            token,
            IConfigurable.TokenConfig({
                minMarginPerLiquidityPosition: 10 * (10 ** 6),
                maxRiskRatePerLiquidityPosition: 99_500_000,
                maxLeveragePerLiquidityPosition: 200,
                minMarginPerPosition: 10 * (10 ** 6),
                maxLeveragePerPosition: 200,
                liquidationFeeRatePerPosition: 200_000,
                liquidationExecutionFee: 600_000,
                interestRate: 1250,
                maxFundingRate: 150_000
            }),
            IConfigurable.TokenFeeRateConfig({
                tradingFeeRate: 50_000,
                liquidityFeeRate: 50_000_000,
                protocolFeeRate: 30_000_000,
                referralReturnFeeRate: 10_000_000,
                referralParentReturnFeeRate: 1_000_000,
                referralDiscountRate: 90_000_000
            }),
            IConfigurable.TokenPriceConfig({
                maxPriceImpactLiquidity: 1_0000_0000 * (10 ** 6),
                liquidationVertexIndex: 4,
                vertices: vertices
            })
        );

        pool = Pool(address(poolFactory.createPool(token)));
    }

    function testFuzz_OpenLiquidityPosition(address account, uint128 margin, uint128 liquidity) public {
        vm.assume(account != address(0));

        usd.mint(address(pool), margin);
        vm.startPrank(router);

        if (liquidity == 0) {
            vm.expectRevert(IPoolErrors.InvalidLiquidityToOpen.selector);
            pool.openLiquidityPosition(account, margin, liquidity);
            return;
        }

        if (margin < 10 * (10 ** 6)) {
            vm.expectRevert(IPoolErrors.InsufficientMargin.selector);
            pool.openLiquidityPosition(account, margin, liquidity);
            return;
        }

        if (uint256(margin) * 200 < liquidity) {
            vm.expectRevert(abi.encodeWithSelector(IPoolErrors.LeverageTooHigh.selector, margin, liquidity, 200));
            pool.openLiquidityPosition(account, margin, liquidity);
            return;
        }

        pool.openLiquidityPosition(account, margin, liquidity);

        assertEq(pool.liquidityPositionAccount(1), account);

        {
            (
                uint128 _margin,
                uint128 _liquidity,
                uint256 entryUnrealizedLoss,
                uint256 entryRealizedProfitGrowthX64,
                uint64 entryTime,
                address _account
            ) = pool.liquidityPositions(1);
            assertEq(_margin, margin);
            assertEq(_liquidity, liquidity);
            assertEq(entryUnrealizedLoss, 0);
            assertEq(entryRealizedProfitGrowthX64, 0);
            assertEq(entryTime, block.timestamp);
            assertEq(_account, account);
        }

        {
            (
                uint128 netSize,
                uint128 liquidationBufferNetSize,
                uint160 entryPriceX96,
                Side side,
                uint128 _liquidity,
                uint256 realizedProfitGrowthX64
            ) = pool.globalLiquidityPosition();
            assertEq(netSize, 0);
            assertEq(liquidationBufferNetSize, 0);
            assertEq(entryPriceX96, 0);
            assertEq(Side.unwrap(side), 0);
            assertEq(_liquidity, liquidity);
            assertEq(realizedProfitGrowthX64, 0);
        }

        vm.stopPrank();
    }

    function testFuzz_OpenLiquidityPosition_RevertIf_TotalLiquidityOverflow(
        address account,
        uint128 margin,
        uint128 liquidity
    ) public {
        vm.assume(account != address(0));
        vm.assume(margin >= 10 * (10 ** 6));
        vm.assume(uint256(margin) * 200 >= liquidity);
        vm.assume(liquidity > 0);

        usd.mint(address(pool), uint256(margin));
        vm.startPrank(router);

        assertEq(pool.openLiquidityPosition(account, margin, liquidity), 1);

        usd.mint(address(pool), uint256(margin));

        if (uint256(margin) * 2 > type(uint128).max) {
            vm.expectRevert();
            pool.openLiquidityPosition(account, margin, liquidity);
            return;
        }

        if (uint256(liquidity) * 2 > type(uint128).max) {
            vm.expectRevert();
            pool.openLiquidityPosition(account, margin, liquidity);
            return;
        }

        assertEq(pool.openLiquidityPosition(account, margin, liquidity), 2);

        {
            (
                uint128 netSize,
                uint128 liquidationBufferNetSize,
                uint160 entryPriceX96,
                Side side,
                uint128 _liquidity,
                uint256 realizedProfitGrowthX64
            ) = pool.globalLiquidityPosition();
            assertEq(netSize, 0);
            assertEq(liquidationBufferNetSize, 0);
            assertEq(entryPriceX96, 0);
            assertEq(Side.unwrap(side), 0);
            assertEq(_liquidity, liquidity * 2);
            assertEq(realizedProfitGrowthX64, 0);
        }

        vm.stopPrank();
    }

    function testFuzz_AdjustLiquidityPositionMargin(address account, int128 marginDelta, address receiver) public {
        vm.assume(account != address(0));
        vm.assume(receiver != address(pool));
        vm.assume(receiver != address(0));

        uint128 margin = type(uint128).max / 10;
        uint128 liquidity = type(uint128).max / 10;

        usd.mint(address(pool), uint256(margin));
        vm.startPrank(router);

        uint96 id = pool.openLiquidityPosition(account, margin, liquidity);

        if (marginDelta >= 0) {
            usd.mint(address(pool), uint128(marginDelta));
            if (uint256(margin) + uint128(marginDelta) > type(uint128).max) {
                vm.expectRevert();
                pool.adjustLiquidityPositionMargin(id, marginDelta, receiver);
                return;
            }
            pool.adjustLiquidityPositionMargin(1, marginDelta, receiver);

            {
                (uint128 _margin, uint128 _liquidity, , , , ) = pool.liquidityPositions(1);
                assertEq(_margin, uint256(margin) + uint128(marginDelta));
                assertEq(_liquidity, liquidity);
            }
        } else {
            if (marginDelta == type(int128).min) {
                vm.expectRevert();
                pool.adjustLiquidityPositionMargin(id, marginDelta, receiver);
                return;
            }
            if (margin < uint128(-marginDelta)) {
                vm.expectRevert(IPoolErrors.InsufficientMargin.selector);
                pool.adjustLiquidityPositionMargin(id, marginDelta, receiver);
                return;
            }
            if (margin - uint128(-marginDelta) < 600_000 || margin - uint128(-marginDelta) - 600_000 == 0) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IPoolErrors.RiskRateTooHigh.selector,
                        margin - uint128(-marginDelta),
                        600_000,
                        0
                    )
                );
                pool.adjustLiquidityPositionMargin(id, marginDelta, receiver);
                return;
            }
            if ((uint256(margin) - uint128(-marginDelta)) * 200 < liquidity) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IPoolErrors.LeverageTooHigh.selector,
                        margin - uint128(-marginDelta),
                        liquidity,
                        200
                    )
                );
                pool.adjustLiquidityPositionMargin(id, marginDelta, receiver);
                return;
            }

            pool.adjustLiquidityPositionMargin(id, marginDelta, receiver);
            assertEq(usd.balanceOf(receiver), uint128(-marginDelta));
            {
                (uint128 _margin, uint128 _liquidity, , , , ) = pool.liquidityPositions(1);
                assertEq(_margin, uint256(margin) - uint128(-marginDelta));
                assertEq(_liquidity, liquidity);
            }
        }

        vm.stopPrank();
    }
}
