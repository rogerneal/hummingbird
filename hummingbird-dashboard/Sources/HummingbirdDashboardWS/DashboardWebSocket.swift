//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Hummingbird
import HummingbirdDashboard
import HummingbirdWebSocket

extension RouterMethods where Context: WebSocketRequestContext {
    /// Register a WebSocket endpoint that pushes JSON metric snapshots to connected clients.
    ///
    /// Pair with ``DashboardConfiguration/liveSocketPath`` so the dashboard page knows
    /// where to connect, or use ``addDashboardWithLiveUpdates()`` which wires both up.
    ///
    /// Requires the application server to be built with
    /// ``HTTPServerBuilder/http1WebSocketUpgrade(webSocketRouter:)``.
    ///
    /// - Parameters:
    ///   - path: WebSocket upgrade path
    ///   - metrics: Metrics store to read snapshots from
    ///   - refreshIntervalMS: How often to push a new snapshot, in milliseconds
    @discardableResult
    public func addDashboardWebSocket(
        path: String = "/dashboard/api/live",
        metrics: DashboardMetrics = .shared,
        refreshIntervalMS: Int = 2000
    ) -> Self {
        let jsonEncoder = JSONEncoder()
        self.ws(RouterPath(path)) { inbound, outbound, _ in
            try await withThrowingTaskGroup(of: Void.self) { group in
                // drain inbound until the client closes the connection
                group.addTask {
                    do {
                        for try await _ in inbound {}
                    } catch is CancellationError {
                        return
                    }
                }
                // push snapshots on a timer
                group.addTask {
                    let intervalMS = max(refreshIntervalMS, 50)
                    while !Task.isCancelled {
                        do {
                            let data = try jsonEncoder.encode(metrics.snapshot())
                            let text = String(decoding: data, as: UTF8.self)
                            try await outbound.write(.text(text))
                            try await Task.sleep(for: .milliseconds(intervalMS))
                        } catch is CancellationError {
                            return
                        }
                    }
                }
                _ = try await group.next()
                group.cancelAll()
            }
        }
        return self
    }

    /// Add the dashboard UI, JSON API, Prometheus endpoint, and a WebSocket live stream.
    ///
    /// The router must use a ``WebSocketRequestContext`` (eg `BasicWebSocketRequestContext`)
    /// and the application server must use ``HTTPServerBuilder/http1WebSocketUpgrade(webSocketRouter:)``.
    ///
    /// ```swift
    /// let router = Router(context: BasicWebSocketRequestContext.self)
    /// router.addDashboardWithLiveUpdates()
    /// router.add(middleware: DashboardMiddleware())
    ///
    /// let app = Application(
    ///     router: router,
    ///     server: .http1WebSocketUpgrade(webSocketRouter: router)
    /// )
    /// ```
    @discardableResult
    public func addDashboardWithLiveUpdates(
        configuration: DashboardConfiguration = .init(),
        metrics: DashboardMetrics = .shared,
        livePath: String = "/dashboard/api/live"
    ) -> Self {
        var config = configuration
        config.liveSocketPath = livePath
        self.addDashboard(configuration: config, metrics: metrics)
        self.addDashboardWebSocket(
            path: livePath,
            metrics: metrics,
            refreshIntervalMS: config.refreshIntervalMS
        )
        return self
    }
}
