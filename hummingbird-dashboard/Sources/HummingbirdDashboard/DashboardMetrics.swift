//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import NIOConcurrencyHelpers

/// Thread-safe, in-memory metrics store powering the Hummingbird dashboard.
///
/// Metrics are recorded by ``DashboardMiddleware`` and read via ``snapshot()``.
/// All state is protected by a single lock, making the type safely `Sendable`.
public final class DashboardMetrics: Sendable {
    /// Shared default instance used when no explicit instance is provided.
    public static let shared = DashboardMetrics()

    /// Number of latency samples kept for percentile calculations.
    static let maxLatencySamples = 1000
    /// Number of per-second buckets kept for the requests/second chart.
    static let historySeconds = 60
    /// Number of recent requests kept for the activity feed.
    static let maxRecentRequests = 20
    /// Maximum number of distinct route entries tracked. Requests to paths beyond
    /// this limit (eg random 404 scans) are grouped under a single "(other)" entry.
    static let maxTrackedRoutes = 200

    struct StoredRequest {
        var epoch: Double
        var method: String
        var path: String
        var status: Int
        var duration: Double
        var responseBytes: Int
    }

    struct State {
        var startDate = Date()
        var totalRequests = 0
        var totalErrors = 0
        var inFlight = 0
        var peakInFlight = 0
        var dataInBytes = 0
        var dataOutBytes = 0
        var statusCounts = StatusCounts()
        var methodCounts: [String: Int] = [:]
        var routes: [String: RouteStats] = [:]
        var latencySamples: [Double] = []
        var latencyInsertIndex = 0
        var buckets = [Int](repeating: 0, count: DashboardMetrics.historySeconds)
        var bucketEpoch = Int(Date().timeIntervalSince1970)
        var peakRPS = 0
        var recentRequests: [StoredRequest] = []

        /// Shift the per-second buckets forward so the last bucket represents `epochSecond`.
        mutating func advanceBuckets(to epochSecond: Int) {
            let delta = epochSecond - self.bucketEpoch
            guard delta > 0 else { return }
            if delta >= self.buckets.count {
                self.buckets = [Int](repeating: 0, count: self.buckets.count)
            } else {
                self.buckets.removeFirst(delta)
                self.buckets.append(contentsOf: repeatElement(0, count: delta))
            }
            self.bucketEpoch = epochSecond
        }
    }

    let state: NIOLockedValueBox<State>

    /// Initialize an empty metrics store.
    public init() {
        self.state = .init(State())
    }

    /// Record that a request has started being processed.
    public func requestStarted() {
        self.state.withLockedValue { state in
            state.inFlight += 1
            state.peakInFlight = max(state.peakInFlight, state.inFlight)
        }
    }

    /// Record a finished request.
    ///
    /// - Parameters:
    ///   - method: HTTP method, eg "GET"
    ///   - path: Route template if available (eg "/api/users/{id}"), otherwise the request path
    ///   - status: HTTP response status code
    ///   - duration: Time taken to process the request, in seconds
    ///   - requestBytes: Size of the request body in bytes
    ///   - responseBytes: Size of the response body in bytes
    public func requestFinished(
        method: String,
        path: String,
        status: Int,
        duration: Double,
        requestBytes: Int,
        responseBytes: Int
    ) {
        let now = Date().timeIntervalSince1970
        self.state.withLockedValue { state in
            state.inFlight = max(state.inFlight - 1, 0)
            state.totalRequests += 1
            state.dataInBytes += requestBytes
            state.dataOutBytes += responseBytes
            state.methodCounts[method, default: 0] += 1
            state.statusCounts.record(status)
            if status >= 400 {
                state.totalErrors += 1
            }

            // latency ring buffer
            if state.latencySamples.count < Self.maxLatencySamples {
                state.latencySamples.append(duration)
            } else {
                state.latencySamples[state.latencyInsertIndex] = duration
                state.latencyInsertIndex = (state.latencyInsertIndex + 1) % Self.maxLatencySamples
            }

            // requests/second history
            state.advanceBuckets(to: Int(now))
            state.buckets[state.buckets.count - 1] += 1
            state.peakRPS = max(state.peakRPS, state.buckets[state.buckets.count - 1])

            // per-route stats, capped to avoid unbounded cardinality
            let routeKey: String
            if state.routes[path] != nil || state.routes.count < Self.maxTrackedRoutes {
                routeKey = path
            } else {
                routeKey = "(other)"
            }
            var route = state.routes[routeKey] ?? RouteStats()
            route.requests += 1
            route.totalDuration += duration
            route.maxDuration = max(route.maxDuration, duration)
            if status >= 400 {
                route.errors += 1
            }
            route.lastStatus = status
            state.routes[routeKey] = route

            // recent request feed
            state.recentRequests.append(
                StoredRequest(
                    epoch: now,
                    method: method,
                    path: path,
                    status: status,
                    duration: duration,
                    responseBytes: responseBytes
                )
            )
            if state.recentRequests.count > Self.maxRecentRequests {
                state.recentRequests.removeFirst(state.recentRequests.count - Self.maxRecentRequests)
            }
        }
    }

    /// Reset all metrics. The server start date (uptime) is preserved.
    public func reset() {
        self.state.withLockedValue { state in
            let startDate = state.startDate
            state = State()
            state.startDate = startDate
        }
    }

