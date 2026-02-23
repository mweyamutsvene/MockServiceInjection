//
//  MockServiceMacros.swift
//  MockServiceMacro
//
//  Two macros that eliminate boilerplate in hand-written mock service actors.
//  The mock actor lives in your app/test target; these macros just reduce the
//  repetitive plumbing inside it.
//

// MARK: - @MockService

/// Injects `MockCallSequencer` infrastructure into a mock service actor.
///
/// Attach to an `actor` declaration that conforms to a service protocol. The macro
/// generates the following members:
///
/// - `private let sequencer: MockCallSequencer`
/// - `init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil)` — creates
///   the sequencer with shared state support and initializes any `CurrentValueSubject`
///   properties detected on the actor from shared state bindings or `initialState`.
///
/// You still write:
/// - The protocol conformance (`public actor Foo: BarProtocol`)
/// - Any `nonisolated let` properties (e.g. `CurrentValueSubject`)
/// - The required protocol `init` (typically 3 lines)
/// - Method signatures with `@MockMethod`
///
/// ## Example
///
/// ```swift
/// @MockService
/// public actor MockYourService: YourServiceProtocol {
///     nonisolated public let serviceStatus: CurrentValueSubject<ServiceStatus, Never>
///
///     public init(resolver: DependencyResolving?, settings: Settings) {
///         self.sequencer = MockCallSequencer(methods: [:])
///         self.serviceStatus = CurrentValueSubject(.idle)
///     }
///
///     @MockMethod public func performAction(input1: String, input2: String) async throws -> ServiceResponse
///     @MockMethod public func fetchData() async throws -> ServiceResponse
///     @MockMethod public func checkEligibility() async throws -> Bool
///     @MockMethod public func resetState() async
///     @MockMethod public func tearDown() async
/// }
/// ```
@attached(member, names: named(sequencer), named(init(configuration:sharedState:)))
public macro MockService() = #externalMacro(module: "MockServiceMacroPlugin", type: "MockServiceMacro")

// MARK: - @MockMethod

/// Generates the body of a mock method that delegates to `MockCallSequencer`.
///
/// Attach to a function declaration inside a `@MockService` actor. The macro inspects
/// the function's name and return type to generate the correct sequencer call:
///
/// - **Returning methods** (`-> T`):
///   - If `throws`: `try await sequencer.nextDecodedValue(for: "methodName", as: T.self)`
///   - If non-throwing: `try! await sequencer.nextDecodedValue(for: "methodName", as: T.self)`
///
/// - **Void methods** (no return type):
///   - If `throws`: `try await sequencer.recordVoidCall(for: "methodName")`
///   - If non-throwing: `try? await sequencer.recordVoidCall(for: "methodName")`
///
/// The method name string is derived from the function name automatically.
/// To override it (e.g. for overloaded methods), pass a custom key:
///
/// ```swift
/// @MockMethod("elevate")
/// public func elevate(level: AccessLevel, flow: FlowOption?) async throws -> ServiceResponse
/// ```
@attached(body)
public macro MockMethod(_ methodKey: String? = nil) = #externalMacro(module: "MockServiceMacroPlugin", type: "MockMethodMacro")
