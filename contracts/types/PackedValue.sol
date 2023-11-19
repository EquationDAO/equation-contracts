// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

type PackedValue is uint256;

using {
    packUint16,
    unpackUint16,
    packUint24,
    unpackUint24,
    packUint32,
    unpackUint32,
    packUint200,
    unpackUint200,
    packUint216,
    unpackUint216,
    packUint232,
    unpackUint232
} for PackedValue global;

function packUint16(PackedValue self, uint16 value, uint8 position) pure returns (PackedValue) {
    return PackedValue.wrap(PackedValue.unwrap(self) | (uint256(value) << position));
}

function unpackUint16(PackedValue self, uint8 position) pure returns (uint16) {
    return uint16((PackedValue.unwrap(self) >> position) & 0xffff);
}

function packUint24(PackedValue self, uint24 value, uint8 position) pure returns (PackedValue) {
    return PackedValue.wrap(PackedValue.unwrap(self) | (uint256(value) << position));
}

function unpackUint24(PackedValue self, uint8 position) pure returns (uint24) {
    return uint24((PackedValue.unwrap(self) >> position) & 0xffffff);
}

function packUint32(PackedValue self, uint32 value, uint8 position) pure returns (PackedValue) {
    return PackedValue.wrap(PackedValue.unwrap(self) | (uint256(value) << position));
}

function unpackUint32(PackedValue self, uint8 position) pure returns (uint32) {
    return uint32((PackedValue.unwrap(self) >> position) & 0xffffffff);
}

function packUint200(PackedValue self, uint200 value, uint8 position) pure returns (PackedValue) {
    return PackedValue.wrap(PackedValue.unwrap(self) | (uint256(value) << position));
}

function unpackUint200(PackedValue self, uint8 position) pure returns (uint200) {
    return uint200((PackedValue.unwrap(self) >> position) & 0xffffffffffffffffffffffffffffffffffffffffffffffffff);
}

function packUint216(PackedValue self, uint216 value, uint8 position) pure returns (PackedValue) {
    return PackedValue.wrap(PackedValue.unwrap(self) | (uint256(value) << position));
}

function unpackUint216(PackedValue self, uint8 position) pure returns (uint216) {
    return uint216((PackedValue.unwrap(self) >> position) & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffff);
}

function packUint232(PackedValue self, uint232 value, uint8 position) pure returns (PackedValue) {
    return PackedValue.wrap(PackedValue.unwrap(self) | (uint256(value) << position));
}

function unpackUint232(PackedValue self, uint8 position) pure returns (uint232) {
    return
        uint232((PackedValue.unwrap(self) >> position) & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
}
