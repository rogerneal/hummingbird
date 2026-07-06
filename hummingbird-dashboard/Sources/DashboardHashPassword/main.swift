//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import HummingbirdDashboard

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: DashboardHashPassword <password>\n", stderr)
    exit(1)
}

do {
    print(try DashboardAuthConfiguration.hashPassword(CommandLine.arguments[1]))
} catch {
    fputs("Failed to hash password: \(error)\n", stderr)
    exit(1)
}
