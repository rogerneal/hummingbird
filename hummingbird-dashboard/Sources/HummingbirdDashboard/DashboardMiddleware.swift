//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Dispatch
import Hummingbird
import HummingbirdCore

/// Middleware recording request metrics for the Hummingbird dashboard.
///
/// Add this middleware before your routes so that every request is recorded.
/// Middleware only applies to routes registered after it, so register the
/// dashboard routes first if you don't want dashboard traffic in your metrics:
/// ```swift
/// let router = Router()
/// router.addDashboard()
/// router.add(middleware: DashboardMiddleware())
/// // your routes...
/// ```
public struct DashboardMiddleware<Context: RequestContext>: RouterMiddleware {
    let metrics: DashboardMetrics

    /// Initialize DashboardMiddleware
    /// - Parameter metrics: metrics store to record requests into
    public init(metrics: DashboardMetrics = .shared) {
        self.metrics = metrics
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let startTime = DispatchTime.now().uptimeNanoseconds
        let requestBytes = request.headers[.contentLength].flatMap(Int.init) ?? 0
        self.metrics.requestStarted()
        do {
            var response = try await next(request, context)
            let responseStatus = response.status.code
            let responseBytes = response.body.contentLength ?? 0
            let metrics = self.metrics
            let method = request.method.rawValue
            let requestPath = request.uri.path
            // record once the response has been written, at which point the
            // endpoint path (route template) is guaranteed to be set
            response.body = response.body.withPostWriteAction {
                let duration = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
                metrics.requestFinished(
                    method: method,
                    path: context.endpointPath ?? requestPath,
                    status: Int(responseStatus),
                    duration: duration,
                    requestBytes: requestBytes,
                    responseBytes: responseBytes
                )
            }
            return response
        } catch {
            let status: Int
            if let httpError = error as? any HTTPResponseError {
                status = Int(httpError.status.code)
            } else {
                status = 500
            }
            let duration = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
            self.metrics.requestFinished(
                method: request.method.rawValue,
                path: context.endpointPath ?? request.uri.path,
                status: status,
                duration: duration,
                requestBytes: requestBytes,
                responseBytes: 0
            )
            throw error
        }
    }
}

extension ResponseBody {
    /// Return a response body that runs a closure after the original body has been
    /// fully written to the channel.
    ///
    /// Public-API equivalent of HummingbirdCore's package-scoped `withPostWriteClosure`,
    /// so this package can live outside the hummingbird repository.
    func withPostWriteAction(_ postWrite: @escaping @Sendable () async -> Void) -> Self {
        let body = self
        return .init(contentLength: self.contentLength) { writer in
            do {
                try await body.write(writer)
                await postWrite()
            } catch {
                await postWrite()
                throw error
            }
        }
    }
}
