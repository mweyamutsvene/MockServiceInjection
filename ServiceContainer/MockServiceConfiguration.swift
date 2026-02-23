//
//  MockServiceConfiguration.swift
//  YourFramework
//
//  Created by GitHub Copilot on 2/23/26.
//

import Foundation

// MARK: - AnyCodableValue

/// A lightweight type-erased JSON value that supports encoding/decoding arbitrary JSON structures.
/// Used to transport opaque response payloads through the mock configuration layer.
public enum AnyCodableValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null
}

extension AnyCodableValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([AnyCodableValue].self) {
            self = .array(arrayValue)
        } else if let dictValue = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dictValue)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value type"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension AnyCodableValue {
    /// Converts this `AnyCodableValue` back into serialized JSON `Data`,
    /// suitable for decoding into a concrete `Decodable` type.
    public func toJSONData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

// MARK: - MockErrorPayload

/// Describes an error to be thrown by a mock method call.
public struct MockErrorPayload: Codable, Sendable {
    /// A domain-specific error code string (e.g. "timeout", "networkTimeout").
    public let code: String
    /// A human-readable error description.
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - ExhaustBehavior

/// Controls what happens when all configured responses for a method have been consumed.
public enum ExhaustBehavior: String, Codable, Sendable {
    /// Re-use the last response for all subsequent calls. This is the default.
    case repeatLast
    /// Trigger a `fatalError` to catch unexpected extra calls during testing.
    case fatalError
}

// MARK: - MockResponse

/// A single configured response for a mock method call.
public struct MockResponse: Codable, Sendable {
    /// The result type of this response.
    public let result: ResultType

    /// The JSON value to decode into the method's return type. Nil for void methods.
    public let value: AnyCodableValue?

    /// The error payload to throw if `result` is `.error`.
    public let error: MockErrorPayload?

    /// Optional simulated delay in milliseconds before the response is returned.
    public let delayMs: Int?

    /// Optional shared state updates to apply after this response is returned.
    /// Keys are shared state property names, values are the new `AnyCodableValue` to send.
    ///
    /// Example JSON: `"updateSharedState": { "serviceStatus": 3 }`
    public let updateSharedState: [String: AnyCodableValue]?

    public init(
        result: ResultType,
        value: AnyCodableValue? = nil,
        error: MockErrorPayload? = nil,
        delayMs: Int? = nil,
        updateSharedState: [String: AnyCodableValue]? = nil
    ) {
        self.result = result
        self.value = value
        self.error = error
        self.delayMs = delayMs
        self.updateSharedState = updateSharedState
    }

    /// Whether this response represents a success or an error.
    public enum ResultType: String, Codable, Sendable {
        case success
        case error
    }
}

// MARK: - MockMethodConfig

/// Configuration for a single mock method, containing an ordered sequence of responses.
public struct MockMethodConfig: Codable, Sendable {
    /// Ordered list of responses. The Nth call returns the Nth element.
    public let responses: [MockResponse]

    /// Behavior when all responses have been consumed. Defaults to `.repeatLast`.
    public let exhaustBehavior: ExhaustBehavior

    public init(
        responses: [MockResponse],
        exhaustBehavior: ExhaustBehavior = .repeatLast
    ) {
        self.responses = responses
        self.exhaustBehavior = exhaustBehavior
    }

    enum CodingKeys: String, CodingKey {
        case responses
        case exhaustBehavior
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.responses = try container.decode([MockResponse].self, forKey: .responses)
        self.exhaustBehavior = try container.decodeIfPresent(ExhaustBehavior.self, forKey: .exhaustBehavior) ?? .repeatLast
    }
}

// MARK: - SharedStateProperty

/// Declares a single shared state property in the top-level `sharedState` config.
///
/// Example JSON: `{ "initial": 0 }` or `{ "initial": "inactive" }`
public struct SharedStateProperty: Codable, Sendable {
    /// The initial value of this shared state property.
    public let initial: AnyCodableValue

    public init(initial: AnyCodableValue) {
        self.initial = initial
    }
}

// MARK: - MockServiceEntry

/// Configuration for a single mock service, containing bindings and method configurations.
public struct MockServiceEntry: Codable, Sendable {
    /// Optional initial state values for the service (e.g. for service-local state only).
    public let initialState: [String: AnyCodableValue]?

    /// Maps service property names to shared state keys.
    /// E.g. `{ "serviceStatus": "serviceStatus" }`
    /// Services with bindings receive the shared `CurrentValueSubject` for that key,
    /// so multiple services that bind to the same key share the same observable.
    public let bindings: [String: String]?

    /// Method configurations keyed by method name.
    public let methods: [String: MockMethodConfig]

    public init(
        initialState: [String: AnyCodableValue]? = nil,
        bindings: [String: String]? = nil,
        methods: [String: MockMethodConfig]
    ) {
        self.initialState = initialState
        self.bindings = bindings
        self.methods = methods
    }
}

// MARK: - MockServiceConfiguration

/// Top-level configuration containing shared state declarations and all mock service definitions.
/// Passed from XCUITest to the app via a base64-encoded environment variable.
///
/// ## JSON Structure
/// ```json
/// {
///   "sharedState": {
///     "serviceStatus": { "initial": 0 }
///   },
///   "services": {
///     "YourServiceProtocol": {
///       "bindings": { "serviceStatus": "serviceStatus" },
///       "methods": {
///         "performAction": {
///           "responses": [{
///             "result": "success",
///             "value": { "status": 3 },
///             "updateSharedState": { "serviceStatus": 3 }
///           }]
///         }
///       }
///     }
///   }
/// }
/// ```
public struct MockServiceConfiguration: Codable, Sendable {
    /// Shared state properties that can be observed across multiple mock services.
    /// Keys are property names (e.g. "serviceStatus"), values define the initial value.
    public let sharedState: [String: SharedStateProperty]?

    /// Service configurations keyed by protocol name (e.g. "YourServiceProtocol").
    public let services: [String: MockServiceEntry]

    public init(
        sharedState: [String: SharedStateProperty]? = nil,
        services: [String: MockServiceEntry]
    ) {
        self.sharedState = sharedState
        self.services = services
    }

    // MARK: - Environment Variable Transport

    /// The environment variable key used to pass the mock configuration.
    public static let environmentKey = "MOCK_SERVICE_CONFIG"

    /// Attempts to read and decode a `MockServiceConfiguration` from the process environment.
    /// Returns `nil` if the environment variable is not set or decoding fails.
    public static func fromEnvironment() -> MockServiceConfiguration? {
        guard let base64String = ProcessInfo.processInfo.environment[environmentKey],
              let jsonData = Data(base64Encoded: base64String) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(MockServiceConfiguration.self, from: jsonData)
        } catch {
            assertionFailure("Failed to decode MockServiceConfiguration from environment: \(error)")
            return nil
        }
    }

    /// Encodes this configuration to a base64 string suitable for setting as an environment variable.
    public func toBase64() throws -> String {
        let jsonData = try JSONEncoder().encode(self)
        return jsonData.base64EncodedString()
    }
}
