//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import HummingbirdCore
import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin.C
#elseif canImport(Android)
import Android
#else
#error("Unsupported platform")
#endif

/// Access environment variables
///
/// By default, environment variable names are treated case insensitively (keys are normalized to
/// lowercase). Pass `caseSensitiveKeys: true` to preserve Unix shell semantics where
/// `MY_VAR` and `my_var` are distinct variables.
public struct Environment: Sendable, Decodable, ExpressibleByDictionaryLiteral {
    public struct Error: Swift.Error, Equatable {
        enum Code {
            case dotEnvParseError
            case variableDoesNotExist
            case variableDoesNotConvert
        }

        fileprivate let code: Code
        public let message: String?
        fileprivate init(_ code: Code, message: String? = nil) {
            self.code = code
            self.message = message
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.code == rhs.code
        }

        /// Required variable does not exist
        public static var variableDoesNotExist: Self { .init(.variableDoesNotExist) }
        /// Required variable does not convert to type
        public static var variableDoesNotConvert: Self { .init(.variableDoesNotConvert) }
        /// Error while parsing dot env file
        public static var dotEnvParseError: Self { .init(.dotEnvParseError) }
    }

    var values: [String: String]
    let caseSensitiveKeys: Bool

    /// Initialize from environment variables
    /// - Parameter caseSensitiveKeys: When `true`, preserve the case of environment variable names.
    ///   Defaults to `false` (case insensitive lookup).
    public init(caseSensitiveKeys: Bool = false) {
        self.caseSensitiveKeys = caseSensitiveKeys
        self.values = Self.getEnvironment(caseSensitiveKeys: caseSensitiveKeys)
    }

    /// Initialize from dictionary
    /// - Parameters:
    ///   - values: Environment variables to add
    ///   - caseSensitiveKeys: When `true`, preserve the case of keys in `values`.
    public init(values: [String: String], caseSensitiveKeys: Bool = false) {
        self.caseSensitiveKeys = caseSensitiveKeys
        self.values = Self.getEnvironment(caseSensitiveKeys: caseSensitiveKeys)
        for (key, value) in values {
            self.values[self.storageKey(key)] = value
        }
    }

    /// Initialize from dictionary literal
    public init(dictionaryLiteral elements: (String, String)...) {
        self.caseSensitiveKeys = false
        self.values = Self.getEnvironment(caseSensitiveKeys: false)
        for element in elements {
            self.values[self.storageKey(element.0)] = element.1
        }
    }

    /// Initialize from Decodable
    public init(from decoder: any Decoder) throws {
        self.caseSensitiveKeys = false
        self.values = Self.getEnvironment(caseSensitiveKeys: false)
        let container = try decoder.singleValueContainer()
        let decodedValues = try container.decode([String: String].self)
        for (key, value) in decodedValues {
            self.values[self.storageKey(key)] = value
        }
    }

    /// Get environment variable with name
    /// - Parameter s: Environment variable name
    public func get(_ s: String) -> String? {
        self.values[self.storageKey(s)]
    }

    /// Get environment variable with name as a certain type
    /// - Parameters:
    ///   - s: Environment variable name
    ///   - as: Type we want variable to be cast to
    public func get<T: LosslessStringConvertible>(_ s: String, as: T.Type) -> T? {
        self.values[self.storageKey(s)].map { T(String($0)) } ?? nil
    }

    /// Require environment variable with name
    /// - Parameter s: Environment variable name
    public func require(_ s: String) throws -> String {
        guard let value = self.values[self.storageKey(s)] else {
            throw Error(.variableDoesNotExist, message: "Environment variable '\(s)' does not exist")
        }
        return value
    }

    /// Require environment variable with name as a certain type
    /// - Parameters:
    ///   - s: Environment variable name
    ///   - as: Type we want variable to be cast to
    public func require<T: LosslessStringConvertible>(_ s: String, as: T.Type) throws -> T {
        let stringValue = try self.require(s)
        guard let value = T(stringValue) else {
            throw Error(.variableDoesNotConvert, message: "Environment variable '\(s)' can not be converted to \(T.self)")
        }
        return value
    }

    /// Set environment variable
    ///
    /// This sets the variable within this type and also calls `setenv` so future versions
    /// of this type will also have this variable set (using the exact key casing passed to `set`).
    ///
    /// - Warning: `setenv` and `unsetenv` are not thread-safe on Linux. Only call this during
    ///   application startup before concurrent tasks access the environment, unless you provide
    ///   your own synchronization.
    /// - Parameters:
    ///   - s: Environment variable name
    ///   - value: Environment variable name value
    public mutating func set(_ s: String, value: String?) {
        self.values[self.storageKey(s)] = value
        if let value {
            setenv(s, value, 1)
        } else {
            unsetenv(s)
        }
    }

