//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import CryptoKit
import Foundation
import Hummingbird

actor DashboardSessionStore {
    struct Session: Sendable {
        let id: String
        let expiresAt: Date
        var csrfToken: String?
    }

    private let configuration: DashboardAuthConfiguration
    private var sessions: [String: Session] = [:]
    private var loginCSRF: [String: Date] = [:]

    init(configuration: DashboardAuthConfiguration) {
        self.configuration = configuration
    }

    func createSession() -> String {
        self.purgeExpired()
        let id = Self.randomToken()
        let expiresAt = Date().addingTimeInterval(TimeInterval(configuration.sessionTTL.components.seconds))
        sessions[id] = Session(id: id, expiresAt: expiresAt, csrfToken: nil)
        return id
    }

    func isValidSession(_ id: String) -> Bool {
        self.purgeExpired()
        guard let session = sessions[id] else { return false }
        return session.expiresAt > Date()
    }

    func revokeSession(_ id: String) {
        sessions[id] = nil
    }

    func issueCSRFToken(for sessionID: String) -> String? {
        self.purgeExpired()
        guard var session = sessions[sessionID] else { return nil }
        let token = Self.randomToken()
        session.csrfToken = token
        sessions[sessionID] = session
        return token
    }

    func validateCSRF(sessionID: String, token: String) -> Bool {
        self.purgeExpired()
        guard let session = sessions[sessionID], let expected = session.csrfToken else { return false }
        return Self.timingSafeEquals(expected, token)
    }

    func createLoginCSRFToken() -> String {
        self.purgeExpired()
        let token = Self.randomToken()
        loginCSRF[token] = Date().addingTimeInterval(600)
        return token
    }

    func validateLoginCSRF(_ token: String) -> Bool {
        self.purgeExpired()
        guard let expiresAt = loginCSRF[token], expiresAt > Date() else { return false }
        loginCSRF[token] = nil
        return true
    }

    private func purgeExpired() {
        let now = Date()
        sessions = sessions.filter { $0.value.expiresAt > now }
        loginCSRF = loginCSRF.filter { $0.value > now }
    }

    private static func randomToken() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    static func timingSafeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let l = Array(lhs.utf8)
        let r = Array(rhs.utf8)
        guard l.count == r.count else { return false }
        return zip(l, r).reduce(into: UInt8(0)) { $0 |= $1.0 ^ $1.1 } == 0
    }
}

enum DashboardAuthCredentials {
    static func usernameMatches(_ provided: String, expected: String) -> Bool {
        DashboardSessionStore.timingSafeEquals(provided, expected)
    }

    static func passwordMatches(_ provided: String, hash: String) -> Bool {
        DashboardPasswordHasher.verify(provided, hash: hash)
    }
}
