//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Hummingbird
import NIOCore

/// Configuration options for the dashboard routes.
public struct DashboardConfiguration: Sendable {
    /// Path the dashboard HTML page is served from
    public var path: String
    /// Path the Prometheus exposition endpoint is served from. Set to `nil` to disable.
    public var prometheusPath: String?
    /// Whether to register `POST <path>/api/reset` which resets all metrics.
    /// Enable this in development only.
    public var enableReset: Bool
    /// How often the dashboard page polls for new data, in milliseconds
    public var refreshIntervalMS: Int
    /// Path of a WebSocket endpoint pushing live metric snapshots. When set, the dashboard page connects to it for push updates and only falls back to polling if the connection fails. Register the endpoint with `addDashboardWebSocket()` from the `HummingbirdDashboardWS` product.
    public var liveSocketPath: String?
    /// Optional admin authentication. When set, all dashboard endpoints require login.
    public var auth: DashboardAuthConfiguration?

    public init(
        path: String = "/dashboard",
        prometheusPath: String? = "/metrics",
        enableReset: Bool = false,
        refreshIntervalMS: Int = 2000,
        liveSocketPath: String? = nil,
        auth: DashboardAuthConfiguration? = nil
    ) {
        self.path = path
        self.prometheusPath = prometheusPath
        self.enableReset = enableReset
        self.refreshIntervalMS = refreshIntervalMS
        self.liveSocketPath = liveSocketPath
        self.auth = auth
    }
}

extension RouterMethods {
    /// Add the dashboard UI and its API endpoints to this router.
    ///
    /// When ``DashboardConfiguration/auth`` is set, login routes are registered and all
    /// dashboard endpoints require a valid admin session. Returns the shared
    /// ``DashboardAuthState`` when auth is enabled (pass it to ``addDashboardWebSocket``).
    @discardableResult
    public func addDashboard(
        configuration: DashboardConfiguration = .init(),
        metrics: DashboardMetrics = .shared,
        authState: DashboardAuthState? = nil
    ) -> (router: Self, authState: DashboardAuthState?) {
        var resolvedAuth = authState
        if resolvedAuth == nil, var authConfig = configuration.auth {
            if authConfig.loginPath == "/dashboard/login", configuration.path != "/dashboard" {
                authConfig.loginPath = "\(configuration.path)/login"
            }
            resolvedAuth = DashboardAuthState(configuration: authConfig)
        }

        if let authState = resolvedAuth {
            self.registerAuthRoutes(configuration: configuration, authState: authState)
        }

        let apiPath = "\(configuration.path)/api"
        let resetPath = configuration.enableReset ? "\(apiPath)/reset" : nil
        let loginPath = resolvedAuth?.configuration.loginPath
        let renderer = DashboardRenderer(
            metricsAPIPath: "\(apiPath)/metrics",
            refreshIntervalMS: configuration.refreshIntervalMS,
            liveSocketPath: configuration.liveSocketPath,
            resetAPIPath: resetPath,
            loginPath: loginPath
        )
        let jsonEncoder = JSONEncoder()
        let exporter = PrometheusExporter()

        if let authState = resolvedAuth {
            let middleware = DashboardAuthMiddleware<Context>(authState: authState, allowBearerScrape: false)
            var dashboardGroup = self.group(RouterPath(configuration.path)).add(middleware: middleware)

            dashboardGroup = dashboardGroup.get("") { request, _ in
                var csrfToken: String?
                if let sessionID = request.cookies[authState.configuration.sessionCookieName]?.value {
                    csrfToken = await authState.sessionStore.issueCSRFToken(for: sessionID)
                }
                let html = renderer.html(csrfToken: csrfToken)
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/html; charset=utf-8",
                        .cacheControl: "no-store",
                    ],
                    body: .init(byteBuffer: ByteBuffer(string: html))
                )
            }

