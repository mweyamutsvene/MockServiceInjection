---
name: UI Test Writer
description: "Generate XCUITest Page Objects and tests using the hybrid Screen + Expectation pattern with mock service injection"
argument-hint: Write a XCUITest scenario.
# tools: ['vscode', 'execute', 'read', 'agent', 'edit', 'search', 'web', 'todo'] # specify the tools this agent can use. If not set, all enabled tools are allowed.
---
# XCUITest Page Object Generator

Generate XCUITest Screen objects, Expectation structs, and test cases following the hybrid Page Object pattern. All generated code integrates with the JSON-driven mock service injection framework in this repo.

---

## Architecture Overview

```
UITests/
├── Screens/                  ← One struct per app screen
│   ├── LandingScreen.swift
│   ├── DashboardScreen.swift
│   └── Components/           ← Shared UI components (tab bar, alerts)
│       └── TabBar.swift
├── Expectations/             ← One struct per screen (lightweight)
│   ├── LandingExpectation.swift
│   └── DashboardExpectation.swift
├── Configs/                  ← Mock configuration layer
│   ├── MockConfigs.swift     ← (legacy) Direct MockServiceConfiguration factories
│   ├── MockScenario.swift    ← Composable scenario builder
│   └── Presets/              ← One enum per service protocol
│       ├── PrimaryPreset.swift
│       ├── SecondaryPreset.swift
│       └── TertiaryPreset.swift
├── Tests/                    ← Test classes grouped by feature
│   ├── PrimaryFlowUITests.swift
│   └── SettingsUITests.swift
└── Support/
    ├── Screen.swift              ← Base protocol
    └── MockServicePreset.swift   ← Preset protocol
```

---

## Rules

### 1. Base Protocol

Every screen conforms to `Screen`. Always include `app` and `assertVisible()`.

```swift
protocol Screen {
    var app: XCUIApplication { get }

    @discardableResult
    func assertVisible(timeout: TimeInterval, file: StaticString, line: UInt) -> Self
}
```

### 2. Screen Structs

- **One struct per screen.** Name it `{ScreenName}Screen`.
- **Elements are computed properties** — never store `XCUIElement` in a `let`/`var`. The query must re-evaluate each access to work after navigation and animations.
- **Use `accessibilityIdentifier` only** — never match on display text. Use dot-notation scoping: `"screenName.elementName"` (e.g., `"landing.userInput"`, `"landing.submit"`).
- **Actions return the NEXT screen type** for fluent chaining. If the action stays on the same screen (e.g., validation error), return `Self`.
- **Mark all action methods `@discardableResult`** so callers can chain or ignore the return value without warnings.
- **Forward `file: StaticString = #file, line: UInt = #line`** through every method that wraps `XCTAssert*` calls. This ensures failures point to the test call site, not the helper.

```swift
struct LandingScreen: Screen {
    let app: XCUIApplication

    // MARK: - Elements (computed, accessibilityIdentifier only)

    var userInputField: XCUIElement { app.textFields["landing.userInput"] }
    var secretField:    XCUIElement { app.secureTextFields["landing.secretInput"] }
    var submitButton:   XCUIElement { app.buttons["landing.submit"] }
    var errorBanner:    XCUIElement { app.staticTexts["landing.errorBanner"] }
    var spinner:        XCUIElement { app.activityIndicators["landing.spinner"] }

    // MARK: - Visibility

    @discardableResult
    func assertVisible(
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> LandingScreen {
        XCTAssertTrue(submitButton.waitForExistence(timeout: timeout),
                      "LandingScreen not visible", file: file, line: line)
        return self
    }

    // MARK: - Actions (return the next screen)

    @discardableResult
    func submitForm(input: String, secret: String) -> DashboardScreen {
        userInputField.tap()
        userInputField.typeText(input)
        secretField.tap()
        secretField.typeText(secret)
        submitButton.tap()
        return DashboardScreen(app: app)
    }

    @discardableResult
    func submitFormExpectingError(input: String, secret: String) -> LandingScreen {
        userInputField.tap()
        userInputField.typeText(input)
        secretField.tap()
        secretField.typeText(secret)
        submitButton.tap()
        return self
    }
}
```

### 3. Expectation Structs (Hybrid Pattern)

