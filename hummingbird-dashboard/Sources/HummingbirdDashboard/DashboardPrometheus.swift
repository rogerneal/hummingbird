//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// Renders a ``DashboardSnapshot`` in the Prometheus text exposition format.
public struct PrometheusExporter: Sendable {
    public init() {}

    /// Generate Prometheus-formatted metrics from a snapshot.
    public func render(_ snapshot: DashboardSnapshot) -> String {
        var out = ""
        out.reserveCapacity(4096)

        func metric(_ name: String, _ help: String, _ type: String, _ samples: [(labels: String, value: String)]) {
            out += "# HELP \(name) \(help)\n"
            out += "# TYPE \(name) \(type)\n"
            for sample in samples {
                out += "\(name)\(sample.labels) \(sample.value)\n"
            }
        }

        metric(
            "http_requests_total",
            "Total number of HTTP requests.",
            "counter",
            [("", String(snapshot.totalRequests))]
        )
        metric(
            "http_request_errors_total",
            "Total number of HTTP responses with status >= 400.",
            "counter",
            [("", String(snapshot.totalErrors))]
        )
        metric(
            "http_requests_in_flight",
            "Number of requests currently being processed.",
            "gauge",
            [("", String(snapshot.inFlight))]
        )
        metric(
            "http_requests_per_second",
            "Requests per second averaged over the last 60 seconds.",
            "gauge",
            [("", String(format: "%.3f", snapshot.requestsPerSecond))]
        )
        metric(
            "http_request_duration_seconds",
            "Request duration percentiles.",
            "summary",
            [
                ("{quantile=\"0.5\"}", String(format: "%.6f", snapshot.p50Latency)),
                ("{quantile=\"0.9\"}", String(format: "%.6f", snapshot.p90Latency)),
                ("{quantile=\"0.99\"}", String(format: "%.6f", snapshot.p99Latency)),
            ]
        )
        let latencySum = snapshot.averageLatency * Double(snapshot.latencySampleCount)
        out += "http_request_duration_seconds_sum \(String(format: "%.6f", latencySum))\n"
        out += "http_request_duration_seconds_count \(snapshot.latencySampleCount)\n"
        metric(
            "http_response_size_bytes_total",
            "Total bytes sent in response bodies.",
            "counter",
            [("", String(snapshot.dataOutBytes))]
        )
        metric(
            "http_request_size_bytes_total",
            "Total bytes received in request bodies.",
            "counter",
            [("", String(snapshot.dataInBytes))]
        )
        metric(
            "http_requests_by_status_total",
            "Total requests by HTTP status code class.",
            "counter",
            [
                ("{code=\"1xx\"}", String(snapshot.statusCounts.informational)),
                ("{code=\"2xx\"}", String(snapshot.statusCounts.success)),
                ("{code=\"3xx\"}", String(snapshot.statusCounts.redirect)),
                ("{code=\"4xx\"}", String(snapshot.statusCounts.clientError)),
                ("{code=\"5xx\"}", String(snapshot.statusCounts.serverError)),
            ]
        )
        metric(
            "http_requests_by_method_total",
            "Total requests by HTTP method.",
            "counter",
            snapshot.methodCounts
                .sorted { $0.key < $1.key }
                .map { ("{method=\"\(Self.escapeLabel($0.key))\"}", String($0.value)) }
        )
        metric(
            "http_route_requests_total",
            "Total requests per route.",
            "counter",
            snapshot.routes.map { ("{route=\"\(Self.escapeLabel($0.path))\"}", String($0.requests)) }
        )
        metric(
            "http_route_errors_total",
            "Total errored requests per route.",
            "counter",
            snapshot.routes.map { ("{route=\"\(Self.escapeLabel($0.path))\"}", String($0.errors)) }
        )
        metric(
            "http_route_duration_seconds_avg",
            "Average request duration per route.",
            "gauge",
            snapshot.routes.map {
                ("{route=\"\(Self.escapeLabel($0.path))\"}", String(format: "%.6f", $0.averageDuration))
            }
        )
        metric(
            "process_uptime_seconds",
            "Time since the server started.",
            "gauge",
            [("", String(format: "%.1f", snapshot.uptimeSeconds))]
        )
        return out
    }

    static func escapeLabel(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
