//
//  MockCallSequencer.swift
//  YourFramework
//
//  Created by GitHub Copilot on 2/23/26.
//

import Foundation

/// A reusable actor that manages sequenced mock responses for any service.
///
/// Given a dictionary of method configurations (from the JSON config), the sequencer
/// tracks how many times each method has been called and returns the appropriate
/// response from the ordered sequence. After returning, it applies any `updateSharedState`
/// side effects to the shared state object.
///
/// Supports `repeatLast` and `fatalError` exhaust behaviors, optional simulated delays,
/// and error simulation.
///
/// This actor is the shared core used by all concrete mock services.
public actor MockCallSequencer {

    /// Method configurations keyed by method name.
    private let methods: [String: MockMethodConfig]

    /// Call counters keyed by method name. Tracks how many times each method has been invoked.
    private var callCounts: [String: Int] = [:]

    /// Reference to shared state for cross-service side effects. Optional — services
    /// without shared state bindings can still use the sequencer.
    private let sharedState: MockSharedState?

    /// Initializes the sequencer with method configurations and optional shared state.
    /// - Parameters:
    ///   - methods: The method configurations dictionary.
    ///   - sharedState: Optional shared state for cross-service updates.
    public init(methods: [String: MockMethodConfig], sharedState: MockSharedState? = nil) {
        self.methods = methods
        self.sharedState = sharedState
    }

    /// Convenience initializer from a `MockServiceEntry`.
    /// - Parameters:
    ///   - entry: The service entry containing method configurations.
    ///   - sharedState: Optional shared state for cross-service updates.
    public init(entry: MockServiceEntry, sharedState: MockSharedState? = nil) {
        self.methods = entry.methods
        self.sharedState = sharedState
    }

    // MARK: - Public API

    /// Returns the next `MockResponse` for the given method name, advancing the call counter.
    ///
    /// - If the method has no configuration, returns a default success response with nil value.
    /// - If all responses are exhausted, behavior depends on `exhaustBehavior`:
    ///   - `.repeatLast`: returns the last response again.
    ///   - `.fatalError`: crashes with a descriptive message.
    ///
    /// **Does not** apply shared state updates — callers should use `nextDecodedValue` or
    /// `recordVoidCall` which handle both response retrieval and side effects.
    ///
    /// - Parameter method: The method name (e.g. "performAction", "fetchData").
    /// - Returns: The `MockResponse` for this call.
    public func nextResponse(for method: String) -> MockResponse {
        guard let config = methods[method] else {
            // No configuration for this method — return a default no-op success.
            return MockResponse(result: .success, value: nil, error: nil, delayMs: nil)
        }

        let callIndex = callCounts[method, default: 0]
        callCounts[method] = callIndex + 1

        if callIndex < config.responses.count {
            return config.responses[callIndex]
        }

        // All responses consumed — apply exhaust behavior.
        switch config.exhaustBehavior {
        case .repeatLast:
            guard let lastResponse = config.responses.last else {
                // Empty responses array — return default no-op.
                return MockResponse(result: .success, value: nil, error: nil, delayMs: nil)
            }
            return lastResponse

        case .fatalError:
            Swift.fatalError(
                "[MockCallSequencer] All \(config.responses.count) responses for '\(method)' "
                + "have been consumed (call #\(callIndex + 1)). "
                + "exhaustBehavior is .fatalError."
            )
        }
    }

    /// Returns the next decoded value for a method, or throws if the response is an error.
    ///
    /// This is the primary API for mock methods that return a `Decodable` value.
    /// It advances the call counter, applies any configured delay, decodes the value
    /// or throws, and then applies any `updateSharedState` side effects from the response.
    ///
    /// - Parameters:
    ///   - method: The method name.
    ///   - type: The expected `Decodable` return type.
    /// - Returns: The decoded value.
    /// - Throws: `MockServiceError` if the response is an error, or `DecodingError` if decoding fails.
    public func nextDecodedValue<T: Decodable>(for method: String, as type: T.Type) async throws -> T {
        let response = nextResponse(for: method)

        // Apply simulated delay if configured.
        if let delayMs = response.delayMs, delayMs > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }

        // Check for error response.
        if response.result == .error {
            let payload = response.error ?? MockErrorPayload(code: "unknown", message: "Mock error (no payload)")
            throw MockServiceError(code: payload.code, message: payload.message)
        }

        // Decode the success value.
        guard let value = response.value else {
            throw MockServiceError(
                code: "missingValue",
                message: "Mock response for '\(method)' has result=success but no 'value' field. "
                    + "Expected a decodable \(T.self)."
            )
        }

        let jsonData = try value.toJSONData()
        let decoded = try JSONDecoder().decode(T.self, from: jsonData)

        // Apply shared state side effects after successful decode.
        if let updates = response.updateSharedState {
            sharedState?.applyUpdates(updates)
        }

        return decoded
    }

    /// Records a void method call, applying any configured delay, throwing if error,
    /// and applying shared state updates.
    ///
    /// Use this for mock methods that return `Void` (e.g. `resetState`, `tearDown`).
    ///
    /// - Parameter method: The method name.
    /// - Throws: `MockServiceError` if the response is configured as an error.
    public func recordVoidCall(for method: String) async throws {
        let response = nextResponse(for: method)

        // Apply simulated delay if configured.
        if let delayMs = response.delayMs, delayMs > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }

        // Check for error response.
        if response.result == .error {
            let payload = response.error ?? MockErrorPayload(code: "unknown", message: "Mock error (no payload)")
            throw MockServiceError(code: payload.code, message: payload.message)
        }

        // Apply shared state side effects.
        if let updates = response.updateSharedState {
            sharedState?.applyUpdates(updates)
        }
    }

    // MARK: - Diagnostic

    /// Returns the current call count for a specific method. Useful for test assertions.
    /// - Parameter method: The method name.
    /// - Returns: The number of times this method has been called.
    public func callCount(for method: String) -> Int {
        callCounts[method, default: 0]
    }

    /// Resets all call counters. Useful if a mock needs to be reused across test phases.
    public func resetCallCounts() {
        callCounts.removeAll()
    }
}