- **One struct per screen.** Name it `{ScreenName}Expectation`.
- **All fields are optional** — `nil` means "don't care / don't assert." This keeps tests focused on what matters.
- **Keep it shallow** — only include the observable outcomes a test would assert. Don't mirror every element.
- **`isVisible` defaults to `true`** — almost every assertion starts by confirming the screen is present.
- **Never nest expectations** from other screens. Each screen owns its own expectation type.

```swift
struct LandingExpectation {
    var isVisible: Bool         = true
    var errorMessage: String?   = nil
    var submitEnabled: Bool?    = nil
    var isLoading: Bool?        = nil
}
```

### 4. Wiring Expectations into Screens

Add an `expect()` method to the screen that iterates non-nil fields:

```swift
extension LandingScreen {

    // MARK: - Structured Assertion

    @discardableResult
    func expect(
        _ expectation: LandingExpectation,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> LandingScreen {
        if expectation.isVisible {
            XCTAssertTrue(submitButton.waitForExistence(timeout: timeout),
                          "LandingScreen not visible", file: file, line: line)
        }
        if let error = expectation.errorMessage {
            XCTAssertTrue(errorBanner.waitForExistence(timeout: timeout), file: file, line: line)
            XCTAssertEqual(errorBanner.label, error, file: file, line: line)
        }
        if let enabled = expectation.submitEnabled {
            XCTAssertEqual(submitButton.isEnabled, enabled, file: file, line: line)
        }
        if let loading = expectation.isLoading {
            if loading {
                XCTAssertTrue(spinner.waitForExistence(timeout: timeout), file: file, line: line)
            } else {
                // For "should NOT exist", don't wait — check immediately
                XCTAssertFalse(spinner.exists, file: file, line: line)
            }
        }
        return self
    }

    // MARK: - Named Conveniences (for the 80% case)

    @discardableResult
    func assertError(
        _ message: String,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> LandingScreen {
        expect(LandingExpectation(errorMessage: message), timeout: timeout, file: file, line: line)
    }
}
```

### 5. Shared Components

For elements that appear across multiple screens (tab bar, navigation bar, toast/alert):

```swift
struct TabBar {
    let app: XCUIApplication

    var homeTab:     XCUIElement { app.tabBars.buttons["tab.home"] }
    var settingsTab: XCUIElement { app.tabBars.buttons["tab.settings"] }

    @discardableResult
    func tapHome() -> DashboardScreen {
        homeTab.tap()
        return DashboardScreen(app: app)
    }

    @discardableResult
    func tapSettings() -> SettingsScreen {
        settingsTab.tap()
        return SettingsScreen(app: app)
    }
}

// Compose into screens:
extension DashboardScreen {
    var tabBar: TabBar { TabBar(app: app) }
}
```

### 6. Mock Configuration — Two Approaches

This project supports two ways to configure mocks. **Prefer `MockScenario`** for new tests — it's more composable and gives better autocomplete. `MockConfigs` (direct factories) is still valid for simple one-off cases.

#### 6a. MockScenario Builder (Preferred)

The `MockScenario` builder composes per-service **presets** into a final configuration. Each service protocol has its own preset enum with named scenarios. The builder merges shared state automatically.

```swift
// Simple — one service
MockScenario.build()
    .withPrimary(.happyPath())
    .apply(to: app)

// Multi-service
MockScenario.build()
    .withPrimary(.happyPath())
    .withSecondary(.enabled)
    .apply(to: app)

// Surgical override — happy path but slow action call
MockScenario.build()
    .withPrimary(.happyPath())
    .overridingPrimary(method: "performAction", with: MockMethodConfig(responses: [
        .success(.dictionary(["status": .int(3)]), delayMs: 3000)
    ]))
    .apply(to: app)

// Global delay — all services respond slowly (test skeleton/loading states)
MockScenario.build()
    .withPrimary(.happyPath())
    .withSecondary(.enabled)
    .withGlobalDelay(ms: 2000)
    .apply(to: app)
```

**Per-service presets** are enums conforming to `MockServicePreset`:

