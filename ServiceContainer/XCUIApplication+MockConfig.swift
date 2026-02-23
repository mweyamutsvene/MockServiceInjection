//
//  XCUIApplication+MockConfig.swift
//  YourUITestTarget
//
//  Created by GitHub Copilot on 2/23/26.
//

#if canImport(XCTest)

import XCTest

extension XCUIApplication {

    // MARK: - Configuration Injection

    /// Encodes a `MockServiceConfiguration` into the app's launch environment.
    ///
    /// The configuration is serialized to JSON, base64-encoded, and stored in
    /// `launchEnvironment["MOCK_SERVICE_CONFIG"]`. On launch, `MockServiceBootstrap`
    /// reads this value and registers mock services.
    ///
    /// Call this **before** `launch()`:
    ///
    /// ```swift
    /// let app = XCUIApplication()
    /// app.configureMockServices(myConfig)
    /// app.launch()
    /// ```
    ///
    /// - Parameter config: The mock service configuration to inject.
    public func configureMockServices(_ config: MockServiceConfiguration) {
        guard let base64 = try? config.toBase64() else {
            XCTFail("Failed to encode MockServiceConfiguration to base64.")
            return
        }
        launchEnvironment[MockServiceConfiguration.environmentKey] = base64
    }

    // MARK: - Convenience Builders

    /// Creates a `MockServiceConfiguration` with shared state and multiple service entries,
    /// then injects it into the launch environment.
    ///
    /// - Parameters:
    ///   - sharedState: Top-level shared state property declarations.
    ///   - services: Service entries keyed by protocol name.
    public func configureMockServices(
        sharedState: [String: SharedStateProperty]? = nil,
        services: [String: MockServiceEntry]
    ) {
        let config = MockServiceConfiguration(
            sharedState: sharedState,
            services: services
        )
        configureMockServices(config)
    }
}

// MARK: - Response Builder Helpers

/// Convenience factory methods for building mock configurations with less boilerplate.
extension MockResponse {

    /// A simple success response with an encodable value.
    ///
    /// ```swift
    /// MockResponse.success(["status": .int(3)])
    /// ```
    public static func success(
        _ value: AnyCodableValue? = nil,
        delayMs: Int? = nil,
        updateSharedState: [String: AnyCodableValue]? = nil
    ) -> MockResponse {
        MockResponse(
            result: .success,
            value: value,
            delayMs: delayMs,
            updateSharedState: updateSharedState
        )
    }

    /// A simple error response.
    ///
    /// ```swift
    /// MockResponse.error(code: "timeout", message: "Session expired")
    /// ```
    public static func error(
        code: String,
        message: String,
        delayMs: Int? = nil,
        updateSharedState: [String: AnyCodableValue]? = nil
    ) -> MockResponse {
        MockResponse(
            result: .error,
            error: MockErrorPayload(code: code, message: message),
            delayMs: delayMs,
            updateSharedState: updateSharedState
        )
    }
}

extension MockMethodConfig {

    /// Creates a method config with a single success response.
    public static func singleSuccess(
        _ value: AnyCodableValue? = nil,
        updateSharedState: [String: AnyCodableValue]? = nil
    ) -> MockMethodConfig {
        MockMethodConfig(responses: [
            .success(value, updateSharedState: updateSharedState)
        ])
    }

    /// Creates a method config with a single error response.
    public static func singleError(code: String, message: String) -> MockMethodConfig {
        MockMethodConfig(responses: [
            .error(code: code, message: message)
        ])
    }

    /// Creates a method config that always succeeds with no value (for void methods).
    public static var voidSuccess: MockMethodConfig {
        MockMethodConfig(responses: [.success()])
    }
}

// MARK: - Usage Examples

/*

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 EXAMPLE: Standard Flow → Fetch Data → Finalize
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 func testStandardFlow() {
     let app = XCUIApplication()

     app.configureMockServices(
         sharedState: [
             "serviceStatus": SharedStateProperty(initial: .int(0))
         ],
         services: [
             "YourServiceProtocol": MockServiceEntry(
                 bindings: ["serviceStatus": "serviceStatus"],
                 methods: [
                     "performAction": MockMethodConfig(responses: [
                         .success(
                             .dictionary(["status": .int(3)]),
                             updateSharedState: ["serviceStatus": .int(3)]
                         )
                     ]),
                     "fetchData": MockMethodConfig(responses: [
                         .success(.dictionary(["status": .int(5)]))
                     ]),
                     "checkEligibility": .singleSuccess(.bool(true)),
                     "finalize": MockMethodConfig(responses: [
                         .success(
                             .dictionary(["status": .int(7)]),
                             updateSharedState: ["serviceStatus": .int(7)]
                         )
                     ]),
                     "resetState": .voidSuccess,
                     "tearDown": .voidSuccess
                 ]
             )
         ]
     )

     app.launch()
     // ... drive UI and assert
 }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 EXAMPLE: Cross-Service Shared State (Secondary + Primary)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 func testSecondaryServiceFlow() {
     let app = XCUIApplication()

     app.configureMockServices(
         sharedState: [
             "serviceStatus": SharedStateProperty(initial: .int(0))
         ],
         services: [
             "YourServiceProtocol": MockServiceEntry(
                 bindings: ["serviceStatus": "serviceStatus"],
                 methods: [
                     "fetchData": .singleSuccess(.dictionary(["status": .int(5)])),
                     "checkEligibility": .singleSuccess(.bool(true)),
                     "finalize": MockMethodConfig(responses: [
                         .success(
                             .dictionary(["status": .int(7)]),
                             updateSharedState: ["serviceStatus": .int(7)]
                         )
                     ]),
                     "resetState": .voidSuccess,
                     "tearDown": .voidSuccess
                 ]
             ),
             "SecondaryServiceProtocol": MockServiceEntry(
                 bindings: ["serviceStatus": "serviceStatus"],
                 methods: [
                     "performAction": MockMethodConfig(responses: [
                         .success(
                             .dictionary(["status": .int(3)]),
                             updateSharedState: ["serviceStatus": .int(3)]
                         )
                     ])
                 ]
             )
         ]
     )

     app.launch()
     // Secondary service updates shared serviceStatus → YourService sees it
 }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 EXAMPLE: Error Simulation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 func testServiceFailure() {
     let app = XCUIApplication()

     app.configureMockServices(
         services: [
             "YourServiceProtocol": MockServiceEntry(
                 methods: [
                     "performAction": .singleError(
                         code: "invalidInput",
                         message: "The provided input was invalid."
                     )
                 ]
             )
         ]
     )

     app.launch()
     // ... assert error UI
 }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 EXAMPLE: Multi-Call Sequence
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 func testRetryableAction() {
     let app = XCUIApplication()

     app.configureMockServices(
         sharedState: [
             "serviceStatus": SharedStateProperty(initial: .int(0))
         ],
         services: [
             "YourServiceProtocol": MockServiceEntry(
                 bindings: ["serviceStatus": "serviceStatus"],
                 methods: [
                     "performAction": MockMethodConfig(responses: [
                         // 1st call: fails
                         .error(code: "networkTimeout", message: "Connection timed out"),
                         // 2nd call: succeeds
                         .success(
                             .dictionary(["status": .int(3)]),
                             updateSharedState: ["serviceStatus": .int(3)]
                         )
                     ])
                 ]
             )
         ]
     )

     app.launch()
     // ... drive retry flow
 }

*/

#endif
