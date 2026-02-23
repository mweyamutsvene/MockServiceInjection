# Composable Scenario Builder — Implementation Plan

This file defines the full architecture for a composable, preset-driven
XCUITest mock configuration layer that sits on top of the existing
MockServiceConfiguration / MockServiceBootstrap infrastructure.

Nothing here changes the existing infrastructure. This produces a
MockServiceConfiguration at the end — same base64 → launch environment
→ bootstrap pipeline.

```
┌──────────────────────────────────────────────────────────┐
│  Test call site                                           │
│  MockScenario.build()                                     │
│      .withPrimary(.happyPath)                             │
│      .withSecondary(.enabled)                             │
│      .apply(to: app)                                      │
├──────────────────────────────────────────────────────────┤
│  Per-service presets (PrimaryPreset, SecondaryPreset)      │
│  Each knows its own methods, bindings, and state           │
├──────────────────────────────────────────────────────────┤
│  Existing infrastructure (unchanged)                       │
│  MockServiceConfiguration → base64 → bootstrap             │
└──────────────────────────────────────────────────────────┘
```

---

## 1. MockServicePreset Protocol

```swift
import Foundation

#if canImport(XCTest)
import XCTest

/// Every per-service preset conforms to this protocol.
/// It knows how to produce a `MockServiceEntry` and declare what shared state it needs.
protocol MockServicePreset {
    /// The protocol name string used as the key in `MockServiceConfiguration.services`.
    /// Must match the `case` in `MockServiceBootstrap.registerMockService(named:with:sharedState:)`.
    static var serviceName: String { get }

    /// Shared state properties this preset requires.
    /// The builder merges these across all composed presets.
    var sharedState: [String: SharedStateProperty] { get }

    /// The fully configured `MockServiceEntry` for this preset.
    var serviceEntry: MockServiceEntry { get }
}
```

---

## 2. Per-Service Presets

Create one enum per service protocol. Each case is a named scenario with
sensible defaults. Parameters allow surgical overrides without exposing
the raw MockMethodConfig / AnyCodableValue internals.

**Naming convention:** `enum <Feature>Preset: MockServicePreset { ... }`

Every enum must include a `.custom(...)` escape hatch for one-off tests.

### Example: PrimaryServiceProtocol

Methods: `performAction`, `verifyIdentity`, `canVerifyIdentity`, `finalizeSession`, `resetProfiler`, `signOut`
Observable: `sessionStatus` (shared state, Int raw value)