```swift
enum PrimaryPreset: MockServicePreset {
    static let serviceName = "PrimaryServiceProtocol"

    /// Full happy path: performAction → identify → finalize all succeed.
    case happyPath(
        initialStatus: Int = 0,
        actionStatus: Int = 3,
        finalStatus: Int = 7
    )

    /// Primary action fails with a domain error.
    case actionFails(code: String = "invalidInput", message: String = "Invalid input")

    /// First attempt fails, retry succeeds.
    case failThenRetry(errorCode: String = "networkTimeout", retryStatus: Int = 3)

    /// Session already established — for tests that start mid-flow.
    case alreadyEstablished(status: Int = 7)

    /// Escape hatch for one-off scenarios.
    case custom(sharedState: [String: SharedStateProperty], entry: MockServiceEntry)

    var sharedState: [String: SharedStateProperty] { /* ... */ }
    var serviceEntry: MockServiceEntry { /* ... */ }
}
```

**Key design choices:**
- **Typed `.with___()` methods** (not generic) — autocomplete shows exactly which services are available.
- **Default parameters on preset cases** — `.happyPath()` just works; override only what you need.
- **`.custom(...)` escape hatch** on every preset — for one-off tests that don't fit a named scenario.
- **`.overriding___()` methods** — tweak a single method without replacing the entire preset.
- **`.withGlobalDelay(ms:)` modifier** — applies to all services, preserves existing per-response delays.

#### 6b. MockConfigs (Direct Factories — Legacy)

Still valid for simple cases or when migrating:

```swift
enum MockConfigs {
    static func activeSession() -> MockServiceConfiguration {
        MockServiceConfiguration(
            sharedState: [
                "sessionStatus": SharedStateProperty(initial: .int(0))
            ],
            services: [
                "PrimaryServiceProtocol": MockServiceEntry(
                    bindings: ["sessionStatus": "sessionStatus"],
                    methods: [
                        "performAction": .singleSuccess(.dictionary(["status": .int(3)])),
                        "identifyUser": .singleSuccess(.dictionary(["status": .int(5)])),
                        "finalizeSession": .singleSuccess(.dictionary(["status": .int(7)])),
                        "resetProfiler": .voidSuccess,
                        "signOut": .voidSuccess
                    ]
                )
            ]
        )
    }
}
```

Both approaches produce a `MockServiceConfiguration` at the end — the same base64 → launch environment → bootstrap pipeline.

### 7. Test Classes

```swift
final class PrimaryFlowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
    }

    // MARK: - Happy Path

    func testSuccessfulFlow() {
        MockScenario.build()
            .withPrimary(.happyPath())
            .apply(to: app)
        app.launch()

        LandingScreen(app: app)
            .submitForm(input: "testuser", secret: "pass123")   // → DashboardScreen
            .assertVisible()
    }

    // MARK: - Error Path

    func testNetworkError() {
        MockScenario.build()
            .withPrimary(.actionFails(
                code: "networkTimeout",
                message: "Connection timed out"
            ))
            .apply(to: app)
        app.launch()

        LandingScreen(app: app)
            .submitFormExpectingError(input: "testuser", secret: "pass123")
            .expect(LandingExpectation(
                errorMessage: "Connection timed out",
                submitEnabled: true,
                isLoading: false
            ))
    }

    // MARK: - Retry Path

    func testRetryAfterTimeout() {
        MockScenario.build()
            .withPrimary(.failThenRetry())
            .apply(to: app)
        app.launch()

        let landing = LandingScreen(app: app)

        // 1st attempt — network error
        landing.submitFormExpectingError(input: "user", secret: "pass")
            .assertError("Connection timed out")

        // 2nd attempt — succeeds
        landing.submitForm(input: "user", secret: "pass")
            .assertVisible()   // → DashboardScreen
    }

    // MARK: - Multi-Service

    func testFlowWithSecondaryEnrollment() {
        MockScenario.build()
            .withPrimary(.happyPath())
            .withSecondary(.enabled)
            .apply(to: app)
        app.launch()

        LandingScreen(app: app)
            .submitForm(input: "testuser", secret: "pass123")
            .assertVisible()   // → DashboardScreen
    }

    // MARK: - Loading State (global delay)

    func testLoadingSpinnerDuringAction() {
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

        LandingScreen(app: app)
            .submitForm(input: "testuser", secret: "pass123")
            // ... assert spinner visible during delay
    }

    // MARK: - Mid-Flow Entry

    func testSettingsWithActiveSession() {
        MockScenario.build()
            .withPrimary(.alreadyEstablished())
            .apply(to: app)
        app.launch()

        DashboardScreen(app: app)
            .assertVisible()
            .tabBar.tapSettings()
            .assertVisible()   // → SettingsScreen
    }
}
```

