// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {BitMath} from "./BitMath.sol";

/// @title Packed tick initialized state library
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev The mapping uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values per word.
library TickBitmap {
    /// @notice Thrown when the tick is not enumerated by the tick spacing
    /// @param tick the invalid tick
    /// @param tickSpacing The tick spacing of the pool
    error TickMisaligned(int24 tick, int24 tickSpacing);

    /// @notice Computes the position in the mapping where the initialized bit for a tick lives
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word where the flag is stored
    function position(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        unchecked {
            wordPos = int16(tick >> 8);
            bitPos = uint8(int8(tick % 256));
        }
    }

    /// @notice Flips the initialized state for a given tick from false to true, or vice versa
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        unchecked {
            if (tick % tickSpacing != 0) revert TickMisaligned(tick, tickSpacing); // ensure that the tick is spaced
            (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
            uint256 mask = 1 << bitPos;
            self[wordPos] ^= mask;
        }
    }

    function compress(int24 tick, int24 spacing) internal pure returns (int24 compressed) {
        unchecked {
            compressed = tick / spacing;
            if (tick < 0 && tick % spacing != 0) compressed--; // round towards negative infinity
        }
    }

    function nextBitPosLte(uint256 word, uint8 bitPos) internal pure returns (uint8 nextBitPos, bool initialized) {
        unchecked {
            // all the 1s at or to the right of the current bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = word & mask;
            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            initialized = masked != 0;
            nextBitPos = initialized ? BitMath.mostSignificantBit(masked) : 0;
        }
    }

    function nextBitPosGt(uint256 word, uint8 bitPos) internal pure returns (uint8 nextBitPos, bool initialized) {
        unchecked {
            // all the 1s at or to the left of the bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = word & mask;
            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized = masked != 0;
            nextBitPos = initialized ? BitMath.leastSignificantBit(masked) : type(uint8).max;
        }
    }

    function tickInitialized(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing)
        internal
        view
        returns (bool initialized)
    {
        int24 compressed = compress(tick, tickSpacing);
        (int16 wordPos, uint8 bitPos) = position(compressed);
        uint256 word = self[wordPos];
        initialized = word & (1 << bitPos) != 0;
    }

    /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
    /// to the left (less than or equal to) or right (greater than) of the given tick
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param tickSpacing The spacing between usable ticks
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        unchecked {
            int24 compressed = compress(tick, tickSpacing);
            int16 wordPos;
            uint8 bitPos;
            uint8 nextBitPos;
            if (lte) {
                (wordPos, bitPos) = position(compressed);
                (nextBitPos, initialized) = nextBitPosLte(self[wordPos], bitPos);
            } else {
                // start from the word of the next tick, since the current tick state doesn't matter
                (wordPos, bitPos) = position(compressed + 1);
                (nextBitPos, initialized) = nextBitPosGt(self[wordPos], bitPos);
            }
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = ((int24(wordPos) << 8) + int24(uint24(nextBitPos))) * tickSpacing;
        }
    }
}