```swift
enum PrimaryPreset: MockServicePreset {

    static let serviceName = "PrimaryServiceProtocol"

    // ── Preset Cases ──────────────────────────────────────────────────────

    /// Full happy path: perform → verify → finalize all succeed.
    /// sessionStatus transitions: 0 → actionStatus → finalStatus
    case happyPath(
        initialStatus: Int = 0,
        actionStatus: Int = 3,
        finalStatus: Int = 7
    )

    /// The primary action fails with a domain error.
    case actionFails(
        code: String = "invalidInput",
        message: String = "The provided input was invalid."
    )

    /// First attempt fails, retry succeeds.
    case failThenRetry(
        errorCode: String = "networkTimeout",
        retryStatus: Int = 3
    )

    /// Elevated access required after initial action.
    case elevatedAccessRequired(
        initialStatus: Int = 3,
        elevatedStatus: Int = 5,
        finalStatus: Int = 7
    )

    /// Session already established — for tests that start mid-flow.
    case alreadyEstablished(status: Int = 7)

    /// Escape hatch for one-off scenarios.
    case custom(
        sharedState: [String: SharedStateProperty],
        entry: MockServiceEntry
    )

    // ── Shared State ──────────────────────────────────────────────────────

    var sharedState: [String: SharedStateProperty] {
        switch self {
        case .custom(let state, _):
            return state
        case .alreadyEstablished(let status):
            return ["sessionStatus": SharedStateProperty(initial: .int(status))]
        default:
            return ["sessionStatus": SharedStateProperty(initial: .int(0))]
        }
    }

    // ── Service Entry ─────────────────────────────────────────────────────

    var serviceEntry: MockServiceEntry {
        switch self {

        case .happyPath(_, let actionStatus, let finalStatus):
            return MockServiceEntry(
                bindings: ["sessionStatus": "sessionStatus"],
                methods: [
                    "performAction": MockMethodConfig(responses: [
                        .success(
                            .dictionary(["status": .int(actionStatus)]),
                            updateSharedState: ["sessionStatus": .int(actionStatus)]
                        )
                    ]),
                    "verifyIdentity": .singleSuccess(
                        .dictionary(["status": .int(5)])
                    ),
                    "canVerifyIdentity": .singleSuccess(.bool(true)),
                    "finalizeSession": MockMethodConfig(responses: [
                        .success(
                            .dictionary(["status": .int(finalStatus)]),
                            updateSharedState: ["sessionStatus": .int(finalStatus)]
                        )
                    ]),
                    "resetProfiler": .voidSuccess,
                    "signOut": .voidSuccess
                ]
            )

        case .actionFails(let code, let message):
            return MockServiceEntry(
                bindings: ["sessionStatus": "sessionStatus"],
                methods: [
                    "performAction": .singleError(code: code, message: message),
                    "resetProfiler": .voidSuccess,
                    "signOut": .voidSuccess
                ]
            )

        case .failThenRetry(let errorCode, let retryStatus):
            return MockServiceEntry(
                bindings: ["sessionStatus": "sessionStatus"],
                methods: [
                    "performAction": MockMethodConfig(responses: [
                        .error(code: errorCode, message: "Connection timed out"),
                        .success(
                            .dictionary(["status": .int(retryStatus)]),
                            updateSharedState: ["sessionStatus": .int(retryStatus)]
                        )
                    ]),
                    "verifyIdentity": .singleSuccess(
                        .dictionary(["status": .int(5)])
                    ),
                    "canVerifyIdentity": .singleSuccess(.bool(true)),
                    "finalizeSession": .singleSuccess(
                        .dictionary(["status": .int(7)]),
                        updateSharedState: ["sessionStatus": .int(7)]
                    ),
                    "resetProfiler": .voidSuccess,
                    "signOut": .voidSuccess
                ]
            )

        case .elevatedAccessRequired(let initialStatus, let elevatedStatus, let finalStatus):
            return MockServiceEntry(
                bindings: ["sessionStatus": "sessionStatus"],
                methods: [
                    "performAction": MockMethodConfig(responses: [
                        .success(
                            .dictionary(["status": .int(initialStatus)]),
                            updateSharedState: ["sessionStatus": .int(initialStatus)]
                        )
                    ]),
                    "elevateAccess": MockMethodConfig(responses: [
                        .success(
                            .dictionary(["status": .int(elevatedStatus)]),
                            updateSharedState: ["sessionStatus": .int(elevatedStatus)]
                        )
                    ]),
                    "verifyIdentity": .singleSuccess(
                        .dictionary(["status": .int(5)])
                    ),
                    "canVerifyIdentity": .singleSuccess(.bool(true)),
                    "finalizeSession": MockMethodConfig(responses: [
                        .success(
                            .dictionary(["status": .int(finalStatus)]),
                            updateSharedState: ["sessionStatus": .int(finalStatus)]
                        )
                    ]),
                    "resetProfiler": .voidSuccess,
                    "signOut": .voidSuccess
                ]
            )

        case .alreadyEstablished:
            return MockServiceEntry(
                bindings: ["sessionStatus": "sessionStatus"],
                methods: [
                    "canVerifyIdentity": .singleSuccess(.bool(true)),
                    "resetProfiler": .voidSuccess,
                    "signOut": .voidSuccess
                ]
            )

        case .custom(_, let entry):
            return entry
        }
    }
}
```

### Example: SecondaryServiceProtocol

Stub out one preset enum per additional service in ServiceContainer.

```swift
enum SecondaryPreset: MockServicePreset {
    static let serviceName = "SecondaryServiceProtocol"

    case enabled
    case disabled
    case verificationFails(code: String = "verificationFailed")
    case custom(sharedState: [String: SharedStateProperty], entry: MockServiceEntry)

    var sharedState: [String: SharedStateProperty] {
        switch self {
        case .custom(let state, _): return state
        default: return [:]  // No shared state needed, or add if service requires it
        }
    }

    var serviceEntry: MockServiceEntry {
        switch self {
        case .enabled:
            return MockServiceEntry(methods: [
                "verify": .singleSuccess(.bool(true)),
                "enroll": .singleSuccess(.dictionary(["enrolled": .bool(true)])),
                "reset": .voidSuccess
            ])
        case .disabled:
            return MockServiceEntry(methods: [
                "verify": .singleSuccess(.bool(false)),
                "reset": .voidSuccess
            ])
        case .verificationFails(let code):
            return MockServiceEntry(methods: [
                "verify": .singleError(code: code, message: "Verification failed"),
                "reset": .voidSuccess
            ])
        case .custom(_, let entry):
            return entry
        }
    }
}
```

> Repeat for each service:
> `enum TertiaryPreset: MockServicePreset { ... }`
> `enum QuaternaryPreset: MockServicePreset { ... }`
> `enum QuinaryPreset: MockServicePreset { ... }`

---

## 3. MockScenario Builder