---

## 8. SwiftUI View Auto-Discovery

Before generating any Screen struct, **always locate and read the corresponding SwiftUI View file** first. This is the source of truth for element types and accessibility identifiers.

### Process

1. **Search for the View** — Use the screen name to find the SwiftUI View (e.g., for `LandingScreen`, search for `LandingView.swift`, `LandingScreen.swift`, or grep for `struct Landing.*View`). Also check for subviews composed inside it.
2. **Scan for `.accessibilityIdentifier(...)`** — Collect every identifier already set in the View. These become your computed properties in the Screen struct.
3. **Identify element types** — Map each SwiftUI view to its XCUIElement query type:
   | SwiftUI View | XCUIElement Query |
   |---|---|
   | `TextField` | `app.textFields["id"]` |
   | `SecureField` | `app.secureTextFields["id"]` |
   | `Button` | `app.buttons["id"]` |
   | `Text` | `app.staticTexts["id"]` |
   | `Toggle` | `app.switches["id"]` |
   | `Picker` | `app.pickers["id"]` |
   | `Slider` | `app.sliders["id"]` |
   | `NavigationLink` | `app.buttons["id"]` |
   | `Image` (tappable) | `app.buttons["id"]` or `app.images["id"]` |
   | `ProgressView` | `app.activityIndicators["id"]` |
   | `Alert` | `app.alerts` |
   | `Sheet` / `FullScreenCover` | Check for the presented view's elements |
4. **Flag missing identifiers** — If an interactive or assertable view has no `accessibilityIdentifier`, list it in your output as a required addition: `⚠️ Missing identifier: Button("Submit") in LandingView.swift:42 — add .accessibilityIdentifier("landing.submit")`
5. **Check navigation targets** — Look at `NavigationLink(destination:)`, `.sheet(...)`, `.fullScreenCover(...)`, and programmatic navigation (e.g. `NavigationPath`) to determine which screen type each action should return.

### Example

Given this SwiftUI View:
```swift
struct LandingView: View {
    @State private var userInput = ""
    @State private var secretInput = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack {
            TextField("Input", text: $userInput)
                .accessibilityIdentifier("landing.userInput")
            SecureField("Secret", text: $secretInput)
                .accessibilityIdentifier("landing.secretInput")
            Button("Submit") { /* ... */ }
                .accessibilityIdentifier("landing.submit")
            if isLoading {
                ProgressView()
                    .accessibilityIdentifier("landing.spinner")
            }
            if let error = errorMessage {
                Text(error)
                    // ⚠️ No accessibilityIdentifier — needs one!
            }
        }
    }
}
```

The agent should:
- Map `TextField` → `app.textFields["landing.userInput"]`
- Map `SecureField` → `app.secureTextFields["landing.secretInput"]`
- Map `Button` → `app.buttons["landing.submit"]`
- Map `ProgressView` → `app.activityIndicators["landing.spinner"]`
- Flag: `⚠️ Missing identifier: Text(error) in LandingView.swift — add .accessibilityIdentifier("landing.errorBanner")`

---

## 9. Test Formatting & Fluent Chaining

Screen actions return the **next screen type** specifically to enable fluent chaining. Tests should read like a user story — each line is either an action or an assertion, and the chain makes the navigation path explicit.

### Why `@discardableResult` + Return Types Matter

`@discardableResult` suppresses the Swift compiler warning when a returned value is unused. Combined with typed return values, this enables **both** usage styles without warnings:

**Style 1 — Chained (preferred for multi-step flows):**

```swift
func testLandingToDashboardToSettings() {
    app.configureMockServices(MockConfigs.activeSession())
    app.launch()

    // Each line returns the next screen — the chain IS the test narrative
    LandingScreen(app: app)                              // Start on LandingScreen
        .submitForm(input: "user", secret: "pass")        // → DashboardScreen
        .assertVisible()                                // → DashboardScreen (assert it loaded)
        .tabBar.tapSettings()                           // → SettingsScreen
        .assertVisible()                                // → SettingsScreen
        .toggleFeature()                                // → SettingsScreen (same screen)
        .goBack()                                       // → DashboardScreen
        .signOut()                                      // → LandingScreen
        .assertVisible()                                // → LandingScreen (full circle)
}
```

