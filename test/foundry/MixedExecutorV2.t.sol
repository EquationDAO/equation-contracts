// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../contracts/misc/MixedExecutorV2.sol";
import "../../contracts/test/MockEFC.sol";
import "../../contracts/test/MockPool.sol";
import "../../contracts/test/MockPoolFactory.sol";
import "../../contracts/test/MockFeeDistributor.sol";

contract MixedExecutorV2Test is Test {
    MockPool public pool1;
    MockPool public pool2;
    MockPoolFactory public poolFactory;

    PoolIndexer public poolIndexer;

    event IncreaseOrderExecuteFailed(uint256 indexed orderIndex);
    event DecreaseOrderExecuteFailed(uint256 indexed orderIndex);

    function setUp() public {
        pool1 = new MockPool(IERC20(address(0)), IERC20(address(0x101)));
        pool2 = new MockPool(IERC20(address(0)), IERC20(address(0x102)));

        poolFactory = new MockPoolFactory();
        poolFactory.createPool(address(pool1));
        poolFactory.createPool(address(pool2));

        poolIndexer = new PoolIndexer(IPoolFactory(address(poolFactory)));
        poolIndexer.assignPoolIndex(IPool(address(pool1)));
        poolIndexer.assignPoolIndex(IPool(address(pool2)));
    }

    function test_executeIncreaseOrder_revert_if_requireSuccess_is_true() public {
        MixedExecutorV2 executor = new MixedExecutorV2(
            poolIndexer,
            ILiquidator(address(0)),
            IPositionRouter(address(0)),
            IPriceFeed(address(0)),
            IOrderBook(address(new OrderBook_Thrown_InvalidMarketTriggerPrice()))
        );
        executor.setExecutor(address(this), true);

        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint248(1111, 0);
        packed = packed.packBool(true, 248);
        vm.expectRevert(
            abi.encodeWithSelector(
                MixedExecutorV2.ExecutionFailed.selector,
                abi.encodeWithSelector(IOrderBook.InvalidMarketPriceToTrigger.selector, 111, 222)
            )
        );
        executor.executeIncreaseOrder(packed);
    }

    function test_executeIncreaseOrder_not_cancel_order_due_to_invalid_market_trigger_price() public {
        MixedExecutorV2 executor = new MixedExecutorV2(
            poolIndexer,
            ILiquidator(address(0)),
            IPositionRouter(address(0)),
            IPriceFeed(address(0)),
            IOrderBook(address(new OrderBook_Thrown_InvalidMarketTriggerPrice()))
        );
        executor.setExecutor(address(this), true);

        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint248(1111, 0);
        packed = packed.packBool(false, 248);
        vm.expectEmit(true, false, false, false);
        emit IncreaseOrderExecuteFailed(1111);
        executor.executeIncreaseOrder(packed);
    }

    function test_executeDecreaseOrder_revert_if_requireSuccess_is_true() public {
        MixedExecutorV2 executor = new MixedExecutorV2(
            poolIndexer,
            ILiquidator(address(0)),
            IPositionRouter(address(0)),
            IPriceFeed(address(0)),
            IOrderBook(address(new OrderBook_Thrown_InvalidMarketTriggerPrice()))
        );
        executor.setExecutor(address(this), true);

        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint248(2222, 0);
        packed = packed.packBool(true, 248);
        vm.expectRevert(
            abi.encodeWithSelector(
                MixedExecutorV2.ExecutionFailed.selector,
                abi.encodeWithSelector(IOrderBook.InvalidMarketPriceToTrigger.selector, 222, 333)
            )
        );
        executor.executeDecreaseOrder(packed);
    }

    function test_executeDecreaseOrder_not_cancel_order_due_to_invalid_market_trigger_price() public {
        MixedExecutorV2 executor = new MixedExecutorV2(
            poolIndexer,
            ILiquidator(address(0)),
            IPositionRouter(address(0)),
            IPriceFeed(address(0)),
            IOrderBook(address(new OrderBook_Thrown_InvalidMarketTriggerPrice()))
        );
        executor.setExecutor(address(this), true);

        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint248(2222, 0);
        packed = packed.packBool(false, 248);
        vm.expectEmit(true, false, false, false);
        emit DecreaseOrderExecuteFailed(2222);
        executor.executeDecreaseOrder(packed);
    }
}

contract OrderBook_Thrown_InvalidMarketTriggerPrice {
    function executeIncreaseOrder(uint256, address) external pure {
        revert IOrderBook.InvalidMarketPriceToTrigger(111, 222);
    }

    function executeDecreaseOrder(uint256, address) external pure {
        revert IOrderBook.InvalidMarketPriceToTrigger(222, 333);
    }
}
