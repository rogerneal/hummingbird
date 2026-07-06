//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

public import Hummingbird

extension RouterPath {
    func matchAll<Context: RouterRequestContext>(_ context: Context) -> Context? {
        if self.components.count != context.routerContext.remainingPathComponents.count {
            if case .recursiveWildcard = self.components.last?.value {
                if self.components.count > context.routerContext.remainingPathComponents.count + 1 {
                    return nil
                }
            } else {
                return nil
            }
        }
        return self.match(context)
    }

    @usableFromInline
    func matchPrefix<Context: RouterRequestContext>(_ context: Context) -> Context? {
        if self.components.count > context.routerContext.remainingPathComponents.count {
            return nil
        }
        return self.match(context)
    }

    private func pathComponentMatches(_ lhs: Substring, _ rhs: Substring, caseInsensitive: Bool) -> Bool {
        if caseInsensitive {
            lhs.lowercased() == rhs.lowercased()
        } else {
            lhs == rhs
        }
    }

    private func pathComponentHasSuffix(_ component: Substring, suffix: Substring, caseInsensitive: Bool) -> Bool {
        if caseInsensitive {
            component.lowercased().hasSuffix(suffix.lowercased())
        } else {
            component.hasSuffix(suffix)
        }
    }

    private func pathComponentHasPrefix(_ component: Substring, prefix: Substring, caseInsensitive: Bool) -> Bool {
        if caseInsensitive {
            component.lowercased().hasPrefix(prefix.lowercased())
        } else {
            component.hasPrefix(prefix)
        }
    }

    private func match<Context: RouterRequestContext>(_ context: Context) -> Context? {
        var pathIterator = context.routerContext.remainingPathComponents.makeIterator()
        var context = context
        let caseInsensitive = context.routerContext.caseInsensitive
        for component in self.components {
            switch component.value {
            case .path(let lhs):
                guard let rhs = pathIterator.next() else { return nil }
                if !self.pathComponentMatches(lhs, rhs, caseInsensitive: caseInsensitive) {
                    return nil
                }
            case .capture(let key):
                context.coreContext.parameters[key] = pathIterator.next()!
            case .prefixCapture(let suffix, let key):
                let pathComponent = pathIterator.next()!
                if self.pathComponentHasSuffix(pathComponent, suffix: suffix, caseInsensitive: caseInsensitive) {
                    context.coreContext.parameters[key] = pathComponent.dropLast(suffix.count)
                } else {
                    return nil
                }
            case .suffixCapture(let prefix, let key):
                let pathComponent = pathIterator.next()!
                if self.pathComponentHasPrefix(pathComponent, prefix: prefix, caseInsensitive: caseInsensitive) {
                    context.coreContext.parameters[key] = pathComponent.dropFirst(prefix.count)
                } else {
                    return nil
                }
            case .wildcard:
                guard pathIterator.next() != nil else { return nil }
            case .prefixWildcard(let suffix):
                guard let pathComponent = pathIterator.next() else { return nil }
                if !self.pathComponentHasSuffix(pathComponent, suffix: suffix, caseInsensitive: caseInsensitive) {
                    return nil
                }
            case .suffixWildcard(let prefix):
                guard let pathComponent = pathIterator.next() else { return nil }
                if !self.pathComponentHasPrefix(pathComponent, prefix: prefix, caseInsensitive: caseInsensitive) {
                    return nil
                }
            case .recursiveWildcard:
                var paths = pathIterator.next().map { [$0] } ?? []
                while let pathComponent = pathIterator.next() {
                    paths.append(pathComponent)
                }
                context.coreContext.parameters.setCatchAll(paths.joined(separator: "/")[...])
                context.routerContext.remainingPathComponents = []
                return context
            case .null:
                return nil
            }
        }
        context.routerContext.remainingPathComponents = context.routerContext.remainingPathComponents.dropFirst(self.components.count)
        return context
    }
}
