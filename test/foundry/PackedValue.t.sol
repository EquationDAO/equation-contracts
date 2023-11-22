// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../contracts/types/PackedValue.sol";

contract PackedValueTest is Test {
    function setUp() public {}

    function test_pack_1_value(uint16 value) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint16(value, 0);

        assertEq(packed.unpackUint16(0), value);
        assertEq(PackedValue.unwrap(packed), uint256(value));
    }

    function test_pack_2_value(uint16 value, uint24 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint16(value, 0);
        packed = packed.packUint24(value2, 16);

        assertEq(packed.unpackUint16(0), value);
        assertEq(packed.unpackUint24(16), value2);
        assertEq(PackedValue.unwrap(packed), uint256(value) | (uint256(value2) << 16));
    }

    function test_pack_2_value(uint16 value, uint32 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint16(value, 0);
        packed = packed.packUint32(value2, 16);

        assertEq(packed.unpackUint16(0), value);
        assertEq(packed.unpackUint32(16), value2);
        assertEq(PackedValue.unwrap(packed), uint256(value) | (uint256(value2) << 16));
    }

    function test_pack_2_value(uint32 value, uint32 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint32(value, 0);
        packed = packed.packUint32(value2, 32);

        assertEq(packed.unpackUint32(0), value);
        assertEq(packed.unpackUint32(32), value2);
        assertEq(PackedValue.unwrap(packed), uint256(value) | (uint256(value2) << 32));
    }

    function test_pack_2_value(uint24 value, uint232 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint24(value, 0);
        packed = packed.packUint232(value2, 24);

        assertEq(packed.unpackUint24(0), value);
        assertEq(packed.unpackUint232(24), value2);
        assertEq(PackedValue.unwrap(packed), uint256(value) | (uint256(value2) << 24));
    }

    function test_pack_2_value(address value, bool value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packAddress(value, 0);
        packed = packed.packBool(value2, 160);

        assertEq(packed.unpackAddress(0), value);
        assertEq(packed.unpackBool(160), value2);
        assertEq(PackedValue.unwrap(packed), uint256(uint160(value)) | (uint256(value2 ? 1 : 0) << 160));
    }

    function test_pack_3_value(uint24 value, uint32 value2, uint16 value3) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint24(value, 0);
        packed = packed.packUint32(value2, 24);
        packed = packed.packUint16(value3, 56);

        assertEq(packed.unpackUint24(0), value);
        assertEq(packed.unpackUint32(24), value2);
        assertEq(packed.unpackUint16(56), value3);
        assertEq(PackedValue.unwrap(packed), uint256(value) | (uint256(value2) << 24) | (uint256(value3) << 56));
    }

    function test_pack_3_value(uint24 value, uint16 value2, uint216 value3) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint24(value, 0);
        packed = packed.packUint16(value2, 24);
        packed = packed.packUint216(value3, 40);

        assertEq(packed.unpackUint24(0), value);
        assertEq(packed.unpackUint16(24), value2);
        assertEq(packed.unpackUint216(40), value3);
        assertEq(PackedValue.unwrap(packed), uint256(value) | (uint256(value2) << 24) | (uint256(value3) << 40));
    }

    function test_pack_4_value(uint24 value, uint16 value2, uint16 value3, uint200 value4) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint24(value, 0);
        packed = packed.packUint16(value2, 24);
        packed = packed.packUint16(value3, 40);
        packed = packed.packUint200(value4, 56);

        assertEq(packed.unpackUint24(0), value);
        assertEq(packed.unpackUint16(24), value2);
        assertEq(packed.unpackUint16(40), value3);
        assertEq(packed.unpackUint200(56), value4);
    }
}
