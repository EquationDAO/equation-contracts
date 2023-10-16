// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "solady/src/utils/LibBit.sol";

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
    return masked == 0 ? (0, false) : (uint8(LibBit.ffs(masked)), true);
}
