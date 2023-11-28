// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Token.sol";
import "forge-std/Test.sol";
import "../../contracts/misc/Airdrop.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AirdropTest is Test {
    IERC20 private token;
    Airdrop private airdrop;
    PackedValue[] private packedValues;
    address private constant ACCOUNT0 = address(1);
    address private constant ACCOUNT1 = address(2);
    address private constant ACCOUNT2 = address(3);
    uint96 private constant AMOUNT0 = 100e18;
    uint96 private constant AMOUNT1 = 200e18;
    uint96 private constant AMOUNT2 = 300e18;
    address private constant SENDER = address(5);

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Token("T18", "T18");
        airdrop = new Airdrop();

        packedValues = new PackedValue[](3);
        PackedValue packedValue0 = PackedValue.wrap(0);
        packedValue0 = packedValue0.packUint96(AMOUNT0, 0);
        packedValue0 = packedValue0.packAddress(ACCOUNT0, 96);
        PackedValue packedValue1 = PackedValue.wrap(0);
        packedValue1 = packedValue1.packUint96(AMOUNT1, 0);
        packedValue1 = packedValue1.packAddress(ACCOUNT1, 96);
        PackedValue packedValue2 = PackedValue.wrap(0);
        packedValue2 = packedValue2.packUint96(AMOUNT2, 0);
        packedValue2 = packedValue2.packAddress(ACCOUNT2, 96);
        packedValues[0] = packedValue0;
        packedValues[1] = packedValue1;
        packedValues[2] = packedValue2;
    }

    function testSetMaxBatchSize() public {
        assertEq(airdrop.maxBatchSize(), 200);
        airdrop.setMaxBatchSize(100);
        assertEq(airdrop.maxBatchSize(), 100);
    }

    function testMultiTransfer_RevertIfTheTokenIsZeroAddress() public {
        vm.expectRevert(Airdrop.InvalidToken.selector);
        airdrop.multiTransfer(IERC20(address(0)), new PackedValue[](0));
    }

    function testMultiTransfer_RevertIfTheLengthExceedMaxBatchSize() public {
        assertEq(airdrop.maxBatchSize(), 200);
        airdrop.setMaxBatchSize(2);
        vm.expectRevert(abi.encodeWithSignature("InvalidBatchSize(uint256,uint256)", 3, 2));
        airdrop.multiTransfer(token, packedValues);
    }

    function testMultiTransfer_RevertIfTheSenderHasInsufficientBalance() public {
        deal(address(token), SENDER, AMOUNT0 + AMOUNT1 + AMOUNT2 - 1);
        vm.prank(SENDER);
        token.approve(address(airdrop), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance(uint256)", AMOUNT0 + AMOUNT1 + AMOUNT2));
        airdrop.multiTransfer(token, packedValues);
    }

    function testMultiTransfer_RevertIfTheAmountIsZero() public {
        PackedValue packedValue0 = PackedValue.wrap(0);
        packedValue0 = packedValue0.packUint96(0, 0);
        packedValue0 = packedValue0.packAddress(ACCOUNT1, 96);
        packedValues[0] = packedValue0;
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount(uint256)", 0));
        airdrop.multiTransfer(token, packedValues);
    }

    function testMultiTransfer_RevertIfTheAccountIsZero() public {
        PackedValue packedValue1 = PackedValue.wrap(0);
        packedValue1 = packedValue1.packUint96(AMOUNT0, 0);
        packedValue1 = packedValue1.packAddress(address(0), 96);
        packedValues[1] = packedValue1;
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress(uint256)", 1));
        airdrop.multiTransfer(token, packedValues);
    }

    function testMultiTransfer_ShouldEmitTheRightEventAndUpdatedWithTheRightValue() public {
        deal(address(token), SENDER, AMOUNT0 + AMOUNT1 + AMOUNT2);
        vm.startPrank(SENDER);
        token.approve(address(airdrop), AMOUNT0 + AMOUNT1 + AMOUNT2);
        vm.expectEmit(true, true, false, true);
        emit Transfer(SENDER, ACCOUNT0, AMOUNT0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(SENDER, ACCOUNT1, AMOUNT1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(SENDER, ACCOUNT2, AMOUNT2);
        airdrop.multiTransfer(token, packedValues);
        assertEq(token.balanceOf(ACCOUNT0), AMOUNT0);
        assertEq(token.balanceOf(ACCOUNT1), AMOUNT1);
        assertEq(token.balanceOf(ACCOUNT2), AMOUNT2);
    }
}