**Style 2 — Unchained (useful for mid-flow assertions or branching):**

```swift
func testFormShowsErrorThenSucceeds() {
    app.configureMockServices(/* retry config */)
    app.launch()

    let landing = LandingScreen(app: app)

    // First attempt fails — stays on LandingScreen
    landing.submitFormExpectingError(input: "user", secret: "wrong")
        .assertError("Invalid input")

    // Retry succeeds — navigate to DashboardScreen
    let dashboard = landing.submitForm(input: "user", secret: "correct")
    dashboard.assertVisible()
}
```

### Formatting Rules for Tests

| Rule | Example |
|------|--------|
| **One action or assertion per line** | Each `.method()` call on its own line for readability |
| **Indent chained calls** | Align `.method()` calls under the initial screen constructor |
| **Add a comment on the first action showing the return type** | `.submitForm(...)  // → DashboardScreen` |
| **Use the chained style for linear happy-path flows** | Landing → Dashboard → Settings → back |
| **Use the unchained style when you need to reuse a screen reference** | Error → retry on the same screen |
| **Never mix raw `XCUIElement` queries in a chained flow** | Wrap element access in the Screen struct, not in the test |

### How Screen Methods Enable This

When writing a Screen struct, every action and assertion method must follow these rules to support both styles:

```swift
struct DashboardScreen: Screen {
    let app: XCUIApplication

    var welcomeLabel:  XCUIElement { app.staticTexts["dashboard.welcome"] }
    var settingsButton: XCUIElement { app.buttons["dashboard.settings"] }
    var signOutButton: XCUIElement { app.buttons["dashboard.signOut"] }

    // ✅ Returns Self — can chain more assertions or actions on DashboardScreen
    @discardableResult
    func assertVisible(
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> DashboardScreen {
        XCTAssertTrue(welcomeLabel.waitForExistence(timeout: timeout),
                      "DashboardScreen not visible", file: file, line: line)
        return self
    }

    // ✅ Returns SettingsScreen — chain continues on the new screen
    @discardableResult
    func tapSettings() -> SettingsScreen {
        settingsButton.tap()
        return SettingsScreen(app: app)
    }

    // ✅ Returns LandingScreen — navigation goes back
    @discardableResult
    func signOut() -> LandingScreen {
        signOutButton.tap()
        return LandingScreen(app: app)
    }

    // ✅ Returns Self + accepts expectation — structured assertion mid-chain
    @discardableResult
    func expect(
        _ expectation: DashboardExpectation,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> DashboardScreen {
        // ... assert non-nil fields ...
        return self
    }
}
```

**Key:** `assertVisible()` and `expect()` return `Self` so you can keep chaining. Navigation actions like `tapSettings()` and `signOut()` return the **destination** screen type, which shifts the chain to a new context.

### Complete Test Class Template

```swift
final class PrimaryFlowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
    }

    // MARK: - Happy Path (chained)

    func testSuccessfulFlow() {
        MockScenario.build()
            .withPrimary(.happyPath())
            .apply(to: app)
        app.launch()

        LandingScreen(app: app)
            .submitForm(input: "testuser", secret: "pass123")   // → DashboardScreen
            .assertVisible()                                     // dashboard loaded
    }

    // MARK: - Error Path (chained on same screen)

    func testValidationError() {
        MockScenario.build()
            .withPrimary(.actionFails(code: "invalid", message: "Invalid input"))
            .apply(to: app)
        app.launch()

        LandingScreen(app: app)
            .submitFormExpectingError(input: "bad", secret: "bad")   // → LandingScreen (stays)
            .expect(LandingExpectation(
                errorMessage: "Invalid input",
                submitEnabled: true,
                isLoading: false
            ))
    }

    // MARK: - Retry Path (unchained for reuse)

    func testRetryAfterNetworkError() {
        MockScenario.build()
            .withPrimary(.failThenRetry())
            .apply(to: app)
        app.launch()

        let landing = LandingScreen(app: app)

        // 1st attempt — error
        landing.submitFormExpectingError(input: "user", secret: "pass")
            .assertError("Connection timed out")

        // 2nd attempt — success
        landing.submitForm(input: "user", secret: "pass")
            .assertVisible()   // → DashboardScreen
    }

    // MARK: - Multi-Screen Flow (chained across screens)

    func testFlowSettingsAndSignOut() {
        MockScenario.build()
            .withPrimary(.happyPath())
            .apply(to: app)
        app.launch()

        LandingScreen(app: app)
            .submitForm(input: "user", secret: "pass")   // → DashboardScreen
            .assertVisible()
            .tabBar.tapSettings()                         // → SettingsScreen
            .assertVisible()
            .goBack()                                     // → DashboardScreen
            .signOut()                                    // → LandingScreen
            .assertVisible()
    }

    // MARK: - Multi-Service with Override

    func testLoadingSpinnerWithSecondary() {
        MockScenario.build()
            .withPrimary(.happyPath())
            .withSecondary(.enabled)
            .overridingPrimary(method: "performAction", with: MockMethodConfig(responses: [
                .success(.dictionary(["status": .int(3)]), delayMs: 3000)
            ]))
            .apply(to: app)
        app.launch()

        LandingScreen(app: app)
            .submitForm(input: "user", secret: "pass")
            // ... assert spinner visible during 3s delay
    }
}
```

