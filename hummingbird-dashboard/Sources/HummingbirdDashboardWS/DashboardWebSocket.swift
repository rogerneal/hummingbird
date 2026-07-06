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
    /// When ``DashboardAuthState`` is provided, the WebSocket upgrade requires a valid admin session cookie.
    @discardableResult
    public func addDashboardWebSocket(
        path: String = "/dashboard/api/live",
        metrics: DashboardMetrics = .shared,
        refreshIntervalMS: Int = 2000,
        authState: DashboardAuthState? = nil
    ) -> Self {
        let jsonEncoder = JSONEncoder()
        self.ws(
            RouterPath(path),
            shouldUpgrade: { request, _ in
                if let authState {
                    guard await authState.isAuthorized(request: request) else {
                        throw HTTPError(.unauthorized)
                    }
                }
                return .upgrade()
            }
        ) { inbound, outbound, _ in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        for try await _ in inbound {}
                    } catch is CancellationError {
                        return
                    }
                }
                group.addTask {
                    while !Task.isCancelled {
                        do {
                            let data = try jsonEncoder.encode(metrics.snapshot())
                            let text = String(decoding: data, as: UTF8.self)
                            try await outbound.write(.text(text))
                            try await Task.sleep(for: .milliseconds(refreshIntervalMS))
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
    @discardableResult
    public func addDashboardWithLiveUpdates(
        configuration: DashboardConfiguration = .init(),
        metrics: DashboardMetrics = .shared,
        livePath: String = "/dashboard/api/live"
    ) -> Self {
        var config = configuration
        config.liveSocketPath = livePath
        let (_, authState) = self.addDashboard(configuration: config, metrics: metrics)
        self.addDashboardWebSocket(
            path: livePath,
            metrics: metrics,
            refreshIntervalMS: config.refreshIntervalMS,
            authState: authState
        )
        return self
    }
}
