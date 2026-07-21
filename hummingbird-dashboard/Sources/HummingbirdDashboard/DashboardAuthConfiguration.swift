//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Hummingbird

/// Admin authentication settings for the dashboard.
public struct DashboardAuthConfiguration: Sendable {
    /// Admin username
    public var username: String
    /// PBKDF2-SHA256 password hash from ``hashPassword(_:)``. Never store plaintext passwords here.
    public var passwordHash: String
    /// Session cookie name
    public var sessionCookieName: String
    /// Session lifetime
    public var sessionTTL: Duration
    /// Login page path
    public var loginPath: String
    /// Optional bearer token for Prometheus `/metrics` scraping
    public var scrapeToken: String?
    /// When `true`, session cookies include the `Secure` attribute
    public var secureCookies: Bool

    public init(
        username: String,
        passwordHash: String,
        sessionCookieName: String = "hb_dashboard_session",
        sessionTTL: Duration = .seconds(8 * 60 * 60),
        loginPath: String = "/dashboard/login",
        scrapeToken: String? = nil,
        secureCookies: Bool = false
    ) {
        self.username = username
        self.passwordHash = passwordHash
        self.sessionCookieName = sessionCookieName
        self.sessionTTL = sessionTTL
        self.loginPath = loginPath
        self.scrapeToken = scrapeToken
        self.secureCookies = secureCookies
    }

    /// Hash a password for use in configuration or `DASHBOARD_ADMIN_PASSWORD_HASH`.
    public static func hashPassword(_ password: String, iterations: Int = 600_000) throws -> String {
        try DashboardPasswordHasher.hash(password, iterations: iterations)
    }

    /// Verify a plaintext password against a stored hash.
    public static func verifyPassword(_ password: String, passwordHash: String) -> Bool {
        DashboardPasswordHasher.verify(password, hash: passwordHash)
    }

    /// Load admin credentials from the process environment.
    ///
    /// - `DASHBOARD_ADMIN_USER` — admin username (required)
    /// - `DASHBOARD_ADMIN_PASSWORD_HASH` — PBKDF2-SHA256 hash from ``hashPassword(_:)`` (required)
    /// - `DASHBOARD_SCRAPE_TOKEN` — optional bearer token for `/metrics`
    public static func fromEnvironment(loginPath: String = "/dashboard/login") -> Self? {
        let env = Environment()
        guard let username = env.get("DASHBOARD_ADMIN_USER"),
            let passwordHash = env.get("DASHBOARD_ADMIN_PASSWORD_HASH")
        else {
            return nil
        }
        return .init(
            username: username,
            passwordHash: passwordHash,
            loginPath: loginPath,
            scrapeToken: env.get("DASHBOARD_SCRAPE_TOKEN")
        )
    }
}

/// Shared authentication state for dashboard HTTP routes and WebSocket upgrades.
public final class DashboardAuthState: @unchecked Sendable {
    public let configuration: DashboardAuthConfiguration
    let sessionStore: DashboardSessionStore

    public init(configuration: DashboardAuthConfiguration) {
        self.configuration = configuration
        self.sessionStore = DashboardSessionStore(configuration: configuration)
    }
}

extension DashboardAuthState {
    /// Returns whether the request has a valid admin session or bearer scrape token.
    public func isAuthorized(request: Request) async -> Bool {
        if let scrapeToken = configuration.scrapeToken,
            let header = request.headers[.authorization],
            header == "Bearer \(scrapeToken)"
        {
            return true
        }
        let cookieName = configuration.sessionCookieName
        guard let sessionID = request.cookies[cookieName]?.value else { return false }
        return await sessionStore.isValidSession(sessionID)
    }
}
