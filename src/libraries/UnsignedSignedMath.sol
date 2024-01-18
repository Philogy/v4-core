// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title Math functions that operate between a mix of signed and unsigned types
library UnsignedSignedMath {
    /// @notice Returns x + y
    /// @dev If y is negative x will decrease else increase
    /// @param x Unsigned term
    /// @param y Signed term
    function add(uint128 x, int128 y) internal pure returns (uint128 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Add x and y and truncate result to 128-bits.
            z := shr(128, shl(128, add(x, y)))

            // Check that no overflow or underflow occured.
            if iszero(eq(gt(z, x), sgt(y, 0))) {
                // Emit a standard overflow/underflow error (`Panic(0x11)`).
                mstore(0x00, 0x4e487b71)
                mstore(0x20, 0x11)
            }
        }
    }
}
