//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import NIOCore
import NIOHTTP2

/// Closes HTTP2 connections on events `NIOHTTP2ServerConnectionManagementHandler` does not act on.
///
/// Hummingbird servers enable `allowRemoteHalfClosure`, so a connection whose input has closed
/// can accept no new streams but would otherwise stay open indefinitely. Unhandled errors that
/// reach the end of the channel pipeline also close the connection.
@available(hummingbird 2.0, *)
final class HTTP2ConnectionEventsHandler: ChannelInboundHandler {
    typealias InboundIn = HTTP2Frame
    typealias InboundOut = HTTP2Frame

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let channelEvent = event as? ChannelEvent, channelEvent == .inputClosed {
            context.close(mode: .all, promise: nil)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        context.close(mode: .all, promise: nil)
    }
}
