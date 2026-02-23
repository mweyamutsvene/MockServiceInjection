````prompt
# JSON-Driven Mock Service Injection for XCUITest

**TL;DR:** XCUITest passes a base64-encoded JSON config via `launchEnvironment["MOCK_SERVICE_CONFIG"]`. On app launch, after normal service registration, `MockServiceBootstrap` reads the config, creates a shared `MockSharedState` object, constructs mock service actors (passing them both the config entry and shared state), and overwrites specific entries in `DependencyContainer` via the existing `register(_:for:)` API. Each mock method supports ordered response sequences with success/error simulation. Cross-service state updates are driven by `updateSharedState` on individual responses, with `bindings` mapping service properties to shared state keys. **No changes to `DependencyContainer.swift`.**

---

## JSON Schema Design

```json
{
  "sharedState": {
    "serviceStatus": { "initial": 0 }
  },
  "services": {
    "YourServiceProtocol": {
      "bindings": {
        "serviceStatus": "serviceStatus"
      },
      "methods": {
        "performAction": {
          "exhaustBehavior": "repeatLast",
          "responses": [
            {
              "result": "success",
              "value": { "status": 3 },
              "updateSharedState": { "serviceStatus": 3 }
            }
          ]
        },
        "fetchData": {
          "responses": [
            { "result": "success", "value": { "status": 5 } }
          ]
        },
        "checkEligibility": {
          "responses": [
            { "result": "success", "value": true }
          ]
        },
        "finalize": {
          "responses": [
            {
              "result": "success",
              "value": { "status": 7 },
              "updateSharedState": { "serviceStatus": 7 }
            }
          ]
        },
        "resetState": {
          "responses": [
            { "result": "success" }
          ]
        },
        "tearDown": {
          "responses": [
            { "result": "success" }
          ]
        }
      }
    },
    "SecondaryServiceProtocol": {
      "bindings": {
        "serviceStatus": "serviceStatus"
      },
      "methods": {
        "performAction": {
          "responses": [
            {
              "result": "success",
              "value": { "status": 3 },
              "updateSharedState": { "serviceStatus": 3 }
            }
          ]
        }
      }
    }
  }
}
```

### Key design choices

- **Per-method response arrays** — the Nth call returns the Nth element. Services are stateless request/response; the ViewModel orchestrates call order based on response content.
- **`sharedState` (top-level)** — declares shared observable properties with initial values. Each key becomes a `CurrentValueSubject<AnyCodableValue, Never>` in `MockSharedState`.
- **`bindings` (per-service)** — maps service property names to shared state keys. Services that bind to the same key share the same `CurrentValueSubject` instance, so updates from one service are visible to all others.
- **`updateSharedState` (per-response)** — a dictionary of shared state updates to apply after a response is returned. E.g., when secondary service succeeds, it pushes `serviceStatus: 3` to the shared state, and the primary service (which binds to the same key) sees the update.
- **Int-based status values** — `ServiceStatus` and similar enums use `Int` raw values (e.g., `0`, `3`, `5`, `7`), not strings.
- **`exhaustBehavior`** — controls what happens after all responses are consumed: `"repeatLast"` (default) re-uses the final response, `"fatalError"` crashes to catch unexpected extra calls.
- **`result: "error"`** entries include a `code` and `message`, mapped to `MockServiceError`.
- **`value` is opaque JSON** — each concrete mock knows how to decode its own return types.
- Methods with no return value (`resetState`, `tearDown`) can use `{ "result": "success" }` with no `value`, or be omitted entirely to default to no-op.
- **Optional `delayMs` on `MockResponse`** — if present, the sequencer calls `Task.sleep(nanoseconds:)` before returning. Enables testing loading states, spinners, and timeout logic.

---

## Architecture

### Data Flow

```
XCUITest
  └─ MockServiceConfiguration (JSON → base64 → launchEnvironment)
       └─ App launch
            └─ ServiceContainer.shared.registerDependencies(with: resolver)  [real services]
            └─ MockServiceBootstrap.configureIfNeeded()
                 ├─ MockServiceConfiguration.fromEnvironment()  [reads + decodes]
                 ├─ MockSharedState(properties: config.sharedState)  [one instance]
                 └─ For each service in config.services:
                      ├─ MockXxxService(configuration: entry, sharedState: sharedState)
                      └─ ServiceContainer.shared.register(mock, for: XxxProtocol.self)  [overwrites real]
```

