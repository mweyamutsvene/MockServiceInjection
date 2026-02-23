//
//  MockSharedState.swift
//  YourFramework
//
//  Created by GitHub Copilot on 2/23/26.
//

@preconcurrency import Combine
import Foundation

/// Owns shared observable state that multiple mock services can read and write.
///
/// Created once by `MockServiceBootstrap` from the top-level `sharedState` JSON config,
/// then passed to every mock service that declares `bindings`. Services that bind to the
/// same shared state key receive the **same** `CurrentValueSubject` instance, so updates
/// from one service are immediately visible to all others.
///
/// ## Example
/// Two services bind to `"serviceStatus"`:
/// - `MockYourService` binds `serviceStatus → serviceStatus`
/// - `MockSecondaryService` binds `serviceStatus → serviceStatus`
///
/// When secondary service calls `updateSharedState: { "serviceStatus": 3 }`,
/// the primary service's `serviceStatus` subject receives the update automatically.
///
/// ## Thread Safety
/// `CurrentValueSubject` is internally thread-safe for `send`/`value` access.
/// This class is marked `@unchecked Sendable` because it holds `let` references to
/// subjects that are only created during `init` and never replaced.
public final class MockSharedState: @unchecked Sendable {

    /// Shared subjects keyed by shared state property name.
    /// Each subject holds an `AnyCodableValue` so mock services can interpret the
    /// value using their own domain type mappings (e.g. `AnyCodableValue.int(3)` → `ServiceStatus(rawValue: 3)`).
    private let subjects: [String: CurrentValueSubject<AnyCodableValue, Never>]

    /// Creates shared state from the top-level `sharedState` JSON config.
    ///
    /// - Parameter properties: The `sharedState` dictionary from `MockServiceConfiguration`.
    ///   Keys are property names, values contain the initial `AnyCodableValue`.
    public init(properties: [String: SharedStateProperty]?) {
        var built: [String: CurrentValueSubject<AnyCodableValue, Never>] = [:]
        for (key, prop) in properties ?? [:] {
            built[key] = CurrentValueSubject<AnyCodableValue, Never>(prop.initial)
        }
        self.subjects = built
    }

    /// Returns the shared subject for a given key, or `nil` if no shared state property
    /// was declared for that key.
    ///
    /// Mock services call this during `init` to obtain the `CurrentValueSubject` they
    /// should expose as their protocol's observable property.
    ///
    /// - Parameter key: The shared state property name (e.g. "serviceStatus").
    /// - Returns: The `CurrentValueSubject<AnyCodableValue, Never>` for that key, or `nil`.
    public func subject(for key: String) -> CurrentValueSubject<AnyCodableValue, Never>? {
        subjects[key]
    }

    /// Applies a batch of shared state updates, typically from a `MockResponse.updateSharedState`.
    ///
    /// Each key in the dictionary is a shared state property name. The corresponding
    /// subject has its value sent. All subscribers (across all mock services that bind
    /// to that key) see the update immediately.
    ///
    /// - Parameter updates: A dictionary of `[sharedStateKey: newValue]`.
    public func applyUpdates(_ updates: [String: AnyCodableValue]) {
        for (key, value) in updates {
            subjects[key]?.send(value)
        }
    }
}
