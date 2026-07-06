//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import HTTPTypes
import Hummingbird
import HummingbirdDashboard
import HummingbirdDashboardWS
import HummingbirdWebSocket
import Logging
import NIOCore
import NIOEmbedded

/// Discards response bodies so post-write metrics hooks run during the traffic simulator.
struct DiscardingResponseWriter: ResponseBodyWriter {
    mutating func write(_ buffer: ByteBuffer) async throws {}
    consuming func finish(_ trailingHeaders: HTTPFields?) async throws {}
}

let env = Environment()
let hostname = env.get("SERVER_HOSTNAME") ?? "127.0.0.1"
let port = env.get("SERVER_PORT", as: Int.self) ?? 8080

let router = Router(context: BasicWebSocketRequestContext.self)
router.addDashboardWithLiveUpdates(configuration: .init(enableReset: true))
router.add(middleware: DashboardMiddleware())

router.get("/") { _, _ in
    Response(
        status: .ok,
        headers: [.contentType: "text/html; charset=utf-8"],
        body: .init(
            byteBuffer: .init(
                string: """
                    <html><body style="font-family: system-ui; max-width: 640px; margin: 60px auto;">
                    <h1>Hummingbird Dashboard Example</h1>
                    <p>Simulated traffic is running in the background. The dashboard uses WebSocket push with polling fallback.</p>
                    <ul>
                        <li><a href="/dashboard">Dashboard UI</a></li>
                        <li><a href="/dashboard/api/metrics">Metrics JSON</a></li>
                        <li><a href="/dashboard/api/health">Health check</a></li>
                        <li><a href="/metrics">Prometheus metrics</a></li>
                    </ul>
                    </body></html>
                    """
            )
        )
    )
}
router.get("/hello") { _, _ in "Hello, world!" }
router.get("/api/users") { _, _ in
    try await Task.sleep(for: .milliseconds(Int.random(in: 5...40)))
    return #"[{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]"#
}
router.get("/api/users/{id}") { _, context in
    try await Task.sleep(for: .milliseconds(Int.random(in: 10...80)))
    let id = try context.parameters.require("id", as: Int.self)
    guard id <= 10 else { throw HTTPError(.notFound, message: "User not found") }
    return #"{"id":\#(id),"name":"User \#(id)"}"#
}
router.post("/api/users") { _, _ in
    try await Task.sleep(for: .milliseconds(Int.random(in: 30...120)))
    return Response(
        status: .created,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: .init(string: #"{"id":42,"name":"New User"}"#))
    )
}
router.get("/api/products") { _, _ in
    try await Task.sleep(for: .milliseconds(Int.random(in: 5...30)))
    return #"[{"sku":"HB-1","price":9.99}]"#
}
router.get("/slow") { _, _ in
    try await Task.sleep(for: .milliseconds(Int.random(in: 300...900)))
    return "That took a while"
}
router.get("/flaky") { _, _ in
    if Int.random(in: 0..<4) == 0 {
        throw HTTPError(.internalServerError, message: "Simulated failure")
    }
    return "Got lucky"
}

var logger = Logger(label: "dashboard-example")
logger.logLevel = .info

let app = Application(
    router: router,
    server: .http1WebSocketUpgrade(webSocketRouter: router),
    configuration: .init(address: .hostname(hostname, port: port), serverName: "Hummingbird"),
    logger: logger
)

logger.info("Dashboard:  http://\(hostname):\(port)/dashboard")
logger.info("WebSocket:  ws://\(hostname):\(port)/dashboard/api/live")
logger.info("Prometheus: http://\(hostname):\(port)/metrics")

let simulator = Task {
    let responder = router.buildResponder()
    let simulatorLogger = Logger(label: "traffic-simulator")

    @Sendable func fire(_ method: HTTPRequest.Method, _ path: String) async {
        let request = Request(
            head: .init(method: method, scheme: "http", authority: "localhost", path: path),
            body: .init(buffer: ByteBuffer())
        )
        let context = BasicWebSocketRequestContext(
            source: ApplicationRequestContextSource(channel: EmbeddedChannel(), logger: simulatorLogger)
        )
        do {
            let response = try await responder.respond(to: request, context: context)
            try await response.body.write(DiscardingResponseWriter())
        } catch {
            // errors are recorded by the middleware
        }
    }

    let weightedPaths: [(HTTPRequest.Method, String, Int)] = [
        (.get, "/hello", 30),
        (.get, "/api/users", 20),
        (.get, "/api/users/1", 15),
        (.get, "/api/products", 15),
        (.post, "/api/users", 8),
        (.get, "/flaky", 7),
        (.get, "/slow", 3),
        (.get, "/missing/page", 2),
    ]
    let totalWeight = weightedPaths.reduce(0) { $0 + $1.2 }

    while !Task.isCancelled {
        var pick = Int.random(in: 0..<totalWeight)
        for (method, path, weight) in weightedPaths {
            pick -= weight
            if pick < 0 {
                let resolvedPath =
                    path.hasPrefix("/api/users/") && path != "/api/users/1"
                    ? "/api/users/\(Int.random(in: 1...12))" : path
                await fire(method, resolvedPath)
                break
            }
        }
        try? await Task.sleep(for: .milliseconds(Int.random(in: 40...250)))
    }
}
defer { simulator.cancel() }

try await app.runService()
