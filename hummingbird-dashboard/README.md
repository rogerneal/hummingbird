# Hummingbird Dashboard

A lightweight, zero-configuration observability dashboard for [Hummingbird](https://github.com/hummingbird-project/hummingbird) servers.

Add one middleware and a few routes, then open `/dashboard` in your browser to see live request metrics — no Redis, no sidecar, no external services.

![Hummingbird Dashboard UI](docs/dashboard-screenshot.png)

## What it does

Hummingbird Dashboard gives you **in-process observability** for any Hummingbird app:

| Feature | Description |
|---|---|
| **Live dashboard UI** | Dark-themed web page with charts, route stats, and a recent-requests feed |
| **Request metrics** | Total requests, RPS (60s history), in-flight count, error rate |
| **Latency tracking** | p50 / p90 / p99 percentiles from the last 1,000 completed requests |
| **Per-route breakdown** | Requests, average/max duration, error rate, and last status — grouped by route template (e.g. `/api/users/{id}`) |
| **Recent requests** | Rolling feed of the latest completed requests |
| **JSON API** | Machine-readable metrics snapshot for custom tooling |
| **Prometheus export** | Standard `/metrics` endpoint for scraping with Prometheus or Grafana |
| **WebSocket push** | Optional live updates via [hummingbird-websocket](https://github.com/hummingbird-project/hummingbird-websocket), with automatic polling fallback |

Everything is stored **in memory** inside your process. Metrics reset when the server restarts. For long-term retention, scrape the Prometheus endpoint.

## How it works

```
  Browser                    Your Hummingbird app
  ───────                    ────────────────────

  GET /dashboard  ────────►  Dashboard routes serve HTML + JSON API
  WS  /dashboard/api/live ─►  (optional) WebSocket pushes metric snapshots

  GET /hello      ────────►  DashboardMiddleware records the request
  GET /api/users  ────────►  → timing, status, bytes, route template
                             → stored in DashboardMetrics (thread-safe)
```

1. **`DashboardMiddleware`** wraps your handlers. For each request it records start time, in-flight count, method, path, response status, duration, and bytes transferred. It uses the route **template** (from `context.endpointPath`) so `/api/users/1` and `/api/users/2` group together as `/api/users/{id}`.

2. **`DashboardMetrics`** holds all counters and samples in a thread-safe store (`NIOLockedValueBox`). Latency uses a rolling sample window; RPS uses a 60-second ring buffer.

3. **Dashboard routes** read from the same metrics store and expose:
   - HTML page (JavaScript updates the DOM)
   - JSON snapshot at `/dashboard/api/metrics`
   - Prometheus text at `/metrics`
   - Optional WebSocket stream at `/dashboard/api/live`

4. **The dashboard page** connects to the WebSocket when available and shows **live · ws** in the header. If the WebSocket fails, it falls back to polling the JSON API every 2 seconds.

### Important: register routes before middleware

Dashboard routes should be registered **before** `DashboardMiddleware()` so the dashboard's own traffic is not counted in the metrics it displays:

```swift
router.addDashboard()                    // ← first
router.add(middleware: DashboardMiddleware())  // ← then middleware
// ... your app routes ...
```

## Products

| Product | When to use |
|---|---|
| **`HummingbirdDashboard`** | Core library: middleware, metrics store, HTML UI, JSON API, Prometheus. Depends only on Hummingbird. |
| **`HummingbirdDashboardWS`** | Adds WebSocket live push. Depends on `HummingbirdDashboard` + `HummingbirdWebSocket`. |

## Requirements

- Swift 6.1+
- Hummingbird 2.x
- **Apple:** macOS 14+ / iOS 17+ / tvOS 17+ (minimum deployment targets in `Package.swift`)
- **Linux:** supported — Swift Package Manager builds on Linux by default; no Apple-only APIs are used in the core library

## Quick start

### Try the demo

```sh
cd hummingbird-dashboard
swift run DashboardExample
```

Open [http://localhost:8080/dashboard](http://localhost:8080/dashboard). The example includes a built-in traffic simulator so metrics appear immediately.

Use a different port if 8080 is taken:

```sh
SERVER_PORT=8099 swift run DashboardExample
```

### Add to your app (polling only)

```swift
import Hummingbird
import HummingbirdDashboard

let router = Router()
router.addDashboard()
router.add(middleware: DashboardMiddleware())
// ... your routes ...

let app = Application(router: router)
try await app.runService()
```

### Add to your app (WebSocket live updates)

```swift
import Hummingbird
import HummingbirdDashboard
import HummingbirdDashboardWS
import HummingbirdWebSocket

let router = Router(context: BasicWebSocketRequestContext.self)
router.addDashboardWithLiveUpdates()
router.add(middleware: DashboardMiddleware())
// ... your routes ...

let app = Application(
    router: router,
    server: .http1WebSocketUpgrade(webSocketRouter: router)
)
try await app.runService()
```

## Endpoints

All paths are configurable via `DashboardConfiguration`.

| Route | Description |
|---|---|
| `GET /dashboard` | Dashboard HTML page |
| `GET /dashboard/api/metrics` | Full metrics snapshot as JSON |
| `GET /dashboard/api/health` | Lightweight health check |
| `GET /dashboard/api/live` | WebSocket live metrics stream (`HummingbirdDashboardWS` only) |
| `POST /dashboard/api/reset` | Reset all metrics (opt-in via `enableReset`; shows a **Reset** button in the UI) |
| `GET /metrics` | Prometheus exposition format |

## Configuration

```swift
router.addDashboard(configuration: .init(
    path: "/dashboard",              // dashboard HTML + API base path
    prometheusPath: "/metrics",      // set to nil to disable Prometheus
    enableReset: false,              // true adds POST /dashboard/api/reset
    refreshIntervalMS: 2000,         // poll / push interval for the UI
    liveSocketPath: nil              // set automatically by addDashboardWithLiveUpdates()
))
```

Pass the same `DashboardMetrics` instance to both the middleware and routes if you use a custom store instead of `.shared`:

```swift
let metrics = DashboardMetrics()
router.addDashboard(metrics: metrics)
router.add(middleware: DashboardMiddleware(metrics: metrics))
```

## Local development (this fork)

This package lives at `hummingbird-dashboard/` inside [rogerneal/hummingbird](https://github.com/rogerneal/hummingbird) and depends on the parent fork via `.package(path: "..")` in `Package.swift`.

When extracted to its own repository, replace that with:

```swift
.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.24.0")
```

## Testing

```sh
cd hummingbird-dashboard
swift test
```

The test suite covers metrics recording, route template grouping, Prometheus export, end-to-end HTTP, and WebSocket live streaming.

## Security notes

- The dashboard exposes operational data (routes, error rates, recent requests). In production, protect it with an auth middleware or bind it to an internal-only interface.
- `enableReset` registers an unauthenticated endpoint that wipes all metrics. Leave it disabled (the default) outside development.
- Metrics are in-memory only. Use the Prometheus endpoint with Grafana for persistence and alerting.

## License

Apache-2.0 — see [LICENSE.txt](LICENSE.txt), same as [Hummingbird](https://github.com/hummingbird-project/hummingbird).
