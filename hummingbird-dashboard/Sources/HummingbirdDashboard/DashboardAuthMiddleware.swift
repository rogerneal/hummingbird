//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import HTTPTypes
import Hummingbird

struct DashboardAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    let authState: DashboardAuthState
    let allowBearerScrape: Bool

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        if try await self.isAuthorized(request) {
            return try await next(request, context)
        }
        return self.unauthorizedResponse(for: request)
    }

    func isAuthorized(_ request: Request) async throws -> Bool {
        if self.allowBearerScrape, let scrapeToken = authState.configuration.scrapeToken {
            if let header = request.headers[.authorization], header == "Bearer \(scrapeToken)" {
                return true
            }
        }
        let cookieName = authState.configuration.sessionCookieName
        guard let sessionID = request.cookies[cookieName]?.value else { return false }
        return await authState.sessionStore.isValidSession(sessionID)
    }

    private func unauthorizedResponse(for request: Request) -> Response {
        let path = request.uri.path
        let loginPath = authState.configuration.loginPath
        if self.prefersHTMLResponse(request, path: path) {
            var location = loginPath
            if !path.isEmpty, path != loginPath {
                let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
                location += "?next=\(encoded)"
            }
            return Response(status: .found, headers: [.location: location])
        }
        return Response(
            status: .unauthorized,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: #"{"error":"unauthorized"}"#))
        )
    }

    private func prefersHTMLResponse(_ request: Request, path: String) -> Bool {
        if path == authState.configuration.loginPath { return true }
        if path.hasSuffix("/api/metrics") || path.hasSuffix("/api/health") || path.hasSuffix("/api/reset") {
            return false
        }
        if path == "/metrics" || path.hasSuffix("/metrics") { return false }
        if let accept = request.headers[.accept], accept.contains("text/html") { return true }
        return !path.contains("/api/")
    }
}

enum DashboardAuthCookies {
    static func sessionCookie(value: String, configuration: DashboardAuthConfiguration) throws -> Cookie {
        let maxAge = Int(configuration.sessionTTL.components.seconds)
        return try Cookie.validated(
            name: configuration.sessionCookieName,
            value: value,
            maxAge: maxAge,
            path: "/",
            secure: configuration.secureCookies,
            httpOnly: true,
            sameSite: .strict
        )
    }

    static func clearSessionCookie(configuration: DashboardAuthConfiguration) throws -> Cookie {
        try Cookie.validated(
            name: configuration.sessionCookieName,
            value: "",
            maxAge: 0,
            path: "/",
            secure: configuration.secureCookies,
            httpOnly: true,
            sameSite: .strict
        )
    }
}

enum DashboardFormParser {
    static func parse(_ body: String) -> [String: String] {
        var values: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? Self.decode(parts[1]) : ""
            values[key] = value
        }
        return values
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? value
    }
}
