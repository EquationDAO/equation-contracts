// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

type Bitmap is uint256;

using {flip, searchNextPosition} for Bitmap global;

/// @dev Flip the bit at the specified position in the given bitmap
/// @param self The original bitmap
/// @param position The position of the bit to be flipped
/// @return The updated bitmap after flipping the specified bit
function flip(Bitmap self, uint8 position) pure returns (Bitmap) {
    return Bitmap.wrap(Bitmap.unwrap(self) ^ (1 << position));
}

/// @dev Search for the next position in a bitmap starting from a given index
/// @param self The bitmap to search within
/// @param startInclusive The index to start the search from (inclusive)
/// @return next The next position found in the bitmap
/// @return found A boolean indicating whether the next position was found or not
function searchNextPosition(Bitmap self, uint8 startInclusive) pure returns (uint8 next, bool found) {
    uint256 mask = ~uint256(0) << startInclusive;
    uint256 masked = Bitmap.unwrap(self) & mask;
    return masked == 0 ? (0, false) : (leastSignificantBit(masked), true);
}

/// @notice Returns the index of the least significant bit of the number,
///     where the least significant bit is at index 0 and the most significant bit is at index 255
/// @dev The function satisfies the property:
///     (x & 2**leastSignificantBit(x)) != 0 and (x & (2**(leastSignificantBit(x)) - 1)) == 0)
/// @param x the value for which to compute the least significant bit, must be greater than 0
/// @return r the index of the least significant bit
function leastSignificantBit(uint256 x) pure returns (uint8 r) {
    require(x > 0);

    r = 255;
    unchecked {
        if (x & type(uint128).max > 0) r -= 128;
        else x >>= 128;

        if (x & type(uint64).max > 0) r -= 64;
        else x >>= 64;

        if (x & type(uint32).max > 0) r -= 32;
        else x >>= 32;

        if (x & type(uint16).max > 0) r -= 16;
        else x >>= 16;

        if (x & type(uint8).max > 0) r -= 8;
        else x >>= 8;

        if (x & 0xf > 0) r -= 4;
        else x >>= 4;

        if (x & 0x3 > 0) r -= 2;
        else x >>= 2;

        if (x & 0x1 > 0) r -= 1;
    }
}
