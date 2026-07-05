//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

/// Renders the dashboard HTML page.
///
/// The page is a static shell; its JavaScript polls the dashboard JSON API and
/// updates the DOM in place, so no full-page refreshes are needed.
struct DashboardRenderer: Sendable {
    /// Path to the JSON metrics endpoint the page polls
    let metricsAPIPath: String
    /// Poll interval in milliseconds
    let refreshIntervalMS: Int
    /// Optional WebSocket path for push updates; polling is the fallback
    let liveSocketPath: String?

    init(metricsAPIPath: String, refreshIntervalMS: Int = 2000, liveSocketPath: String? = nil) {
        self.metricsAPIPath = metricsAPIPath
        self.refreshIntervalMS = refreshIntervalMS
        self.liveSocketPath = liveSocketPath
    }

    func html() -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Hummingbird Dashboard</title>
        <style>\(Self.css)</style>
        </head>
        <body>
        <div class="container">
            <header class="header">
                <div class="header-left">
                    \(Self.logoSVG)
                    <div>
                        <h1>Hummingbird Dashboard</h1>
                        <div class="subtitle">Swift server framework &middot; observability</div>
                    </div>
                </div>
                <div class="header-right">
                    <span class="live"><span class="dot" id="live-dot"></span><span id="live-label">live</span></span>
                    <span>uptime <strong id="uptime">&ndash;</strong></span>
                    <span>in-flight <strong id="inflight-header">0</strong></span>
                </div>
            </header>

            <section class="cards">
                <div class="card"><div class="card-label">Total requests</div><div class="card-value" id="total-requests">0</div><div class="card-sub" id="total-requests-sub">&nbsp;</div></div>
                <div class="card"><div class="card-label">Requests / sec</div><div class="card-value" id="rps">0</div><div class="card-sub">60s avg</div></div>
                <div class="card"><div class="card-label">In-flight</div><div class="card-value" id="inflight">0</div><div class="card-sub" id="inflight-sub">peak 0</div></div>
                <div class="card"><div class="card-label">Error rate</div><div class="card-value" id="error-rate">0%</div><div class="card-sub" id="error-count">0 errors</div></div>
                <div class="card"><div class="card-label">p50 latency</div><div class="card-value" id="p50">&ndash;</div><div class="card-sub">median</div></div>
                <div class="card"><div class="card-label">p99 latency</div><div class="card-value" id="p99">&ndash;</div><div class="card-sub" id="latency-samples">0 samples</div></div>
                <div class="card"><div class="card-label">Data out</div><div class="card-value" id="data-out">0 B</div><div class="card-sub" id="data-in">in 0 B</div></div>
            </section>

            <section class="grid-2">
                <div class="panel">
                    <div class="panel-header"><h2>Requests / second</h2><span class="muted">last 60s</span></div>
                    <svg id="rps-chart" viewBox="0 0 600 160" preserveAspectRatio="none"></svg>
                    <div class="panel-footer"><span class="muted" id="chart-peak">peak 0/s</span><span class="muted" id="chart-now">now 0/s</span></div>
                </div>
                <div class="panel">
                    <div class="panel-header"><h2>Responses by status</h2></div>
                    <div class="bars" id="status-bars"></div>
                </div>
            </section>

            <section class="grid-2">
                <div class="panel">
                    <div class="panel-header"><h2>Latency percentiles</h2><span class="muted" id="latency-window">last 0 reqs</span></div>
                    <div class="kv-rows" id="latency-rows"></div>
                </div>
                <div class="panel">
                    <div class="panel-header"><h2>Requests by method</h2></div>
                    <div class="bars" id="method-bars"></div>
                </div>
            </section>

            <section class="panel">
                <div class="panel-header"><h2>Routes</h2></div>
                <div class="table-wrap">
                    <table>
                        <thead><tr><th>Path</th><th class="num">Requests</th><th class="num">Avg</th><th class="num">Max</th><th class="num">Errors</th><th class="num">Last</th></tr></thead>
                        <tbody id="routes-body"><tr><td colspan="6" class="empty">No requests yet</td></tr></tbody>
                    </table>
                </div>
            </section>