### Cross-Service Shared State

```
MockSharedState
  ├─ "serviceStatus" → CurrentValueSubject<AnyCodableValue, Never>(initial: .int(0))
  │     ├─ MockYourService binds "serviceStatus" → reads/observes
  │     └─ MockSecondaryService binds "serviceStatus" → reads/observes
  │
  └─ (future keys...)

When secondary service response includes updateSharedState: { "serviceStatus": 3 }:
  → MockCallSequencer calls sharedState.applyUpdates(["serviceStatus": .int(3)])
  → Both primary service and secondary service see the updated value
```

---

## Implementation Files

### 1. `MockServiceConfiguration.swift` — generic JSON parsing layer

- `enum AnyCodableValue: Codable, Sendable, Equatable` — lightweight type-erased JSON value (string, int, double, bool, dictionary, array, null)
- `struct MockErrorPayload: Codable, Sendable` — `code: String`, `message: String`
- `enum ExhaustBehavior: String, Codable, Sendable` — `.repeatLast` | `.fatalError`
- `struct MockResponse: Codable, Sendable` — `result`, `value`, `error`, `delayMs`, `updateSharedState: [String: AnyCodableValue]?`
- `struct MockMethodConfig: Codable, Sendable` — `responses: [MockResponse]`, `exhaustBehavior`
- `struct SharedStateProperty: Codable, Sendable` — `initial: AnyCodableValue`
- `struct MockServiceEntry: Codable, Sendable` — `initialState`, `bindings: [String: String]?`, `methods`
- `struct MockServiceConfiguration: Codable, Sendable` — `sharedState: [String: SharedStateProperty]?`, `services`
- Static: `fromEnvironment()`, `toBase64()`

### 2. `MockSharedState.swift` — cross-service observable state

- `final class MockSharedState: @unchecked Sendable`
- Holds `[String: CurrentValueSubject<AnyCodableValue, Never>]` — one subject per shared state key
- `init(properties:)` — creates subjects from top-level config
- `subject(for:)` — returns the CVS for a key (used by mocks during init to wire up bindings)
- `applyUpdates(_:)` — sends new values to matching subjects (called by sequencer after response)

### 3. `MockCallSequencer.swift` — reusable actor for sequenced responses

- `actor MockCallSequencer` — stores `[String: MockMethodConfig]`, `[String: Int]` counters, and optional `MockSharedState`
- `init(methods:sharedState:)` and `init(entry:sharedState:)`
- `nextResponse(for:)` — returns the correct response for the Nth call
- `nextDecodedValue<T>(for:as:)` — decodes value, applies delay, throws on error, calls `sharedState?.applyUpdates()`
- `recordVoidCall(for:)` — for void methods, applies delay/error/shared state updates
- `callCount(for:)`, `resetCallCounts()` — diagnostics

### 4. `MockServiceError.swift` — error type

- `struct MockServiceError: Error, Sendable, CustomStringConvertible, LocalizedError`
- Carries `code` and `message` from JSON config

### 5. `MockServiceBootstrap.swift` — app launch integration

- `enum MockServiceBootstrap`
- `configureIfNeeded()` — reads config, creates `MockSharedState`, iterates services, dispatches to concrete mock constructors
- Service registration dispatch: maps protocol name strings to concrete mock types
- Logs which services were mocked

### 6. `XCUIApplication+MockConfig.swift` — test target helper

- `configureMockServices(_:)` — encodes config to base64, sets `launchEnvironment`
- `configureMockServices(sharedState:services:)` — convenience builder
- `MockResponse` convenience factories: `.success()`, `.error()`
- `MockMethodConfig` convenience factories: `.singleSuccess()`, `.singleError()`, `.voidSuccess`

---

## Concrete Flow Examples

### Standard Flow → Fetch Data → Finalize

ViewModel orchestrates this sequence:
1. `performAction(input:secret:)` → returns `ServiceResponse` with `status: 3`
2. `checkEligibility()` → returns `true`
3. `fetchData()` → returns `ServiceResponse` with `status: 5`
4. `finalize()` → returns `ServiceResponse` with `status: 7`