    /// Set environment variable without synchronizing the process environment.
    ///
    /// Updates only this ``Environment`` instance. Use when you need to override variables
    /// for the current application without calling `setenv`.
    public mutating func setLocal(_ s: String, value: String?) {
        self.values[self.storageKey(s)] = value
    }

    /// Merge two environment variable sets together and return result
    ///
    /// If an environment variable exists in both sets it will choose the version from the second
    /// set of environment variables.
    ///
    /// The merged environment uses case-sensitive keys if either input environment uses them.
    /// - Parameter env: Environment variables to merge into this environment variable set
    public func merging(with env: Environment) -> Environment {
        .init(
            rawValues: self.values.merging(env.values) { $1 },
            caseSensitiveKeys: self.caseSensitiveKeys || env.caseSensitiveKeys
        )
    }

    /// Construct environment variable map
    static func getEnvironment(caseSensitiveKeys: Bool = false) -> [String: String] {
        var values: [String: String] = [:]
        for item in ProcessInfo.processInfo.environment {
            let key = caseSensitiveKeys ? item.key : item.key.lowercased()
            values[key] = item.value
        }
        return values
    }

    /// Create Environment initialised from the `.env` file
    ///
    /// If the file cannot be read, returns an environment containing the current process
    /// environment variables (same as ``init(caseSensitiveKeys:)``).
    /// - Parameters:
    ///   - dotEnvPath: Path to the `.env` file
    ///   - caseSensitiveKeys: When `true`, preserve the case of keys from the file
    public static func dotEnv(_ dotEnvPath: String = ".env", caseSensitiveKeys: Bool = false) async throws -> Self {
        guard let dotEnv = await loadDotEnv(dotEnvPath) else {
            return .init(caseSensitiveKeys: caseSensitiveKeys)
        }
        return try .init(rawValues: self.parseDotEnv(dotEnv, caseSensitiveKeys: caseSensitiveKeys), caseSensitiveKeys: caseSensitiveKeys)
    }

    /// Load `.env` file into string
    internal static func loadDotEnv(_ dotEnvPath: String = ".env") async -> String? {
        do {
            let fileHandle = try NIOFileHandle(path: dotEnvPath)
            defer {
                try? fileHandle.close()
            }
            let fileRegion = try FileRegion(fileHandle: fileHandle)
            let contents = try fileHandle.withUnsafeFileDescriptor { descriptor in
                [UInt8](unsafeUninitializedCapacity: fileRegion.readableBytes) { bytes, size in
                    size = fileRegion.readableBytes
                    read(descriptor, .init(bytes.baseAddress), size)
                }
            }
            return String(bytes: contents, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Parse a `.env` file
    internal static func parseDotEnv(_ dotEnv: String, caseSensitiveKeys: Bool = false) throws -> [String: String] {
        enum DotEnvParserState {
            case readingKey
            case skippingEquals(key: String)
            case readingValue(key: String)
        }
        var dotEnvDictionary: [String: String] = [:]
        var parser = Parser(dotEnv)
        var state: DotEnvParserState = .readingKey
        do {
            while !parser.reachedEnd() {
                parser.read(while: \.isWhitespace)

                switch state {
                case .readingKey:
                    // handle empty lines at the end
                    guard !parser.reachedEnd() else { break }

                    // check for comment
                    let c = parser.current()
                    if c == "#" {
                        do {
                            _ = try parser.read(until: \.isNewline)
                            parser.unsafeAdvance()
                        } catch Parser.Error.overflow {
                            parser.moveToEnd()
                            break
                        }
                        continue
                    }
                    let key = try parser.read(until: { $0.isWhitespace || $0 == "=" }).string
                    state = .skippingEquals(key: key)

                case .skippingEquals(let key):
                    let c = try parser.character()
                    // we are expecting an equals
                    guard c == "=" else { throw Error.dotEnvParseError }
                    state = .readingValue(key: key)

                case .readingValue(let key):
                    let value: String
                    if try parser.read("\"") {
                        value = try parser.read(until: { $0 == "\"" }).string
                        parser.unsafeAdvance()
                    } else {
                        value = try parser.read(until: \.isWhitespace, throwOnOverflow: false).string
                    }
                    dotEnvDictionary[caseSensitiveKeys ? key : key.lowercased()] = value
                    state = .readingKey
                }
            }
            guard case .readingKey = state else { throw Error.dotEnvParseError }
        } catch {
            throw Error.dotEnvParseError
        }
        return dotEnvDictionary
    }

    /// initialize from an already processed dictionary
    private init(rawValues: [String: String], caseSensitiveKeys: Bool = false) {
        self.values = rawValues
        self.caseSensitiveKeys = caseSensitiveKeys
    }

    private func storageKey(_ key: String) -> String {
        self.caseSensitiveKeys ? key : key.lowercased()
    }
}

extension Environment: CustomStringConvertible {
    public var description: String {
        String(describing: self.values)
    }
}