            dashboardGroup = dashboardGroup.get("api/metrics") { _, _ in
                let data = try jsonEncoder.encode(metrics.snapshot())
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "application/json",
                        .cacheControl: "no-store",
                    ],
                    body: .init(byteBuffer: ByteBuffer(bytes: data))
                )
            }

            dashboardGroup = dashboardGroup.get("api/health") { _, _ in
                let snapshot = metrics.snapshot()
                let health = HealthResponse(
                    status: "ok",
                    uptimeSeconds: snapshot.uptimeSeconds,
                    totalRequests: snapshot.totalRequests,
                    inFlight: snapshot.inFlight,
                    errorRatePercent: snapshot.errorRatePercent
                )
                let data = try jsonEncoder.encode(health)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(bytes: data))
                )
            }

            if configuration.enableReset {
                dashboardGroup = dashboardGroup.post("api/reset") { request, _ in
                    try await Self.validateCSRF(request: request, authState: authState)
                    metrics.reset()
                    return Response(
                        status: .ok,
                        headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: ByteBuffer(string: #"{"status":"reset"}"#))
                    )
                }
            }

            if let prometheusPath = configuration.prometheusPath {
                let scrapeMiddleware = DashboardAuthMiddleware<Context>(authState: authState, allowBearerScrape: true)
                _ = self.group(RouterPath(prometheusPath)).add(middleware: scrapeMiddleware).get("") { _, _ in
                    Response(
                        status: .ok,
                        headers: [.contentType: "text/plain; version=0.0.4; charset=utf-8"],
                        body: .init(byteBuffer: ByteBuffer(string: exporter.render(metrics.snapshot())))
                    )
                }
            }
        } else {
            let dashboardHTML = renderer.html()
            _ = self.get(RouterPath(configuration.path)) { _, _ in
                Response(
                    status: .ok,
                    headers: [
                        .contentType: "text/html; charset=utf-8",
                        .cacheControl: "no-store",
                    ],
                    body: .init(byteBuffer: ByteBuffer(string: dashboardHTML))
                )
            }

            var dashboardGroup = self.group(RouterPath(configuration.path))
            dashboardGroup = dashboardGroup.get("api/metrics") { _, _ in
                let data = try jsonEncoder.encode(metrics.snapshot())
                return Response(
                    status: .ok,
                    headers: [
                        .contentType: "application/json",
                        .cacheControl: "no-store",
                    ],
                    body: .init(byteBuffer: ByteBuffer(bytes: data))
                )
            }
            dashboardGroup = dashboardGroup.get("api/health") { _, _ in
                let snapshot = metrics.snapshot()
                let health = HealthResponse(
                    status: "ok",
                    uptimeSeconds: snapshot.uptimeSeconds,
                    totalRequests: snapshot.totalRequests,
                    inFlight: snapshot.inFlight,
                    errorRatePercent: snapshot.errorRatePercent
                )
                let data = try jsonEncoder.encode(health)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(bytes: data))
                )
            }
            if configuration.enableReset {
                dashboardGroup = dashboardGroup.post("api/reset") { _, _ in
                    metrics.reset()
                    return Response(
                        status: .ok,
                        headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: ByteBuffer(string: #"{"status":"reset"}"#))
                    )
                }
            }

            if let prometheusPath = configuration.prometheusPath {
                _ = self.get(RouterPath(prometheusPath)) { _, _ in
                    Response(
                        status: .ok,
                        headers: [.contentType: "text/plain; version=0.0.4; charset=utf-8"],
                        body: .init(byteBuffer: ByteBuffer(string: exporter.render(metrics.snapshot())))
                    )
                }
            }
        }

        return (self, resolvedAuth)
    }

    private func registerAuthRoutes(configuration: DashboardConfiguration, authState: DashboardAuthState) {
        let loginPath = authState.configuration.loginPath
        let logoutPath = "\(configuration.path)/logout"

        self.get(RouterPath(loginPath)) { request, _ in
            let csrf = await authState.sessionStore.createLoginCSRFToken()
            let next = request.uri.queryParameters["next"].map(String.init)
            let html = DashboardLoginRenderer(
                loginPath: loginPath,
                csrfToken: csrf,
                errorMessage: nil,
                nextPath: next
            ).html()
            return Response(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8", .cacheControl: "no-store"],
                body: .init(byteBuffer: ByteBuffer(string: html))
            )
        }

        self.post(RouterPath(loginPath)) { request, _ in
            let buffer = try await request.body.collect(upTo: 64 * 1024)
            let fields = DashboardFormParser.parse(String(buffer: buffer))
            let config = authState.configuration

            guard await authState.sessionStore.validateLoginCSRF(fields["csrf"] ?? ""),
                DashboardAuthCredentials.usernameMatches(fields["username"] ?? "", expected: config.username),
                DashboardAuthCredentials.passwordMatches(fields["password"] ?? "", hash: config.passwordHash)
            else {
                let csrf = await authState.sessionStore.createLoginCSRFToken()
                let html = DashboardLoginRenderer(
                    loginPath: loginPath,
                    csrfToken: csrf,
                    errorMessage: "Invalid username or password.",
                    nextPath: fields["next"]
                ).html()
                return Response(
                    status: .unauthorized,
                    headers: [.contentType: "text/html; charset=utf-8"],
                    body: .init(byteBuffer: ByteBuffer(string: html))
                )
            }

            let sessionID = await authState.sessionStore.createSession()
            let cookie = try DashboardAuthCookies.sessionCookie(value: sessionID, configuration: config)
            let next = fields["next"].flatMap { $0.isEmpty ? nil : $0 } ?? configuration.path
            return Response(
                status: .found,
                headers: [.location: next, .setCookie: cookie.description]
            )
        }

        self.post(RouterPath(logoutPath)) { request, _ in
            let cookieName = authState.configuration.sessionCookieName
            if let sessionID = request.cookies[cookieName]?.value {
                await authState.sessionStore.revokeSession(sessionID)
            }
            let cleared = try DashboardAuthCookies.clearSessionCookie(configuration: authState.configuration)
            return Response(
                status: .found,
                headers: [
                    .location: loginPath,
                    .setCookie: cleared.description,
                ]
            )
        }
    }

    private static func validateCSRF(request: Request, authState: DashboardAuthState) async throws {
        let buffer = try await request.body.collect(upTo: 64 * 1024)
        let fields = DashboardFormParser.parse(String(buffer: buffer))
        let cookieName = authState.configuration.sessionCookieName
        guard let sessionID = request.cookies[cookieName]?.value,
            let csrf = fields["csrf"],
            await authState.sessionStore.validateCSRF(sessionID: sessionID, token: csrf)
        else {
            throw HTTPError(.forbidden, message: "Invalid CSRF token")
        }
    }
}

struct HealthResponse: Encodable {
    let status: String
    let uptimeSeconds: Double
    let totalRequests: Int
    let inFlight: Int
    let errorRatePercent: Double
}
