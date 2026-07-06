//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Crypto
import Foundation
import _CryptoExtras

/// PBKDF2-SHA256 password hashing for dashboard admin credentials.
enum DashboardPasswordHasher {
    static let defaultIterations = 600_000
    static let minimumIterations = 210_000
    static let saltLength = 16
    static let keyLength = 32

    /// Hash a password for storage in configuration or secrets.
    ///
    /// The returned string encodes algorithm, iteration count, salt, and digest.
    static func hash(_ password: String, iterations: Int = defaultIterations) throws -> String {
        let rounds = try validatedRounds(iterations)
        let salt = randomSalt()
        let digest = try derive(password: password, salt: salt, rounds: rounds)
        return "pbkdf2-sha256:\(rounds):\(salt.base64EncodedString()):\(digest.base64EncodedString())"
    }

    /// Verify a plaintext password against a stored hash.
    static func verify(_ password: String, hash encoded: String) -> Bool {
        guard let (rounds, salt, expected) = parse(encoded) else { return false }
        guard let derived = try? derive(password: password, salt: salt, rounds: rounds) else {
            return false
        }
        return timingSafeEquals(derived, expected)
    }

    private static func derive(password: String, salt: Data, rounds: Int) throws -> Data {
        let passwordData = Data(password.utf8)
        let key = try KDF.Insecure.PBKDF2.deriveKey(
            from: passwordData,
            salt: salt,
            using: .sha256,
            outputByteCount: keyLength,
            unsafeUncheckedRounds: rounds
        )
        return key.withUnsafeBytes { Data($0) }
    }

    private static func validatedRounds(_ iterations: Int) throws -> Int {
        guard iterations >= minimumIterations else {
            throw DashboardPasswordHasherError.iterationsTooLow(minimum: minimumIterations)
        }
        return iterations
    }

    private static func randomSalt() -> Data {
        let key = SymmetricKey(size: .bits128)
        return Data(key.withUnsafeBytes { Array($0) })
    }

    private static func parse(_ encoded: String) -> (rounds: Int, salt: Data, digest: Data)? {
        let parts = encoded.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
            parts[0] == "pbkdf2-sha256",
            let rounds = Int(parts[1]),
            rounds >= minimumIterations,
            let salt = Data(base64Encoded: parts[2]),
            let digest = Data(base64Encoded: parts[3])
        else {
            return nil
        }
        return (rounds, salt, digest)
    }

    private static func timingSafeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.withUnsafeBytes { l in
            rhs.withUnsafeBytes { r in
                zip(l, r).reduce(into: UInt8(0)) { $0 |= $1.0 ^ $1.1 } == 0
            }
        }
    }
}

enum DashboardPasswordHasherError: Error, Equatable {
    case iterationsTooLow(minimum: Int)
}