Composes multiple service presets into a single `MockServiceConfiguration`.

### Design Decisions
- **Typed `.with___()` methods per service** instead of a generic `.with(preset:)`.
  Sacrifices a tiny bit of DRY for dramatically better autocomplete.
  When someone types `.with`, they see exactly which services are available.
- **Value-type builder** using `self`-returning methods for immutable composition.
- **Method-level overrides** via `.overriding()` let you tweak a single method
  on an existing preset without replacing the entire thing.
- **Global modifiers** like `.withGlobalDelay()` apply cross-cutting concerns.

```swift
struct MockScenario {
    private var sharedState: [String: SharedStateProperty] = [:]
    private var services: [String: MockServiceEntry] = [:]
    private var methodOverrides: [String: [String: MockMethodConfig]] = [:]

    // MARK: - Factory

    /// Entry point. Returns an empty builder ready for composition.
    static func build() -> MockScenario {
        MockScenario()
    }

    // MARK: - Generic Preset Composition (private)

    /// Adds any `MockServicePreset` to the scenario, merging its shared state.
    /// Later additions win on shared state key conflicts (intentional — allows overrides).
    private func adding(_ preset: any MockServicePreset) -> MockScenario {
        var copy = self
        for (key, prop) in preset.sharedState {
            copy.sharedState[key] = prop
        }
        copy.services[type(of: preset).serviceName] = preset.serviceEntry
        return copy
    }

    // MARK: - Typed Service Methods
    //
    // One method per service. Default parameter = most common preset.
    // Xcode autocomplete shows: .withPrimary(.happyPath()), .withPrimary(.actionFails()), etc.

    func withPrimary(_ preset: PrimaryPreset = .happyPath()) -> MockScenario {
        adding(preset)
    }

    func withSecondary(_ preset: SecondaryPreset = .enabled) -> MockScenario {
        adding(preset)
    }

    // Add one per service:
    // func withTertiary(_ preset: TertiaryPreset = .default) -> MockScenario { adding(preset) }
    // func withQuaternary(_ preset: QuaternaryPreset = .default) -> MockScenario { adding(preset) }
    // func withQuinary(_ preset: QuinaryPreset = .default) -> MockScenario { adding(preset) }

    // MARK: - Method-Level Overrides

    /// Override a single method on an already-added service without replacing the entire preset.
    ///
    /// ```swift
    /// MockScenario.build()
    ///     .withPrimary(.happyPath())
    ///     .overriding(service: "PrimaryServiceProtocol",
    ///                 method: "performAction",
    ///                 with: .singleError(code: "locked", message: "Account locked"))
    ///     .apply(to: app)
    /// ```
    func overriding(
        service serviceName: String,
        method methodName: String,
        with config: MockMethodConfig
    ) -> MockScenario {
        var copy = self
        copy.methodOverrides[serviceName, default: [:]][methodName] = config
        return copy
    }

    /// Typed shorthand for overriding primary service methods.
    func overridingPrimary(method: String, with config: MockMethodConfig) -> MockScenario {
        overriding(service: PrimaryPreset.serviceName, method: method, with: config)
    }

    /// Typed shorthand for overriding secondary service methods.
    func overridingSecondary(method: String, with config: MockMethodConfig) -> MockScenario {
        overriding(service: SecondaryPreset.serviceName, method: method, with: config)
    }

    // MARK: - Global Modifiers

    /// Adds a simulated delay to every response across all services.
    /// Useful for testing loading spinners and skeleton states.
    ///
    /// Only applies delay to responses that don't already have one configured
    /// (preserves intentional per-response delays from presets).
    func withGlobalDelay(ms: Int) -> MockScenario {
        var copy = self
        for (serviceName, entry) in copy.services {
            var delayedMethods: [String: MockMethodConfig] = [:]
            for (methodName, methodConfig) in entry.methods {
                let delayedResponses = methodConfig.responses.map { response in
                    MockResponse(
                        result: response.result,
                        value: response.value,
                        error: response.error,
                        delayMs: response.delayMs ?? ms, // preserve existing delays
                        updateSharedState: response.updateSharedState
                    )
                }
                delayedMethods[methodName] = MockMethodConfig(
                    responses: delayedResponses,
                    exhaustBehavior: methodConfig.exhaustBehavior
                )
            }
            copy.services[serviceName] = MockServiceEntry(
                initialState: entry.initialState,
                bindings: entry.bindings,
                methods: delayedMethods
            )
        }
        return copy
    }

    // MARK: - Terminal Operations

    /// Builds the final `MockServiceConfiguration`, applying any method-level overrides.
    func configuration() -> MockServiceConfiguration {
        var finalServices = services

        // Merge method-level overrides into service entries
        for (serviceName, overrides) in methodOverrides {
            guard let existing = finalServices[serviceName] else { continue }
            var methods = existing.methods
            for (methodName, config) in overrides {
                methods[methodName] = config
            }
            finalServices[serviceName] = MockServiceEntry(
                initialState: existing.initialState,
                bindings: existing.bindings,
                methods: methods
            )
        }

        return MockServiceConfiguration(
            sharedState: sharedState.isEmpty ? nil : sharedState,
            services: finalServices
        )
    }

    /// Builds the configuration and injects it into the app's launch environment.
    /// Call **before** `app.launch()`.
    func apply(to app: XCUIApplication) {
        app.configureMockServices(configuration())
    }
}
```

---

## 4. Example Tests

```swift
// ── Simple: Primary service happy path ───────────────────────────────
func testSuccessfulFlow() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.happyPath())
        .apply(to: app)
    app.launch()
    // ... drive UI, assert success state
}

