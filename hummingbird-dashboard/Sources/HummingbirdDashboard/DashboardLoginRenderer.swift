//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// Renders the dashboard login page.
struct DashboardLoginRenderer: Sendable {
    let loginPath: String
    let csrfToken: String
    let errorMessage: String?
    let nextPath: String?

    func html() -> String {
        let errorBlock =
            errorMessage.map { "<p class=\"error\">\(Self.escape($0))</p>" } ?? ""
        let nextField = nextPath.map { "<input type=\"hidden\" name=\"next\" value=\"\(Self.escape($0))\">" } ?? ""
        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Dashboard Login</title>
            <style>\(Self.css)</style>
            </head>
            <body>
            <div class="card">
                <h1>Hummingbird Dashboard</h1>
                <p class="subtitle">Sign in to view observability data</p>
                \(errorBlock)
                <form method="post" action="\(Self.escape(loginPath))">
                    <input type="hidden" name="csrf" value="\(Self.escape(csrfToken))">
                    \(nextField)
                    <label>Username<input type="text" name="username" autocomplete="username" required></label>
                    <label>Password<input type="password" name="password" autocomplete="current-password" required></label>
                    <button type="submit">Sign in</button>
                </form>
            </div>
            </body>
            </html>
            """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #171009; color: #f5ede4; min-height: 100vh;
            display: flex; align-items: center; justify-content: center; padding: 24px;
        }
        .card {
            width: 100%; max-width: 400px; background: #201710; border: 1px solid #33261c;
            border-radius: 12px; padding: 28px;
        }
        h1 { font-size: 22px; margin-bottom: 6px; }
        .subtitle { color: #a08c7d; font-size: 14px; margin-bottom: 20px; }
        .error { color: #f87171; font-size: 14px; margin-bottom: 16px; }
        label { display: block; font-size: 13px; color: #d8c9bc; margin-bottom: 14px; }
        input {
            display: block; width: 100%; margin-top: 6px; padding: 10px 12px;
            border-radius: 8px; border: 1px solid #4a3728; background: #171009; color: #f5ede4;
        }
        button {
            width: 100%; margin-top: 8px; padding: 10px 12px; border: none; border-radius: 8px;
            background: #f97316; color: #1c1310; font-weight: 700; cursor: pointer;
        }
        button:hover { background: #fb923c; }
        """
}
