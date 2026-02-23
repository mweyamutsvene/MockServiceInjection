//
//  MockServiceMacroTests.swift
//  MockServiceMacroTests
//
//  Tests for @MockService and @MockMethod macro expansions.
//

import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(MockServiceMacroPlugin)
@testable import MockServiceMacroPlugin
#endif

final class MockServiceMacroTests: XCTestCase {

    // MARK: - @MockService Tests

    func testMockService_injectsSequencerAndConfigInit() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockService
            public actor MockGreetingService: GreetingServiceProtocol {
                @MockMethod
                public func greet(name: String) async throws -> String

                @MockMethod
                public func reset() async
            }
            """,
            expandedSource: """
            public actor MockGreetingService: GreetingServiceProtocol {
                @MockMethod
                public func greet(name: String) async throws -> String

                @MockMethod
                public func reset() async

                private let sequencer: MockCallSequencer

                public init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil) {
                    self.sequencer = MockCallSequencer(entry: configuration, sharedState: sharedState)
                }
            }
            """,
            macros: ["MockService": MockServiceMacro.self, "MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    func testMockService_detectsCurrentValueSubjectProperties() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockService
            public actor MockPrimaryService: PrimaryServiceProtocol {
                nonisolated public let status: CurrentValueSubject<ServiceStatus, Never>

                public init(resolver: Resolver?, settings: Settings) {
                    self.sequencer = MockCallSequencer(methods: [:])
                    self.status = CurrentValueSubject(.idle)
                }

                @MockMethod
                public func performAction(input: String, secret: String) async throws -> Response
            }
            """,
            expandedSource: """
            public actor MockPrimaryService: PrimaryServiceProtocol {
                nonisolated public let status: CurrentValueSubject<ServiceStatus, Never>

                public init(resolver: Resolver?, settings: Settings) {
                    self.sequencer = MockCallSequencer(methods: [:])
                    self.status = CurrentValueSubject(.idle)
                }

                @MockMethod
                public func performAction(input: String, secret: String) async throws -> Response

                private let sequencer: MockCallSequencer

                public init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil) {
                    self.sequencer = MockCallSequencer(entry: configuration, sharedState: sharedState)
                    if let bindingKey = configuration.bindings?["status"],
                       let subject = sharedState?.subject(for: bindingKey) {
                        if case .int(let rawValue) = subject.value,
                           let status = ServiceStatus(rawValue: rawValue) {
                            self.status = CurrentValueSubject<ServiceStatus, Never>(status)
                        } else {
                            self.status = CurrentValueSubject<ServiceStatus, Never>(.idle)
                        }
                    } else if let initialState = configuration.initialState,
                              let stateValue = initialState["status"],
                              case .int(let rawValue) = stateValue,
                              let status = ServiceStatus(rawValue: rawValue) {
                        self.status = CurrentValueSubject<ServiceStatus, Never>(status)
                    } else {
                        self.status = CurrentValueSubject<ServiceStatus, Never>(.idle)
                    }
                }
            }
            """,
            macros: ["MockService": MockServiceMacro.self, "MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    func testMockService_rejectsNonActor() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockService
            public class NotAnActor {}
            """,
            expandedSource: """
            public class NotAnActor {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@MockService can only be applied to an actor declaration.", line: 1, column: 1)
            ],
            macros: ["MockService": MockServiceMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    // MARK: - @MockMethod Tests

    func testMockMethod_throwingWithReturnType() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockMethod
            public func performAction(input1: String, input2: String) async throws -> ServiceResponse
            """,
            expandedSource: """
            public func performAction(input1: String, input2: String) async throws -> ServiceResponse {
                try await sequencer.nextDecodedValue(for: "performAction", as: ServiceResponse.self)
            }
            """,
            macros: ["MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    func testMockMethod_throwingBoolReturn() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockMethod
            public func checkEligibility() async throws -> Bool
            """,
            expandedSource: """
            public func checkEligibility() async throws -> Bool {
                try await sequencer.nextDecodedValue(for: "checkEligibility", as: Bool.self)
            }
            """,
            macros: ["MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    func testMockMethod_voidNonThrowing() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockMethod
            public func resetState() async
            """,
            expandedSource: """
            public func resetState() async {
                try? await sequencer.recordVoidCall(for: "resetState")
            }
            """,
            macros: ["MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    func testMockMethod_voidThrowing() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockMethod
            public func dangerousReset() async throws
            """,
            expandedSource: """
            public func dangerousReset() async throws {
                try await sequencer.recordVoidCall(for: "dangerousReset")
            }
            """,
            macros: ["MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    func testMockMethod_customKey() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockMethod("elevate")
            public func elevate(level: AccessLevel, flow: FlowOption?) async throws -> ServiceResponse
            """,
            expandedSource: """
            public func elevate(level: AccessLevel, flow: FlowOption?) async throws -> ServiceResponse {
                try await sequencer.nextDecodedValue(for: "elevate", as: ServiceResponse.self)
            }
            """,
            macros: ["MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }

    func testMockMethod_rejectsNonFunction() throws {
        #if canImport(MockServiceMacroPlugin)
        assertMacroExpansion(
            """
            @MockMethod
            public var name: String
            """,
            expandedSource: """
            public var name: String
            """,
            diagnostics: [
                DiagnosticSpec(message: "@MockMethod can only be applied to a function declaration.", line: 1, column: 1)
            ],
            macros: ["MockMethod": MockMethodMacro.self]
        )
        #else
        throw XCTSkip("Macros are only supported when running tests for the host platform")
        #endif
    }
}