// ── Error: Primary action fails ──────────────────────────────────────
func testActionFailure() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.actionFails(code: "invalidInput"))
        .apply(to: app)
    app.launch()
    // ... assert error banner
}

// ── Retry: Fail then succeed ─────────────────────────────────────────
func testRetryAfterTimeout() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.failThenRetry())
        .apply(to: app)
    app.launch()
    // ... first attempt shows error, tap retry, assert success
}

// ── Multi-service: Primary + Secondary ───────────────────────────────
func testFullFlowWithSecondaryVerification() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.happyPath())
        .withSecondary(.enabled)
        .apply(to: app)
    app.launch()
    // ... complete primary flow, secondary verification succeeds
}

// ── Mid-flow entry: Already established session ──────────────────────
func testSettingsScreenWithActiveSession() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.alreadyEstablished())
        .apply(to: app)
    app.launch()
    // ... navigate to settings, assert session info visible
}

// ── Surgical override: Happy path but slow action ────────────────────
func testLoadingSpinnerDuringAction() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.happyPath())
        .overridingPrimary(method: "performAction", with: MockMethodConfig(responses: [
            .success(
                .dictionary(["status": .int(3)]),
                delayMs: 3000,
                updateSharedState: ["sessionStatus": .int(3)]
            )
        ]))
        .apply(to: app)
    app.launch()
    // ... assert loading spinner visible during 3s delay
}

// ── Global delay: All services respond slowly ────────────────────────
func testSkeletonStatesUnderLatency() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.happyPath())
        .withSecondary(.enabled)
        .withGlobalDelay(ms: 2000)
        .apply(to: app)
    app.launch()
    // ... assert skeleton/loading states across all screens
}

// ── Elevated access with secondary verification ──────────────────────
func testElevatedAccessWithSecondaryService() {
    let app = XCUIApplication()
    MockScenario.build()
        .withPrimary(.elevatedAccessRequired())
        .withSecondary(.enabled)
        .apply(to: app)
    app.launch()
    // ... primary action, prompted for elevation, secondary verifies, finalize
}
```

---

## 5. Implementation Checklist

### Step 1: Create MockServicePreset protocol
- File: `MockServicePreset.swift` (in UI test support target)
- Contains: protocol + nothing else

### Step 2: Create one preset enum per service in ServiceContainer
- File per service: `<ServiceName>Preset.swift`
- Services to cover (from `ServiceContainer.registerDependencies`):
  - `PrimaryServiceProtocol` → `PrimaryPreset`
  - `SecondaryServiceProtocol` → `SecondaryPreset`
  - `TertiaryServiceProtocol` → `TertiaryPreset`
  - `QuaternaryServiceProtocol` → `QuaternaryPreset`
  - `QuinaryServiceProtocol` → `QuinaryPreset`
- Each enum: 3-5 preset cases + `.custom` escape hatch
- Start with common scenarios only; add presets as tests demand them

### Step 3: Create MockScenario builder
- File: `MockScenario.swift` (in UI test support target)
- Contains: `struct MockScenario` with typed `.with___()` per service
- Terminal: `.apply(to:)` and `.configuration()`

### Step 4: Migrate existing tests
- Replace raw `app.configureMockServices(sharedState:services:)` calls
  with `MockScenario.build().with___().apply(to: app)`
- One test file at a time; both patterns work simultaneously

### Step 5: Document presets
- Each preset case should have a one-line doc comment
- Consider a shared `XCTestCase` base class or `setUp()` that logs
  which scenario is being used for debugging failures

> **Note:** No changes to `MockServiceConfiguration`, `MockServiceBootstrap`,
> `MockCallSequencer`, `MockSharedState`, or any mock service actors.
> This layer sits entirely in the UI test target.