```json
{
  "sharedState": { "serviceStatus": { "initial": 0 } },
  "services": {
    "YourServiceProtocol": {
      "bindings": { "serviceStatus": "serviceStatus" },
      "methods": {
        "performAction": {
          "responses": [{
            "result": "success",
            "value": { "status": 3 },
            "updateSharedState": { "serviceStatus": 3 }
          }]
        },
        "checkEligibility": { "responses": [{ "result": "success", "value": true }] },
        "fetchData": { "responses": [{ "result": "success", "value": { "status": 5 } }] },
        "finalize": {
          "responses": [{
            "result": "success",
            "value": { "status": 7 },
            "updateSharedState": { "serviceStatus": 7 }
          }]
        },
        "resetState": { "responses": [{ "result": "success" }] },
        "tearDown": { "responses": [{ "result": "success" }] }
      }
    }
  }
}
```

### Secondary Service → Fetch Data → Finalize (Cross-Service)

Secondary service performs action, then the ViewModel uses the primary service for the rest:
1. Secondary: `performAction()` → success, **updates shared `serviceStatus` to 3**
2. Primary: `fetchData()` → success (primary service sees status=3 via shared state)
3. Primary: `finalize()` → success, **updates shared `serviceStatus` to 7**

Both services bind `serviceStatus` to the same shared state key.

### Standard → MFA → OTP

1. Primary: `performAction()` → returns response indicating MFA required
2. Primary: `elevate(desiredLevelOfAccess:flow:)` → returns response indicating OTP challenge
3. OTP: `verify(code:)` → success
4. Primary: `fetchData()` → success
5. Primary: `finalize()` → success

Each method returns the Nth response from its array. The ViewModel drives the flow based on response content.

---

## Swift Macros

### `@MockService` (member macro)
Generates:
- `private let sequencer: MockCallSequencer`
- `init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil)`:
  - Creates sequencer with shared state
  - For each `CurrentValueSubject` property: checks bindings → initialState → default (int-based raw values)

### `@MockMethod` (body macro)
Generates method body:
- Returning + throws: `try await sequencer.nextDecodedValue(for: "methodName", as: T.self)`
- Returning + non-throws: `try! await sequencer.nextDecodedValue(for: "methodName", as: T.self)`
- Void + throws: `try await sequencer.recordVoidCall(for: "methodName")`
- Void + non-throws: `try? await sequencer.recordVoidCall(for: "methodName")`

Custom key: `@MockMethod("customKey")`

---

## Analysis

### Strengths

1. **Zero-modification to production code.** Uses the existing `register(_:for:)` API exactly as intended.
2. **Actor-based sequencer is concurrent-safe.** Multiple ViewModels resolving the same mock simultaneously are safe by construction.
3. **Call-sequence-based responses match UI test reality.** UI tests drive deterministic flows; Nth-call-returns-Nth-response is a natural fit.
4. **Cross-service shared state without coupling.** Services don't reference each other; they share `CurrentValueSubject` instances through `MockSharedState`.
5. **`nonisolated let` for `CurrentValueSubject` is correct.** Assigned once in `init`, never reassigned. `CurrentValueSubject` is internally thread-safe.
6. **Int-based enums work naturally.** `AnyCodableValue.int(3)` → `ServiceStatus(rawValue: 3)`.

### Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Registration timing window | Medium | Ensure both calls are sequential before any UI renders |
| `CurrentValueSubject` not `Sendable` | Medium | `@preconcurrency import Combine`; long-term consider `AsyncStream` |
| All return types must be `Decodable` | Hard req | Network response models are already `Codable` |
| No input-conditional responses | Acceptable | UI tests drive one deterministic path. Future: add `match` field |
| Environment variable size ceiling | Low | Well under ~128KB limit for typical configs |

---

## Key Decisions

- **No modifications to `DependencyContainer.swift`** — mocks register after real services using existing API
- **Sequential arrays, not state machines** — services are stateless request/response; the ViewModel orchestrates based on response content
- **Shared state for cross-service coupling** — `MockSharedState` holds `CurrentValueSubject`s, `bindings` maps properties, `updateSharedState` drives side effects
- **Int-based status values** — `ServiceStatus` uses `Int` raw values, not strings
- **Base64 encoding** for environment variable transport
- **`actor` + `nonisolated let`** for strict Swift 6 compliance
- **`repeatLast` as default** exhaust behavior
- **Concrete mock per protocol** with shared `MockCallSequencer` actor

````