            <section class="panel">
                <div class="panel-header"><h2>Recent requests</h2></div>
                <div class="table-wrap">
                    <table>
                        <thead><tr><th>When</th><th>Method</th><th>Path</th><th class="num">Status</th><th class="num">Duration</th><th class="num">Size</th></tr></thead>
                        <tbody id="recent-body"><tr><td colspan="6" class="empty">No requests yet</td></tr></tbody>
                    </table>
                </div>
            </section>
        </div>
        <script>
        const API_PATH = "\(self.metricsAPIPath)";
        const REFRESH_MS = \(self.refreshIntervalMS);
        const LIVE_WS_PATH = \(self.liveSocketPath.map { "\"\($0)\"" } ?? "null");
        \(Self.javascript)
        </script>
        </body>
        </html>
        """
    }

    static let logoSVG = """
        <svg class="logo" viewBox="0 0 48 48" fill="none" aria-hidden="true">
            <path d="M43 8c-8 0-15 3-20 9l-5 7-9-2c-1 0-2 1-1 2l7 5-3 6c0 1 1 2 2 1l6-3 5 7c1 1 2 0 2-1l-2-9 7-5c6-4 10-10 11-17z" fill="#f97316"/>
            <path d="M23 17c-3-4-8-6-14-6 2 5 6 8 11 9z" fill="#fdba74"/>
            <circle cx="36" cy="14" r="1.6" fill="#1c1310"/>
        </svg>
        """

    static let css = """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #171009; color: #f5ede4; line-height: 1.45;
            -webkit-font-smoothing: antialiased;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 24px 20px 60px; }

        .header { display: flex; justify-content: space-between; align-items: center; gap: 16px;
                  padding-bottom: 20px; margin-bottom: 24px; border-bottom: 1px solid #33261c; flex-wrap: wrap; }
        .header-left { display: flex; align-items: center; gap: 14px; }
        .logo { width: 44px; height: 44px; flex-shrink: 0; }
        .header h1 { font-size: 20px; font-weight: 700; }
        .subtitle { color: #a08c7d; font-size: 13px; }
        .header-right { display: flex; align-items: center; gap: 18px; font-size: 13px; color: #a08c7d; }
        .header-right strong { color: #f5ede4; font-weight: 600; }
        .live { display: flex; align-items: center; gap: 6px; }
        .dot { width: 8px; height: 8px; border-radius: 50%; background: #57534e; }
        .dot.on { background: #f97316; box-shadow: 0 0 6px #f97316; animation: pulse 1.6s infinite; }
        .dot.stale { background: #ef4444; }
        @keyframes pulse { 50% { opacity: 0.5; } }

        .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 12px; margin-bottom: 20px; }
        .card { background: #201710; border: 1px solid #33261c; border-radius: 10px; padding: 14px 16px; }
        .card-label { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #a08c7d; margin-bottom: 6px; }
        .card-value { font-size: 26px; font-weight: 700; font-variant-numeric: tabular-nums; }
        .card-value.bad { color: #f87171; }
        .card-value.good { color: #4ade80; }
        .card-sub { font-size: 12px; color: #7d6a5c; margin-top: 2px; }

        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 20px; }
        @media (max-width: 860px) { .grid-2 { grid-template-columns: 1fr; } }

        .panel { background: #201710; border: 1px solid #33261c; border-radius: 10px; padding: 16px; margin-bottom: 20px; }
        .grid-2 .panel { margin-bottom: 0; }
        .panel-header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 14px; }
        .panel-header h2 { font-size: 14px; font-weight: 600; }
        .panel-footer { display: flex; justify-content: space-between; margin-top: 6px; }
        .muted { color: #7d6a5c; font-size: 12px; }

        #rps-chart { width: 100%; height: 160px; display: block; }

        .bars { display: flex; flex-direction: column; gap: 12px; }
        .bar-row { display: flex; align-items: center; gap: 10px; font-size: 12px; }
        .bar-label { width: 42px; color: #a08c7d; font-weight: 600; }
        .bar-track { flex: 1; height: 8px; background: #33261c; border-radius: 4px; overflow: hidden; }
        .bar-fill { height: 100%; border-radius: 4px; transition: width 0.4s ease; }
        .bar-count { width: 64px; text-align: right; font-variant-numeric: tabular-nums; color: #d8c9bc; }

        .kv-rows { display: flex; flex-direction: column; }
        .kv-row { display: flex; justify-content: space-between; padding: 10px 2px; border-bottom: 1px solid #2a1f16; font-size: 14px; }
        .kv-row:last-child { border-bottom: none; }
        .kv-key { color: #a08c7d; }
        .kv-value { font-weight: 600; font-variant-numeric: tabular-nums; }

        .table-wrap { overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; font-size: 13px; }
        th { text-align: left; padding: 8px 12px; font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em;
             color: #a08c7d; border-bottom: 1px solid #33261c; }
        td { padding: 9px 12px; border-bottom: 1px solid #2a1f16; font-variant-numeric: tabular-nums; }
        tr:last-child td { border-bottom: none; }
        th.num, td.num { text-align: right; }
        td.path { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 12.5px; }
        td.empty { text-align: center; color: #7d6a5c; font-style: italic; padding: 24px; }
        .badge { display: inline-block; min-width: 38px; text-align: center; padding: 2px 7px; border-radius: 5px;
                 font-size: 11.5px; font-weight: 700; }
        .badge.s2 { background: rgba(74,222,128,0.14); color: #4ade80; }
        .badge.s3 { background: rgba(251,191,36,0.14); color: #fbbf24; }
        .badge.s4 { background: rgba(251,146,60,0.16); color: #fb923c; }
        .badge.s5 { background: rgba(248,113,113,0.16); color: #f87171; }
        .err-ok { color: #4ade80; } .err-warn { color: #fbbf24; } .err-bad { color: #f87171; }
        """

    static let javascript = """
        "use strict";
        const $ = (id) => document.getElementById(id);

        function fmtCount(n) { return n.toLocaleString("en-US"); }
        function fmtDuration(seconds) {
            const ms = seconds * 1000;
            if (ms < 1) return "<1 ms";
            if (ms < 1000) return (ms < 10 ? ms.toFixed(1) : Math.round(ms)) + " ms";
            return (ms / 1000).toFixed(2) + " s";
        }
        function fmtBytes(b) {
            if (b < 1024) return b + " B";
            if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " KB";
            if (b < 1024 * 1024 * 1024) return (b / (1024 * 1024)).toFixed(1) + " MB";
            return (b / (1024 * 1024 * 1024)).toFixed(2) + " GB";
        }
        function fmtUptime(seconds) {
            const s = Math.floor(seconds);
            const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600),
                  m = Math.floor((s % 3600) / 60), sec = s % 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m + "m";
            if (m > 0) return m + "m " + sec + "s";
            return sec + "s";
        }
        function fmtAge(seconds) {
            if (seconds < 1) return "now";
            if (seconds < 60) return Math.floor(seconds) + "s ago";
            if (seconds < 3600) return Math.floor(seconds / 60) + "m ago";
            return Math.floor(seconds / 3600) + "h ago";
        }
        function statusClass(code) {
            if (code < 300) return "s2";
            if (code < 400) return "s3";
            if (code < 500) return "s4";
            return "s5";
        }
        function esc(s) {
            return String(s).replace(/[&<>"]/g, (c) => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]));
        }

        function renderChart(history, peak) {
            const svg = $("rps-chart");
            const w = 600, h = 160, pad = 4;
            const maxValue = Math.max(peak, Math.max(...history), 1);
            const stepX = (w - pad * 2) / (history.length - 1);
            const y = (v) => h - pad - (v / maxValue) * (h - pad * 2);
            let line = "";
            history.forEach((v, i) => {
                line += (i === 0 ? "M" : "L") + (pad + i * stepX).toFixed(1) + "," + y(v).toFixed(1);
            });
            const area = line + "L" + (w - pad) + "," + (h - pad) + "L" + pad + "," + (h - pad) + "Z";
            svg.innerHTML =
                '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">' +
                '<stop offset="0%" stop-color="#f97316" stop-opacity="0.35"/>' +
                '<stop offset="100%" stop-color="#f97316" stop-opacity="0.02"/></linearGradient></defs>' +
                '<path d="' + area + '" fill="url(#g)"/>' +
                '<path d="' + line + '" fill="none" stroke="#f97316" stroke-width="2" ' +
                'stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>';
        }

        function renderBars(el, rows) {
            const total = Math.max(rows.reduce((a, r) => a + r.count, 0), 1);
            el.innerHTML = rows.map((r) =>
                '<div class="bar-row"><div class="bar-label">' + esc(r.label) + '</div>' +
                '<div class="bar-track"><div class="bar-fill" style="width:' +
                (r.count / total * 100).toFixed(1) + '%;background:' + r.color + '"></div></div>' +
                '<div class="bar-count">' + fmtCount(r.count) + '</div></div>'
            ).join("");
        }

        function update(s) {
            $("uptime").textContent = fmtUptime(s.uptimeSeconds);
            $("inflight-header").textContent = s.inFlight;

            $("total-requests").textContent = fmtCount(s.totalRequests);
            $("total-requests-sub").innerHTML = s.totalRequests > 0 ? fmtCount(s.totalErrors) + " failed" : "&nbsp;";
            $("rps").textContent = s.requestsPerSecond >= 100 ? Math.round(s.requestsPerSecond) : s.requestsPerSecond.toFixed(1);
            $("inflight").textContent = s.inFlight;
            $("inflight-sub").textContent = "peak " + s.peakInFlight;
            const errEl = $("error-rate");
            errEl.textContent = s.errorRatePercent.toFixed(1) + "%";
            errEl.className = "card-value " + (s.errorRatePercent >= 5 ? "bad" : (s.errorRatePercent > 0 ? "" : "good"));
            $("error-count").textContent = fmtCount(s.totalErrors) + " errors";
            $("p50").textContent = fmtDuration(s.p50Latency);
            $("p99").textContent = fmtDuration(s.p99Latency);
            $("latency-samples").textContent = fmtCount(s.latencySampleCount) + " samples";
            $("data-out").textContent = fmtBytes(s.dataOutBytes);
            $("data-in").textContent = "in " + fmtBytes(s.dataInBytes);

            renderChart(s.requestsPerSecondHistory, s.peakRPS);
            $("chart-peak").textContent = "peak " + s.peakRPS + "/s";
            $("chart-now").textContent = "now " + s.currentRPS + "/s";

            renderBars($("status-bars"), [
                { label: "1xx", count: s.statusCounts.informational, color: "#93c5fd" },
                { label: "2xx", count: s.statusCounts.success, color: "#4ade80" },
                { label: "3xx", count: s.statusCounts.redirect, color: "#fbbf24" },
                { label: "4xx", count: s.statusCounts.clientError, color: "#fb923c" },
                { label: "5xx", count: s.statusCounts.serverError, color: "#f87171" },
            ]);

            const methodColors = { GET: "#f97316", POST: "#fbbf24", PUT: "#93c5fd", PATCH: "#c4b5fd", DELETE: "#f87171" };
            const methods = Object.entries(s.methodCounts)
                .sort((a, b) => b[1] - a[1])
                .map(([m, c]) => ({ label: m, count: c, color: methodColors[m] || "#a8a29e" }));
            renderBars($("method-bars"), methods.length ? methods : [{ label: "\\u2013", count: 0, color: "#57534e" }]);

            $("latency-window").textContent = "last " + fmtCount(s.latencySampleCount) + " reqs";
            $("latency-rows").innerHTML = [
                ["p50", s.p50Latency], ["p90", s.p90Latency], ["p99", s.p99Latency], ["avg", s.averageLatency],
            ].map(([k, v]) =>
                '<div class="kv-row"><span class="kv-key">' + k + '</span><span class="kv-value">' + fmtDuration(v) + "</span></div>"
            ).join("");

            const routesBody = $("routes-body");
            if (s.routes.length === 0) {
                routesBody.innerHTML = '<tr><td colspan="6" class="empty">No requests yet</td></tr>';
            } else {
                routesBody.innerHTML = s.routes.slice(0, 50).map((r) => {
                    const errClass = r.errorRatePercent >= 5 ? "err-bad" : (r.errorRatePercent > 0 ? "err-warn" : "err-ok");
                    return "<tr><td class=\\"path\\">" + esc(r.path) + "</td>" +
                        '<td class="num">' + fmtCount(r.requests) + "</td>" +
                        '<td class="num">' + fmtDuration(r.averageDuration) + "</td>" +
                        '<td class="num">' + fmtDuration(r.maxDuration) + "</td>" +
                        '<td class="num ' + errClass + '">' + r.errorRatePercent.toFixed(1) + "%</td>" +
                        '<td class="num"><span class="badge ' + statusClass(r.lastStatus) + '">' + r.lastStatus + "</span></td></tr>";
                }).join("");
            }

            const recentBody = $("recent-body");
            if (s.recentRequests.length === 0) {
                recentBody.innerHTML = '<tr><td colspan="6" class="empty">No requests yet</td></tr>';
            } else {
                recentBody.innerHTML = s.recentRequests.map((r) =>
                    '<td class="muted">' + fmtAge(r.ageSeconds) + "</td>" +
                    "<td>" + esc(r.method) + "</td>" +
                    '<td class="path">' + esc(r.path) + "</td>" +
                    '<td class="num"><span class="badge ' + statusClass(r.status) + '">' + r.status + "</span></td>" +
                    '<td class="num">' + fmtDuration(r.duration) + "</td>" +
                    '<td class="num">' + fmtBytes(r.responseBytes) + "</td>"
                ).map((row) => "<tr>" + row + "</tr>").join("");
            }
        }

        function setStatus(connected, transport) {
            $("live-dot").className = connected ? "dot on" : "dot stale";
            $("live-label").textContent = connected ? "live" + (transport ? " \\u00b7 " + transport : "") : "disconnected";
        }

        async function poll() {
            try {
                const response = await fetch(API_PATH, { cache: "no-store" });
                if (!response.ok) throw new Error("HTTP " + response.status);
                update(await response.json());
                setStatus(true, null);
            } catch (e) {
                setStatus(false, null);
            }
        }

        let pollTimer = null;
        function startPolling() {
            if (pollTimer !== null) return;
            poll();
            pollTimer = setInterval(poll, REFRESH_MS);
        }
        function stopPolling() {
            if (pollTimer !== null) { clearInterval(pollTimer); pollTimer = null; }
        }

        // Prefer WebSocket push when available; fall back to polling on failure
        // and keep retrying the socket in the background.
        function connectWebSocket() {
            const scheme = location.protocol === "https:" ? "wss://" : "ws://";
            let socket;
            try {
                socket = new WebSocket(scheme + location.host + LIVE_WS_PATH);
            } catch (e) {
                startPolling();
                return;
            }
            socket.onopen = () => stopPolling();
            socket.onmessage = (event) => {
                try {
                    update(JSON.parse(event.data));
                    setStatus(true, "ws");
                } catch (e) { /* ignore malformed frame */ }
            };
            socket.onclose = () => {
                startPolling();
                setTimeout(connectWebSocket, 5000);
            };
        }

        startPolling();
        if (LIVE_WS_PATH) connectWebSocket();
        """
}
