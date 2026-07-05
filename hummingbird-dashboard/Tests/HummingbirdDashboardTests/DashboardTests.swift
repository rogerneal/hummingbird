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
import HummingbirdDashboardWS
import HummingbirdTesting
import HummingbirdWebSocket
import HummingbirdWSTesting
import NIOConcurrencyHelpers
import NIOFoundationEssentialsCompat
import Testing

struct DashboardTests {
    @Test func testMetricsRecording() {
        let metrics = DashboardMetrics()
        metrics.requestStarted()
        metrics.requestFinished(method: "GET", path: "/test", status: 200, duration: 0.1, requestBytes: 0, responseBytes: 1024)
        metrics.requestStarted()
        metrics.requestFinished(method: "POST", path: "/api/users", status: 201, duration: 0.2, requestBytes: 256, responseBytes: 512)
        metrics.requestStarted()
        metrics.requestFinished(method: "GET", path: "/broken", status: 500, duration: 0.05, requestBytes: 0, responseBytes: 0)

        let snapshot = metrics.snapshot()
        #expect(snapshot.totalRequests == 3)
        #expect(snapshot.totalErrors == 1)
        #expect(abs(snapshot.errorRatePercent - 100.0 / 3.0) < 0.01)
        #expect(snapshot.inFlight == 0)
        #expect(snapshot.statusCounts.success == 2)
        #expect(snapshot.statusCounts.serverError == 1)
        #expect(snapshot.methodCounts["GET"] == 2)
        #expect(snapshot.methodCounts["POST"] == 1)
        #expect(snapshot.dataOutBytes == 1536)
        #expect(snapshot.dataInBytes == 256)
        #expect(snapshot.latencySampleCount == 3)
        #expect(snapshot.recentRequests.count == 3)
        #expect(snapshot.recentRequests.first?.path == "/broken")
    }

    @Test func testRouteStats() {
        let metrics = DashboardMetrics()
        for _ in 0..<3 { metrics.requestStarted() }
        metrics.requestFinished(method: "GET", path: "/api/test", status: 200, duration: 0.1, requestBytes: 0, responseBytes: 100)
        metrics.requestFinished(method: "GET", path: "/api/test", status: 200, duration: 0.3, requestBytes: 0, responseBytes: 100)
        metrics.requestFinished(method: "GET", path: "/api/test", status: 404, duration: 0.1, requestBytes: 0, responseBytes: 0)

        let snapshot = metrics.snapshot()
        let route = snapshot.routes.first { $0.path == "/api/test" }
        #expect(route?.requests == 3)
        #expect(route?.errors == 1)
        #expect(route.map { abs($0.averageDuration - 0.5 / 3) < 0.001 } == true)
        #expect(route?.maxDuration == 0.3)
        #expect(route?.lastStatus == 404)
    }

    @Test func testLatencyPercentiles() {
        let metrics = DashboardMetrics()
        for i in 1...100 {
            metrics.requestStarted()
            metrics.requestFinished(
                method: "GET", path: "/p", status: 200,
                duration: Double(i) / 1000, requestBytes: 0, responseBytes: 0
            )
        }
        let snapshot = metrics.snapshot()
        #expect(abs(snapshot.p50Latency - 0.050) < 0.002)
        #expect(abs(snapshot.p99Latency - 0.099) < 0.002)
    }

    @Test func testReset() {
        let metrics = DashboardMetrics()
        metrics.requestStarted()
        metrics.requestFinished(method: "GET", path: "/x", status: 200, duration: 0.1, requestBytes: 0, responseBytes: 10)
        metrics.reset()
        let snapshot = metrics.snapshot()
        #expect(snapshot.totalRequests == 0)
        #expect(snapshot.routes.isEmpty)
        #expect(snapshot.recentRequests.isEmpty)
    }

