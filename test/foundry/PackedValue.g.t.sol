// This file was procedurally generated from scripts/generate/PackedValue.g.t.template.js, DO NOT MODIFY MANUALLY
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../contracts/types/PackedValue.sol";

contract PackedValueTest_Generated is Test {
    function test_uint8_and_uint248(uint8 value1, uint248 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint8(value1, 0);
        packed = packed.packUint248(value2, 8);

        assertEq(packed.unpackUint8(0), value1);
        assertEq(packed.unpackUint248(8), value2);
    }

    function test_uint16_and_uint240(uint16 value1, uint240 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint16(value1, 0);
        packed = packed.packUint240(value2, 16);

        assertEq(packed.unpackUint16(0), value1);
        assertEq(packed.unpackUint240(16), value2);
    }

    function test_uint24_and_uint232(uint24 value1, uint232 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint24(value1, 0);
        packed = packed.packUint232(value2, 24);

        assertEq(packed.unpackUint24(0), value1);
        assertEq(packed.unpackUint232(24), value2);
    }

    function test_uint32_and_uint224(uint32 value1, uint224 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint32(value1, 0);
        packed = packed.packUint224(value2, 32);

        assertEq(packed.unpackUint32(0), value1);
        assertEq(packed.unpackUint224(32), value2);
    }

    function test_uint40_and_uint216(uint40 value1, uint216 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint40(value1, 0);
        packed = packed.packUint216(value2, 40);

        assertEq(packed.unpackUint40(0), value1);
        assertEq(packed.unpackUint216(40), value2);
    }

    function test_uint48_and_uint208(uint48 value1, uint208 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint48(value1, 0);
        packed = packed.packUint208(value2, 48);

        assertEq(packed.unpackUint48(0), value1);
        assertEq(packed.unpackUint208(48), value2);
    }

    function test_uint56_and_uint200(uint56 value1, uint200 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint56(value1, 0);
        packed = packed.packUint200(value2, 56);

        assertEq(packed.unpackUint56(0), value1);
        assertEq(packed.unpackUint200(56), value2);
    }

    function test_uint64_and_uint192(uint64 value1, uint192 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint64(value1, 0);
        packed = packed.packUint192(value2, 64);

        assertEq(packed.unpackUint64(0), value1);
        assertEq(packed.unpackUint192(64), value2);
    }

    function test_uint72_and_uint184(uint72 value1, uint184 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint72(value1, 0);
        packed = packed.packUint184(value2, 72);

        assertEq(packed.unpackUint72(0), value1);
        assertEq(packed.unpackUint184(72), value2);
    }

    function test_uint80_and_uint176(uint80 value1, uint176 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint80(value1, 0);
        packed = packed.packUint176(value2, 80);

        assertEq(packed.unpackUint80(0), value1);
        assertEq(packed.unpackUint176(80), value2);
    }

    function test_uint88_and_uint168(uint88 value1, uint168 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint88(value1, 0);
        packed = packed.packUint168(value2, 88);

        assertEq(packed.unpackUint88(0), value1);
        assertEq(packed.unpackUint168(88), value2);
    }

    function test_uint96_and_uint160(uint96 value1, uint160 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint96(value1, 0);
        packed = packed.packUint160(value2, 96);

        assertEq(packed.unpackUint96(0), value1);
        assertEq(packed.unpackUint160(96), value2);
    }

    function test_uint104_and_uint152(uint104 value1, uint152 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint104(value1, 0);
        packed = packed.packUint152(value2, 104);

        assertEq(packed.unpackUint104(0), value1);
        assertEq(packed.unpackUint152(104), value2);
    }

    function test_uint112_and_uint144(uint112 value1, uint144 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint112(value1, 0);
        packed = packed.packUint144(value2, 112);

        assertEq(packed.unpackUint112(0), value1);
        assertEq(packed.unpackUint144(112), value2);
    }

    function test_uint120_and_uint136(uint120 value1, uint136 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint120(value1, 0);
        packed = packed.packUint136(value2, 120);

        assertEq(packed.unpackUint120(0), value1);
        assertEq(packed.unpackUint136(120), value2);
    }

    function test_uint128_and_uint128(uint128 value1, uint128 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint128(value1, 0);
        packed = packed.packUint128(value2, 128);

        assertEq(packed.unpackUint128(0), value1);
        assertEq(packed.unpackUint128(128), value2);
    }

    function test_uint136_and_uint120(uint136 value1, uint120 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint136(value1, 0);
        packed = packed.packUint120(value2, 136);

        assertEq(packed.unpackUint136(0), value1);
        assertEq(packed.unpackUint120(136), value2);
    }

    function test_uint144_and_uint112(uint144 value1, uint112 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint144(value1, 0);
        packed = packed.packUint112(value2, 144);

        assertEq(packed.unpackUint144(0), value1);
        assertEq(packed.unpackUint112(144), value2);
    }

    function test_uint152_and_uint104(uint152 value1, uint104 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint152(value1, 0);
        packed = packed.packUint104(value2, 152);

        assertEq(packed.unpackUint152(0), value1);
        assertEq(packed.unpackUint104(152), value2);
    }

    function test_uint160_and_uint96(uint160 value1, uint96 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint160(value1, 0);
        packed = packed.packUint96(value2, 160);

        assertEq(packed.unpackUint160(0), value1);
        assertEq(packed.unpackUint96(160), value2);
    }

    function test_uint168_and_uint88(uint168 value1, uint88 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint168(value1, 0);
        packed = packed.packUint88(value2, 168);

        assertEq(packed.unpackUint168(0), value1);
        assertEq(packed.unpackUint88(168), value2);
    }

    function test_uint176_and_uint80(uint176 value1, uint80 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint176(value1, 0);
        packed = packed.packUint80(value2, 176);

        assertEq(packed.unpackUint176(0), value1);
        assertEq(packed.unpackUint80(176), value2);
    }

    function test_uint184_and_uint72(uint184 value1, uint72 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint184(value1, 0);
        packed = packed.packUint72(value2, 184);

        assertEq(packed.unpackUint184(0), value1);
        assertEq(packed.unpackUint72(184), value2);
    }

    function test_uint192_and_uint64(uint192 value1, uint64 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint192(value1, 0);
        packed = packed.packUint64(value2, 192);

        assertEq(packed.unpackUint192(0), value1);
        assertEq(packed.unpackUint64(192), value2);
    }

    function test_uint200_and_uint56(uint200 value1, uint56 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint200(value1, 0);
        packed = packed.packUint56(value2, 200);

        assertEq(packed.unpackUint200(0), value1);
        assertEq(packed.unpackUint56(200), value2);
    }

    function test_uint208_and_uint48(uint208 value1, uint48 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint208(value1, 0);
        packed = packed.packUint48(value2, 208);

        assertEq(packed.unpackUint208(0), value1);
        assertEq(packed.unpackUint48(208), value2);
    }

    function test_uint216_and_uint40(uint216 value1, uint40 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint216(value1, 0);
        packed = packed.packUint40(value2, 216);

        assertEq(packed.unpackUint216(0), value1);
        assertEq(packed.unpackUint40(216), value2);
    }

    function test_uint224_and_uint32(uint224 value1, uint32 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint224(value1, 0);
        packed = packed.packUint32(value2, 224);

        assertEq(packed.unpackUint224(0), value1);
        assertEq(packed.unpackUint32(224), value2);
    }

    function test_uint232_and_uint24(uint232 value1, uint24 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint232(value1, 0);
        packed = packed.packUint24(value2, 232);

        assertEq(packed.unpackUint232(0), value1);
        assertEq(packed.unpackUint24(232), value2);
    }

    function test_uint240_and_uint16(uint240 value1, uint16 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint240(value1, 0);
        packed = packed.packUint16(value2, 240);

        assertEq(packed.unpackUint240(0), value1);
        assertEq(packed.unpackUint16(240), value2);
    }

    function test_uint248_and_uint8(uint248 value1, uint8 value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint248(value1, 0);
        packed = packed.packUint8(value2, 248);

        assertEq(packed.unpackUint248(0), value1);
        assertEq(packed.unpackUint8(248), value2);
    }
}
