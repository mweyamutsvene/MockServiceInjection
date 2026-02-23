//
//  MockServiceError.swift
//  YourFramework
//
//  Created by GitHub Copilot on 2/23/26.
//

import Foundation

/// An error thrown by mock services when a response is configured as an error.
///
/// This is a generic error type used across all mock services. It carries a `code`
/// and `message` from the JSON configuration, allowing test authors to simulate
/// specific failure scenarios (e.g. "timeout", "networkTimeout").
///
/// If domain-specific error mapping is needed (e.g. converting to `AuthError`),
/// concrete mock services can catch `MockServiceError` and rethrow the appropriate
/// domain error type.
public struct MockServiceError: Error, Sendable, CustomStringConvertible {
    /// A domain-specific error code string (e.g. "timeout", "networkTimeout").
    public let code: String

    /// A human-readable error description.
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    /// Convenience initializer from a `MockErrorPayload`.
    public init(payload: MockErrorPayload) {
        self.code = payload.code
        self.message = payload.message
    }

    public var description: String {
        "MockServiceError(code: \"\(code)\", message: \"\(message)\")"
    }
}

extension MockServiceError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}