    @Test func testPrometheusExport() {
        let metrics = DashboardMetrics()
        metrics.requestStarted()
        metrics.requestFinished(method: "GET", path: "/prom", status: 200, duration: 0.05, requestBytes: 0, responseBytes: 1024)

        let output = PrometheusExporter().render(metrics.snapshot())
        #expect(output.contains("http_requests_total 1"))
        #expect(output.contains("http_requests_by_method_total{method=\"GET\"} 1"))
        #expect(output.contains("http_route_requests_total{route=\"/prom\"} 1"))
        #expect(output.contains("http_response_size_bytes_total 1024"))
        #expect(output.contains("# TYPE http_request_duration_seconds summary"))
    }

    @Test func testDashboardEndToEnd() async throws {
        let metrics = DashboardMetrics()
        let router = Router()
        router.addDashboard(configuration: .init(enableReset: true), metrics: metrics)
        router.add(middleware: DashboardMiddleware(metrics: metrics))
        router.get("/hello") { _, _ in "Hello" }
        router.get("/fail") { _, _ -> String in throw HTTPError(.badRequest) }

        let app = Application(router: router)
        try await app.test(.router) { client in
            try await client.execute(uri: "/hello", method: .get) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(uri: "/fail", method: .get) { response in
                #expect(response.status == .badRequest)
            }
            try await client.execute(uri: "/dashboard", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("Hummingbird Dashboard"))
            }
            try await client.execute(uri: "/dashboard/api/metrics", method: .get) { response in
                let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: Data(buffer: response.body))
                #expect(snapshot.totalRequests == 2)
                #expect(snapshot.totalErrors == 1)
            }
            try await client.execute(uri: "/metrics", method: .get) { response in
                #expect(String(buffer: response.body).contains("http_requests_total"))
            }
            try await client.execute(uri: "/dashboard/api/reset", method: .post) { _ in }
            try await client.execute(uri: "/dashboard/api/metrics", method: .get) { response in
                let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: Data(buffer: response.body))
                #expect(snapshot.totalRequests == 0)
            }
        }
    }

    @Test func testRouteTemplateGrouping() async throws {
        let metrics = DashboardMetrics()
        let router = Router()
        router.add(middleware: DashboardMiddleware(metrics: metrics))
        router.get("/users/{id}") { _, context in
            "user \(context.parameters.get("id") ?? "?")"
        }

        let app = Application(router: router)
        try await app.test(.router) { client in
            try await client.execute(uri: "/users/1", method: .get) { _ in }
            try await client.execute(uri: "/users/2", method: .get) { _ in }
            try await client.execute(uri: "/users/3", method: .get) { _ in }
        }

        let snapshot = metrics.snapshot()
        let route = try #require(snapshot.routes.first { $0.path.contains("users") })
        #expect(route.requests == 3)
        #expect(snapshot.routes.count == 1)
    }

    @Test func testDashboardHTMLIncludesWebSocketPath() async throws {
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.addDashboardWithLiveUpdates()
        let app = Application(router: router)
        try await app.test(.router) { client in
            try await client.execute(uri: "/dashboard", method: .get) { response in
                let html = String(buffer: response.body)
                #expect(html.contains("/dashboard/api/live"))
                #expect(html.contains("connectWebSocket"))
            }
        }
    }

    @Test func testWebSocketLiveStream() async throws {
        let metrics = DashboardMetrics()
        metrics.requestStarted()
        metrics.requestFinished(method: "GET", path: "/seed", status: 200, duration: 0.01, requestBytes: 0, responseBytes: 4)

        let router = Router(context: BasicWebSocketRequestContext.self)
        router.addDashboardWebSocket(metrics: metrics, refreshIntervalMS: 50)

        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router)
        )

        let receivedJSON = NIOLockedValueBox<String?>(nil)
        try await app.test(.live) { client in
            _ = try await client.ws("/dashboard/api/live") { inbound, _, _ in
                for try await message in inbound.messages(maxSize: 1024 * 1024) {
                    if case .text(let text) = message {
                        receivedJSON.withLockedValue { $0 = text }
                        return
                    }
                }
            }
        }

        let json = try #require(receivedJSON.withLockedValue { $0 })
        let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.totalRequests >= 1)
        #expect(snapshot.routes.contains { $0.path == "/seed" })
    }
}
