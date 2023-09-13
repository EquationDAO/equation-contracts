// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

Side constant LONG = Side.wrap(1);
Side constant SHORT = Side.wrap(2);

type Side is uint8;

using {normalize, isLong, isShort, flip, eq as ==} for Side global;

function normalize(Side self) pure returns (Side) {
    return Side.unwrap(self) == Side.unwrap(LONG) ? LONG : SHORT;
}

function isLong(Side self) pure returns (bool) {
    return Side.unwrap(self) == Side.unwrap(LONG);
}

function isShort(Side self) pure returns (bool) {
    return Side.unwrap(self) == Side.unwrap(SHORT);
}

function eq(Side self, Side other) pure returns (bool) {
    return Side.unwrap(self) == Side.unwrap(other);
}

function flip(Side self) pure returns (Side) {
    return isLong(self) ? SHORT : LONG;
}
