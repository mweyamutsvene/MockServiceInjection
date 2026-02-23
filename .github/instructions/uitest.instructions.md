---
description: When writing UI tests using XCUITest, follow these conventions for a clean, maintainable test suite.
applyTo: 'UITests/*.swift' # when provided, instructions will automatically be added to the request context when the pattern matches an attached file
---
### Copilot Instructions — XCUITest Page Object Pattern

This project uses a **hybrid Page Object + Expectation pattern** for XCUITests, integrated with a JSON-driven mock service injection framework.

## Core Conventions

### Accessibility Identifiers
- Always use `accessibilityIdentifier`, never display text, for element queries.
- Use dot-notation scoping: `"screenName.elementName"` (e.g., `"landing.userInput"`, `"dashboard.signOut"`).

### Screen Objects
- One struct per screen, named `{ScreenName}Screen`, conforming to `Screen` protocol.
- Elements are **computed properties** — never store `XCUIElement` in `let`/`var`.
- Actions return the **next screen type** for fluent chaining. If the action stays on the same screen, return `Self`.
- Mark all action and assertion methods `@discardableResult`.

### SwiftUI View Auto-Discovery
- Before generating a Screen struct, **always find and read the corresponding SwiftUI View** first.
- Collect all `.accessibilityIdentifier(...)` values from the View to populate the Screen's computed properties.
- Map SwiftUI types to XCUIElement queries (e.g., `TextField` → `app.textFields`, `Button` → `app.buttons`, `Toggle` → `app.switches`).
- Flag any interactive or assertable views that are **missing** an `accessibilityIdentifier` so the developer can add them.

### Test Formatting & Fluent Chaining
- Tests should read like a user story: each line is one action or assertion.
- Use **chained style** for linear flows: `LandingScreen(app: app).submitForm(...).assertVisible().tabBar.tapSettings().assertVisible()`
- Use **unchained style** when you need a screen reference for retry/branching: `let landing = LandingScreen(app: app)` then call multiple actions on `landing`.
- Both styles work because all action/assertion methods are `@discardableResult` and return the appropriate screen type.
- **One action or assertion per line** — each `.method()` on its own line, indented under the initial constructor.
- **Never put raw `XCUIElement` queries in tests** — always go through the Screen struct.

### Expectation Structs
- One struct per screen, named `{ScreenName}Expectation`.
- All fields are **optional** (`nil` = don't assert). `isVisible: Bool = true` is the only non-optional default.
- Keep expectations shallow — don't nest other screens' expectations.

### Assertion Forwarding
- Every method that wraps `XCTAssert*` must accept and forward `file: StaticString = #file, line: UInt = #line` so failures point to the test call site.

### Timing
- Use `waitForExistence(timeout:)` or `XCTNSPredicateExpectation` — never `sleep()`.
- For "element should NOT exist" checks, assert immediately without waiting (`XCTAssertFalse(element.exists)`).

### Mock Integration
- **Prefer `MockScenario` builder** for configuring mocks: `MockScenario.build().withPrimary(.happyPath()).apply(to: app)`.
- Each service protocol has a **Preset enum** (e.g., `PrimaryPreset`, `SecondaryPreset`) with named scenarios (`.happyPath()`, `.actionFails()`, `.failThenRetry()`, `.custom(...)`).
- Use `.overriding___()` to tweak a single method on an existing preset without replacing the entire thing.
- Use `.withGlobalDelay(ms:)` to test loading/skeleton states across all services.
- Legacy `MockConfigs` factories and direct `app.configureMockServices(...)` are still valid but discouraged for new tests.
- Each test is fully independent: own mock config, own `app.launch()`, no shared state between tests.

### Test Structure
- `continueAfterFailure = false` in `setUpWithError()`.
- One assertion focus per test method.
- Capture screenshot in `tearDownWithError()` with `.deleteOnSuccess` lifetime.

## File Layout

```
UITests/
├── Screens/          ← {ScreenName}Screen.swift
├── Expectations/     ← {ScreenName}Expectation.swift
├── Components/       ← Shared UI (TabBar, AlertDialog)
├── Configs/          ← Mock configuration layer
│   ├── MockScenario.swift      ← Composable scenario builder
│   ├── MockConfigs.swift       ← (legacy) Direct factories
│   └── Presets/                ← One enum per service protocol
│       ├── PrimaryPreset.swift
│       └── SecondaryPreset.swift
├── Tests/            ← {Feature}UITests.swift
└── Support/
    ├── Screen.swift              ← Base protocol
    └── MockServicePreset.swift   ← Preset protocol
```
