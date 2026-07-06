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
    /// Path of a WebSocket endpoint pushing live metric snapshots. When set, the
    /// dashboard page connects to it for push updates and only falls back to
    /// polling if the connection fails. Register the endpoint with
    /// `addDashboardWebSocket()` from the `HummingbirdDashboardWS` product.
    public var liveSocketPath: String?

    public init(
        path: String = "/dashboard",
        prometheusPath: String? = "/metrics",
        enableReset: Bool = false,
        refreshIntervalMS: Int = 2000,
        liveSocketPath: String? = nil
    ) {
        self.path = path
        self.prometheusPath = prometheusPath
        self.enableReset = enableReset
        self.refreshIntervalMS = refreshIntervalMS
        self.liveSocketPath = liveSocketPath
    }
}

extension RouterMethods {
    /// Add the dashboard UI and its API endpoints to this router.
    ///
    /// Registers the following routes (with the default configuration):
    /// - `GET /dashboard` — dashboard HTML page
    /// - `GET /dashboard/api/metrics` — metrics snapshot as JSON
    /// - `GET /dashboard/api/health` — health check
    /// - `GET /metrics` — Prometheus exposition format
    ///
    /// Pair this with ``DashboardMiddleware`` which records the metrics. Add the
    /// dashboard routes *before* the middleware so the dashboard's own endpoints
    /// are not included in the metrics:
    /// ```swift
    /// let router = Router()
    /// router.addDashboard()
    /// router.add(middleware: DashboardMiddleware())
    /// // your routes...
    /// ```
    ///
    /// - Parameters:
    ///   - configuration: Dashboard configuration
    ///   - metrics: Metrics store to read from. Use the same instance as the middleware.
    @discardableResult
    public func addDashboard(
        configuration: DashboardConfiguration = .init(),
        metrics: DashboardMetrics = .shared
    ) -> Self {
        let apiPath = "\(configuration.path)/api"
        let renderer = DashboardRenderer(
            metricsAPIPath: "\(apiPath)/metrics",
            refreshIntervalMS: configuration.refreshIntervalMS,
            liveSocketPath: configuration.liveSocketPath,
            resetAPIPath: configuration.enableReset ? "\(apiPath)/reset" : nil
        )
        let jsonEncoder = JSONEncoder()
        let dashboardHTML = renderer.html()

        // dashboard HTML page
        let htmlHandler: @Sendable (Request, Context) async throws -> Response = { _, _ in
            Response(
                status: .ok,
                headers: [
                    .contentType: "text/html; charset=utf-8",
                    .cacheControl: "no-store",
                ],
                body: .init(byteBuffer: ByteBuffer(string: dashboardHTML))
            )
        }
        self.get(RouterPath(configuration.path), use: htmlHandler)

        // JSON metrics snapshot
        self.get(RouterPath("\(apiPath)/metrics")) { _, _ in
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

        // health check
        self.get(RouterPath("\(apiPath)/health")) { _, _ in
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

        // metrics reset (opt-in, for development)
        if configuration.enableReset {
            self.post(RouterPath("\(apiPath)/reset")) { _, _ in
                metrics.reset()
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(string: #"{"status":"reset"}"#))
                )
            }
        }

        // Prometheus exposition endpoint
        if let prometheusPath = configuration.prometheusPath {
            let exporter = PrometheusExporter()
            self.get(RouterPath(prometheusPath)) { _, _ in
                Response(
                    status: .ok,
                    headers: [.contentType: "text/plain; version=0.0.4; charset=utf-8"],
                    body: .init(byteBuffer: ByteBuffer(string: exporter.render(metrics.snapshot())))
                )
            }
        }

        return self
    }
}

struct HealthResponse: Encodable {
    let status: String
    let uptimeSeconds: Double
    let totalRequests: Int
    let inFlight: Int
    let errorRatePercent: Double
}