    /// Capture a consistent snapshot of all metrics.
    public func snapshot() -> DashboardSnapshot {
        let now = Date()
        return self.state.withLockedValue { state in
            state.advanceBuckets(to: Int(now.timeIntervalSince1970))

            let sortedLatencies = state.latencySamples.sorted()
            func percentile(_ q: Double) -> Double {
                guard !sortedLatencies.isEmpty else { return 0 }
                let index = Int(Double(sortedLatencies.count - 1) * q)
                return sortedLatencies[index]
            }
            let averageLatency =
                sortedLatencies.isEmpty
                ? 0 : sortedLatencies.reduce(0, +) / Double(sortedLatencies.count)

            let uptime = now.timeIntervalSince(state.startDate)
            let window = min(Double(state.buckets.count), max(uptime, 1))
            let requestsInWindow = state.buckets.reduce(0, +)

            let routes = state.routes.map { path, stats in
                RouteSnapshot(
                    path: path,
                    requests: stats.requests,
                    errors: stats.errors,
                    averageDuration: stats.averageDuration,
                    maxDuration: stats.maxDuration,
                    errorRatePercent: stats.requests > 0
                        ? Double(stats.errors) / Double(stats.requests) * 100 : 0,
                    lastStatus: stats.lastStatus
                )
            }
            .sorted { $0.requests > $1.requests }

            let recents = state.recentRequests.reversed().map { stored in
                RecentRequest(
                    ageSeconds: max(now.timeIntervalSince1970 - stored.epoch, 0),
                    method: stored.method,
                    path: stored.path,
                    status: stored.status,
                    duration: stored.duration,
                    responseBytes: stored.responseBytes
                )
            }

            return DashboardSnapshot(
                uptimeSeconds: uptime,
                totalRequests: state.totalRequests,
                totalErrors: state.totalErrors,
                errorRatePercent: state.totalRequests > 0
                    ? Double(state.totalErrors) / Double(state.totalRequests) * 100 : 0,
                inFlight: state.inFlight,
                peakInFlight: state.peakInFlight,
                requestsPerSecond: Double(requestsInWindow) / window,
                currentRPS: state.buckets[state.buckets.count - 1],
                peakRPS: state.peakRPS,
                averageLatency: averageLatency,
                p50Latency: percentile(0.50),
                p90Latency: percentile(0.90),
                p99Latency: percentile(0.99),
                latencySampleCount: sortedLatencies.count,
                dataInBytes: state.dataInBytes,
                dataOutBytes: state.dataOutBytes,
                statusCounts: state.statusCounts,
                methodCounts: state.methodCounts,
                routes: routes,
                requestsPerSecondHistory: state.buckets,
                recentRequests: recents
            )
        }
    }
}

/// Counts of responses grouped by status code class.
public struct StatusCounts: Codable, Sendable, Equatable {
    /// 1xx responses
    public var informational = 0
    /// 2xx responses
    public var success = 0
    /// 3xx responses
    public var redirect = 0
    /// 4xx responses
    public var clientError = 0
    /// 5xx responses
    public var serverError = 0

    public init() {}

    mutating func record(_ status: Int) {
        switch status {
        case 100..<200: self.informational += 1
        case 200..<300: self.success += 1
        case 300..<400: self.redirect += 1
        case 400..<500: self.clientError += 1
        case 500..<600: self.serverError += 1
        default: break
        }
    }
}

/// Accumulated statistics for a single route.
struct RouteStats {
    var requests = 0
    var errors = 0
    var totalDuration: Double = 0
    var maxDuration: Double = 0
    var lastStatus = 0

    var averageDuration: Double {
        self.requests > 0 ? self.totalDuration / Double(self.requests) : 0
    }
}

/// Point-in-time statistics for a single route.
public struct RouteSnapshot: Codable, Sendable {
    public let path: String
    public let requests: Int
    public let errors: Int
    /// Average request duration in seconds
    public let averageDuration: Double
    /// Maximum request duration in seconds
    public let maxDuration: Double
    public let errorRatePercent: Double
    /// Status code of the most recent response
    public let lastStatus: Int
}

/// A recently processed request.
public struct RecentRequest: Codable, Sendable {
    /// How long ago the request finished, in seconds
    public let ageSeconds: Double
    public let method: String
    public let path: String
    public let status: Int
    /// Request duration in seconds
    public let duration: Double
    public let responseBytes: Int
}

/// A consistent point-in-time snapshot of all dashboard metrics.
public struct DashboardSnapshot: Codable, Sendable {
    public let uptimeSeconds: Double
    public let totalRequests: Int
    public let totalErrors: Int
    public let errorRatePercent: Double
    public let inFlight: Int
    public let peakInFlight: Int
    /// Average requests per second over the last 60 seconds
    public let requestsPerSecond: Double
    /// Requests recorded in the current second
    public let currentRPS: Int
    /// Highest requests per second observed
    public let peakRPS: Int
    /// Average latency in seconds over the sample window
    public let averageLatency: Double
    public let p50Latency: Double
    public let p90Latency: Double
    public let p99Latency: Double
    public let latencySampleCount: Int
    public let dataInBytes: Int
    public let dataOutBytes: Int
    public let statusCounts: StatusCounts
    public let methodCounts: [String: Int]
    public let routes: [RouteSnapshot]
    /// Requests per second for each of the last 60 seconds, oldest first
    public let requestsPerSecondHistory: [Int]
    /// Most recent requests, newest first
    public let recentRequests: [RecentRequest]
}
