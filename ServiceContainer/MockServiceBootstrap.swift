//
//  MockServiceBootstrap.swift
//  YourFramework
//
//  Created by GitHub Copilot on 2/23/26.
//

import Foundation
import os.log

/// Reads the mock service configuration from the process environment and registers
/// mock services into `ServiceContainer`, overwriting real service registrations.
///
/// Creates a single `MockSharedState` from the top-level `sharedState` config and
/// passes it to every mock service, so services that bind to the same shared state
/// key share the same `CurrentValueSubject` instance.
///
/// Call `MockServiceBootstrap.configureIfNeeded()` in the app's launch sequence
/// **after** `ServiceContainer.shared.registerDependencies(with:)`. When no
/// environment variable is present (i.e. normal app launch), this is a no-op.
///
/// ## Integration
/// ```swift
/// // In your app entry point (e.g. App.init or AppDelegate):
/// await ServiceContainer.shared.registerDependencies(with: resolver)
/// await MockServiceBootstrap.configureIfNeeded()
/// ```
///
/// ## XCUITest Side
/// ```swift
/// let app = XCUIApplication()
/// app.configureMockServices(config)
/// app.launch()
/// ```
public enum MockServiceBootstrap {

    private static let logger = Logger(
        subsystem: "com.example.service",
        category: "MockServiceBootstrap"
    )

    /// Checks for a mock configuration in the process environment and, if found,
    /// creates shared state and registers mock services into `ServiceContainer.shared`.
    ///
    /// This method is safe to call unconditionally — it returns immediately
    /// if no `MOCK_SERVICE_CONFIG` environment variable is set.
    public static func configureIfNeeded() async {
        guard let configuration = MockServiceConfiguration.fromEnvironment() else {
            return
        }

        logger.info("🧪 Mock service configuration detected. Registering mock services...")

        // Create shared state from the top-level config — one instance for the entire test run.
        let sharedState = MockSharedState(properties: configuration.sharedState)

        for (serviceName, entry) in configuration.services {
            await registerMockService(named: serviceName, with: entry, sharedState: sharedState)
        }

        logger.info("🧪 Mock service registration complete. \(configuration.services.count) service(s) configured.")
    }

    // MARK: - Service Registration Dispatch

    /// Maps a service protocol name to its concrete mock type and registers it.
    ///
    /// Add new cases here as additional mock service types are created.
    private static func registerMockService(
        named serviceName: String,
        with entry: MockServiceEntry,
        sharedState: MockSharedState
    ) async {
        switch serviceName {
        case "YourServiceProtocol":
            let mock = MockYourService(configuration: entry, sharedState: sharedState)
            await ServiceContainer.shared.register(mock, for: YourServiceProtocol.self)
            logger.info("  ✓ Registered MockYourService for YourServiceProtocol")

        // Future service mocks:
        //
        // case "SecondaryServiceProtocol":
        //     let mock = MockSecondaryService(configuration: entry, sharedState: sharedState)
        //     await ServiceContainer.shared.register(mock, for: SecondaryServiceProtocol.self)
        //     logger.info("  ✓ Registered MockSecondaryService")
        //
        // case "TertiaryServiceProtocol":
        //     let mock = MockTertiaryService(configuration: entry, sharedState: sharedState)
        //     await ServiceContainer.shared.register(mock, for: TertiaryServiceProtocol.self)
        //     logger.info("  ✓ Registered MockTertiaryService")

        default:
            logger.warning("  ⚠️ Unknown mock service: '\(serviceName)'. Skipping.")
        }
    }
}
