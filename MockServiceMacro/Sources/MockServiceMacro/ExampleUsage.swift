//
//  ExampleUsage.swift
//  MockServiceMacro
//
//  Shows how @MockService + @MockMethod replace hand-written mock boilerplate.
//  Uses concrete service examples with shared state.
//

/*

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BEFORE: Hand-written mock (~110 lines)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

public actor MockYourService: YourServiceProtocol {
    nonisolated public let serviceStatus: CurrentValueSubject<ServiceStatus, Never>
    private let sequencer: MockCallSequencer       // ← boilerplate

    public init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil) {
        self.sequencer = MockCallSequencer(entry: configuration, sharedState: sharedState)

        // Binding → initialState → default  (repeated per CVS property)
        if let bindingKey = configuration.bindings?["serviceStatus"],
           let subject = sharedState?.subject(for: bindingKey) {
            if case .int(let rawValue) = subject.value,
               let status = ServiceStatus(rawValue: rawValue) {
                self.serviceStatus = CurrentValueSubject(status)
            } else {
                self.serviceStatus = CurrentValueSubject(.idle)
            }
        } else if let initialState = configuration.initialState,
                  let stateValue = initialState["serviceStatus"],
                  case .int(let rawValue) = stateValue,
                  let status = ServiceStatus(rawValue: rawValue) {
            self.serviceStatus = CurrentValueSubject(status)
        } else {
            self.serviceStatus = CurrentValueSubject(.idle)
        }
    }

    public init(resolver: DependencyResolving?, settings: Settings) {
        self.sequencer = MockCallSequencer(methods: [:])
        self.serviceStatus = CurrentValueSubject(.idle)
    }

    public func performAction(input1: String, input2: String) async throws -> ServiceResponse {
        try await sequencer.nextDecodedValue(for: "performAction", as: ServiceResponse.self)  // ← boilerplate
    }
    public func elevate(level: AccessLevel, flow: FlowOption?) async throws -> ServiceResponse {
        try await sequencer.nextDecodedValue(for: "elevate", as: ServiceResponse.self)  // ← boilerplate
    }
    public func fetchData() async throws -> ServiceResponse {
        try await sequencer.nextDecodedValue(for: "fetchData", as: ServiceResponse.self)  // ← boilerplate
    }
    public func checkEligibility() async throws -> Bool {
        try await sequencer.nextDecodedValue(for: "checkEligibility", as: Bool.self)  // ← boilerplate
    }
    public func finalize() async throws -> ServiceResponse {
        try await sequencer.nextDecodedValue(for: "finalize", as: ServiceResponse.self)  // ← boilerplate
    }
    public func resetState() async {
        try? await sequencer.recordVoidCall(for: "resetState")  // ← boilerplate
    }
    public func tearDown() async {
        try? await sequencer.recordVoidCall(for: "tearDown")  // ← boilerplate
    }
}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AFTER: With @MockService + @MockMethod

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import MockServiceMacro

@MockService
public actor MockYourService: YourServiceProtocol {

    // You write these — they're protocol-specific:
    nonisolated public let serviceStatus: CurrentValueSubject<ServiceStatus, Never>

    public init(resolver: DependencyResolving?, settings: Settings) {
        self.sequencer = MockCallSequencer(methods: [:])
        self.serviceStatus = CurrentValueSubject(.idle)
    }

    // @MockMethod generates each body from the function signature:
    @MockMethod public func performAction(input1: String, input2: String) async throws -> ServiceResponse
    @MockMethod public func elevate(level: AccessLevel, flow: FlowOption?) async throws -> ServiceResponse
    @MockMethod public func fetchData() async throws -> ServiceResponse
    @MockMethod public func checkEligibility() async throws -> Bool
    @MockMethod public func finalize() async throws -> ServiceResponse
    @MockMethod public func resetState() async
    @MockMethod public func tearDown() async
}

// @MockService generates (visible via "Expand Macro" in Xcode):
//   private let sequencer: MockCallSequencer
//   public init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil) {
//       self.sequencer = MockCallSequencer(entry: configuration, sharedState: sharedState)
//       // For each CurrentValueSubject property:
//       if let bindingKey = configuration.bindings?["serviceStatus"],
//          let subject = sharedState?.subject(for: bindingKey) {
//           if case .int(let rawValue) = subject.value,
//              let status = ServiceStatus(rawValue: rawValue) {
//               self.serviceStatus = CurrentValueSubject<ServiceStatus, Never>(status)
//           } else {
//               self.serviceStatus = CurrentValueSubject<ServiceStatus, Never>(.idle)
//           }
//       } else if let initialState = configuration.initialState,
//                 let stateValue = initialState["serviceStatus"],
//                 case .int(let rawValue) = stateValue,
//                 let status = ServiceStatus(rawValue: rawValue) {
//           self.serviceStatus = CurrentValueSubject<ServiceStatus, Never>(status)
//       } else {
//           self.serviceStatus = CurrentValueSubject<ServiceStatus, Never>(.idle)
//       }
//   }
//
// @MockMethod on each function generates the body:
//   performAction → { try await sequencer.nextDecodedValue(for: "performAction", as: ServiceResponse.self) }
//   checkEligibility → { try await sequencer.nextDecodedValue(for: "checkEligibility", as: Bool.self) }
//   resetState → { try? await sequencer.recordVoidCall(for: "resetState") }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

WHAT EACH MACRO DOES

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@MockService (member macro on the actor):
  ✓ Adds `private let sequencer: MockCallSequencer`
  ✓ Adds `init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil)` with:
    - Sequencer setup (passes sharedState for cross-service side effects)
    - Auto-detected CurrentValueSubject initialization:
      1. Checks shared state bindings first (via configuration.bindings + sharedState)
      2. Falls back to initialState (int-based raw values)
      3. Defaults to .idle
  ✗ Does NOT generate the required protocol init — you write that (3 lines)
  ✗ Does NOT generate method signatures — you write those with @MockMethod

@MockMethod (body macro on each function):
  ✓ Reads the function name → sequencer key (e.g. "performAction")
  ✓ Reads the return type → nextDecodedValue or recordVoidCall
  ✓ Reads throws/non-throws → try vs try? vs try!
  ✓ Supports custom key: @MockMethod("customKey") for overloaded methods
  ✗ Does NOT generate the function signature — you write that

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CROSS-SERVICE SHARED STATE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MockSharedState holds CurrentValueSubject<AnyCodableValue, Never> for each key.
Services declare bindings to map their properties to shared state keys.
When a mock response includes `updateSharedState`, the sequencer pushes new values
to all services that bind to those keys.

JSON config example (secondary service updates serviceStatus → primary service sees it):

{
  "sharedState": {
    "serviceStatus": { "initial": 0 }
  },
  "services": {
    "YourServiceProtocol": {
      "bindings": { "serviceStatus": "serviceStatus" },
      "methods": {
        "fetchData": { "responses": [{ "result": "success", "value": { "status": 5 } }] },
        "checkEligibility": { "responses": [{ "result": "success", "value": true }] },
        "finalize": {
          "responses": [{
            "result": "success",
            "value": { "status": 7 },
            "updateSharedState": { "serviceStatus": 7 }
          }]
        }
      }
    },
    "SecondaryServiceProtocol": {
      "bindings": { "serviceStatus": "serviceStatus" },
      "methods": {
        "performAction": {
          "responses": [{
            "result": "success",
            "value": { "status": 3 },
            "updateSharedState": { "serviceStatus": 3 }
          }]
        }
      }
    }
  }
}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

WHY THIS IS BETTER THAN @GenerateMock ON THE PROTOCOL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Mocks live in the playground app target, NOT in the framework.
   The protocol in the framework is untouched — no macro annotation, no import.
   CocoaPods consumers never see MockServiceMacro.

2. The compiler verifies protocol conformance.
   If the protocol adds a new method, the actor fails to compile until you
   add the new @MockMethod signature. No silent drift.

3. You control what you write vs what's generated.
   Required protocol init = you write it (protocol-specific).
   Method bodies = generated (always the same pattern).
   Sequencer plumbing = generated (always the same).

4. Macro expansion is debuggable.
   Right-click → "Expand Macro" in Xcode shows the generated code inline.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INTEGRATION

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

In the playground app's Xcode project:
  1. Drag MockServiceMacro/ into the project (Add Local Package)
  2. Add MockServiceMacro to the app target's dependencies
  3. import MockServiceMacro in your mock files

The framework's Podfile / podspec — unchanged.
The enterprise app — unchanged.

*/