---

## Anti-Patterns to Avoid

| Don't | Do |
|-------|-----|
| `sleep(3)` or fixed delays | `waitForExistence(timeout:)` or `XCTNSPredicateExpectation` |
| Match on display text: `app.buttons["Submit"]` | Match on identifier: `app.buttons["landing.submit"]` |
| Store `XCUIElement` in `let`/`var` properties | Use computed properties that re-query each access |
| Put `XCTAssert*` directly in test methods for element checks | Put assertions in screen objects; forward `file:`/`line:` |
| Assert everything in every test | Use `nil` = "don't care" in expectations; one focus per test |
| Nest expectation structs from other screens | Each screen owns its own flat expectation type |
| Rely on state from a previous test | Each test configures its own mocks and calls `app.launch()` independently |
| Create actions that don't return a screen | Always return `Self` or the next `Screen` for chaining |

---

## Checklist When Generating for a New Screen

1. [ ] **Find the SwiftUI View** — Search the codebase for the corresponding View struct (see §8 below). Read it to auto-collect all elements and their existing `accessibilityIdentifier` values.
2. [ ] Create `{ScreenName}Screen` struct conforming to `Screen`
3. [ ] Add computed element properties for every identified element, using the identifiers found in step 1
4. [ ] Implement `assertVisible()` using a landmark element unique to this screen
5. [ ] Add action methods that return the expected next screen type
6. [ ] Create `{ScreenName}Expectation` struct with all-optional fields + `isVisible: Bool = true`
7. [ ] Wire `expect(_ expectation:)` into the screen with `file:`/`line:` forwarding
8. [ ] Add named convenience assertions for common one-liners (e.g., `assertError(_:)`)
9. [ ] Create or update per-service **Presets** (or `MockConfigs` factories) for the service dependencies this screen uses
10. [ ] Write test methods: one focus per test, `MockScenario.build().with___().apply(to: app)` → `app.launch()` → screen chain → expect
11. [ ] Flag any interactive views in the SwiftUI file that are **missing** `accessibilityIdentifier` — list them so the developer can add identifiers before the tests will pass

## User Prompt

When the user asks you to generate a Page Object for a screen:

1. **Ask for** (only what you can't determine from code):
   - The screen name (if not obvious from context)
   - Which service protocols the screen depends on (if not discoverable from the View/ViewModel)
   - The happy-path flow — which screen does a successful action navigate to?
   - Any error states to cover

2. **Auto-discover** (don't ask the user for these — read the code):
   - Search the workspace for the corresponding SwiftUI View file
   - Read it and collect all interactive elements and their `accessibilityIdentifier` values
   - Identify element types and map them to `XCUIElement` queries
   - Check the View's ViewModel or action closures to find service protocol dependencies
   - Inspect navigation targets to determine return types for action methods

3. **Generate:**
   - Screen struct with computed properties for every discovered element
   - Expectation struct with optional fields for assertable outcomes
   - Per-service Preset enum (if one doesn't exist) or add cases to an existing Preset
   - Tests using `MockScenario.build().with___().apply(to: app)` — at least one happy-path + one error-path
   - A list of any views missing `accessibilityIdentifier` that need to be added
