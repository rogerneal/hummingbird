//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

/// Allocation-free ASCII case-insensitive string comparisons for router matching.
///
/// Only ASCII letters `A`–`Z` / `a`–`z` are folded. Non-ASCII code units are compared as-is.
/// This avoids `String.lowercased()`, which allocates a new string for each call.
package enum ASCIICaseInsensitive {
    @inline(__always)
    package static func asciiLowercase(_ byte: UInt8) -> UInt8 {
        // A...Z → a...z
        (byte &- 65) < 26 ? byte &+ 32 : byte
    }

    /// Returns whether both substrings are equal when compared ASCII case-insensitively.
    package static func equals(_ lhs: Substring, _ rhs: Substring) -> Bool {
        let left = lhs.utf8
        let right = rhs.utf8
        guard left.count == right.count else { return false }
        var leftIndex = left.startIndex
        var rightIndex = right.startIndex
        while leftIndex != left.endIndex {
            if self.asciiLowercase(left[leftIndex]) != self.asciiLowercase(right[rightIndex]) {
                return false
            }
            left.formIndex(after: &leftIndex)
            right.formIndex(after: &rightIndex)
        }
        return true
    }

    /// Returns whether `string` has an ASCII case-insensitive suffix of `suffix`.
    package static func hasSuffix(_ string: Substring, _ suffix: Substring) -> Bool {
        let left = string.utf8
        let right = suffix.utf8
        guard left.count >= right.count else { return false }
        var leftIndex = left.index(left.endIndex, offsetBy: -right.count)
        var rightIndex = right.startIndex
        while rightIndex != right.endIndex {
            if self.asciiLowercase(left[leftIndex]) != self.asciiLowercase(right[rightIndex]) {
                return false
            }
            left.formIndex(after: &leftIndex)
            right.formIndex(after: &rightIndex)
        }
        return true
    }

    /// Returns whether `string` has an ASCII case-insensitive prefix of `prefix`.
    package static func hasPrefix(_ string: Substring, _ prefix: Substring) -> Bool {
        let left = string.utf8
        let right = prefix.utf8
        guard left.count >= right.count else { return false }
        var leftIndex = left.startIndex
        var rightIndex = right.startIndex
        while rightIndex != right.endIndex {
            if self.asciiLowercase(left[leftIndex]) != self.asciiLowercase(right[rightIndex]) {
                return false
            }
            left.formIndex(after: &leftIndex)
            right.formIndex(after: &rightIndex)
        }
        return true
    }
}
