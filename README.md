# aza UI

The shared SwiftUI library for aza's apps (Heavier, Stream, Timeline), and how those apps are built.

## What's in it

**AzaUI**

| | |
|---|---|
| `.aza(AzaApp(...))` | Put on the window's root view. Applies the chosen colour and theme, provides the aza account, and covers the app with the sign-in screen on first launch. |
| `SignInScreen` | Full screen on first launch: the app's icon and name, **Sign in with aza**, **Skip**. Shown once; skipping is remembered. |
| `ProfileButton` | Top right of the main screen. Your aza picture in a glass ring when signed in, the glass person button in the app's colour when not. Opens Profile. |
| `ProfilePage { … }` | The page behind the profile button: your aza account row at the top, the app's own sections, then Appearance. |
| `AccountRow`, `AppearanceSection` | The two shared parts of Profile, for apps that lay Profile out themselves. |
| `AzaAccount`, `AzaProfile` | Who's signed in: name, picture and handle (protocol section 6). |
| `Appearance`, `Accent` | System, light or dark, and the app's colour, stored under the `appearance` and `accent` keys. `Accent.standard` is black in light mode and white in dark. |
| `Backdrop` | The system background with a soft glow of the app's colour from the top. |
| `PrimaryButton`, `GlassButton`, `CircleButton` | Full-width action in the app's colour, full-width glass, round glass with a symbol. |
| `Card`, `Heading`, `FormRow`, `Token` | Glass cards of rows, the section title above one, label-and-control rows, and a tappable value in the app's colour. |
| `.toast($message)`, `.pressable`, `AzaMark` | A glass message that clears itself, a button style that dips when pressed, and the aza logo. |
| `\.accent`, `\.onAccent` | The app's colour and the colour that reads on it, from the environment. |

**AzaUITesting**, for UI test targets: `poll`, `wait`, and `launchPastSignIn(signedIn:)`.

Signing in is a stand-in until the aza app exists: it signs in as a sample profile. The real flow asks the aza app for a `sign-in` certificate ([protocol](https://github.com/plarza/protocol) section 7).

## Use it

In `project.yml`:

```yaml
packages:
  AzaUI:
    url: https://github.com/plarza/ui
    from: 0.1.0
targets:
  MyApp:
    dependencies:
      - package: AzaUI
  MyAppTests:
    dependencies:
      - package: AzaUI
        product: AzaUITesting
```

```swift
import AzaUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView().aza(AzaApp(name: "My App", accent: "0A84FF"))
        }
    }
}

struct RootView: View {
    @State private var profile = false

    var body: some View {
        Main()
            .overlay(alignment: .topTrailing) { ProfileButton { profile = true }.padding(.trailing, 16) }
            .sheet(isPresented: $profile) {
                ProfilePage {
                    Heading("Units")
                    Card { FormRow("Distance", last: true) { … } }
                }
            }
    }
}
```

The sign-in screen shows the image set named `Icon` in the app's asset catalog (a copy of the app icon), unless `AzaApp(icon:)` names another.

## How aza iOS apps are built

The best of Heavier, Stream and Timeline, written down so every app does it the same way.

### Platform

- iOS 26 and up, iPhone, portrait. Liquid Glass APIs only, with no fallbacks for older systems.
- `UIRequiresFullScreen: true` with portrait only. It's deprecated in iOS 26, but App Store Connect still rejects a portrait-only upload without it.
- `CADisableMinimumFrameDurationOnPhone: true`, or iPhone caps the app's animations at 60 Hz.
- `ITSAppUsesNonExemptEncryption: false`, so TestFlight doesn't ask on every upload.
- Bundle ID `network.aza.<app>`, URL scheme `network-aza-<app>`, team `H5A6B4L9W8`.

### Project

- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `project.yml` is the project, and the generated `.xcodeproj` is ignored by git. Info.plist keys live in `project.yml` under `info.properties`, each with a comment when the reason isn't obvious.
- Folders by what they hold: `App/` (entry point, `AppModel`), `Model/`, `UI/`, then one folder per subsystem (`Recording/`, `Places/`). `Shared/` holds what the app and its extensions both compile.
- Usage descriptions are one plain sentence that says what the permission is for: "Timeline keeps recording your day while the app is closed. Everything stays on this iPhone."
- A `PrivacyInfo.xcprivacy` declaring the required-reason APIs the app uses.

### Swift

- Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY: YES`. Everything is on the main actor unless it says otherwise; heavy work is moved off explicitly (`nonisolated`, `@concurrent`, a `Task.detached` that returns a `Sendable` value).
- `@Observable` models passed with `.environment`, read with `@Environment(Model.self)`. No `ObservableObject`, `@Published` or Combine.
- One `AppModel` per app that owns the app's state and services. Views hold only view state (`@State`).
- Store data in whatever fits it:
  - SwiftData for records you edit (Heavier's sessions and sets).
  - Plain files for high-rate append-only data (Timeline's raw location fixes, one file per day, rebuilt into visits and trips on read).
  - A Rust core over UniFFI when the work is heavy or shared with the Mac (Stream's audio, Spotify, library and sync).
- `@AppStorage` for preferences. `appearance` and `accent` are shared keys, written only by AzaUI.
- Secrets go in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never in `UserDefaults`.
- When iOS can relaunch the app in the background (location, audio), build the model in the app delegate's `didFinishLaunching`, not in a view: no scene connects on a background relaunch.
- `FormatStyle` (`.formatted(...)`) for dates and numbers. Use `String(format:)` only for fixed clock layouts like `4:05`.

### UI

- `.aza(...)` at the root, `ProfileButton` top right of the main screen, `ProfilePage` behind it. Every app has the same sign-in, profile and appearance.
- Never hard-code `.blue` or another colour for the app's own colour: use `.tint` or `\.accent`. Use `\.onAccent` for anything drawn on it.
- `Backdrop()` behind full-screen pages and sheets.
- Liquid Glass for controls that float over content: `.glassEffect(.regular.interactive(), in: .circle)`, `.buttonStyle(.glass)` and `.glassProminent`. Put glass that morphs together in a `GlassEffectContainer` with `glassEffectID` (Timeline's calendar grows out of its button).
- System structure wherever it fits: `TabView` with `Tab` and `Tab(role: .search)`, `.tabViewBottomAccessory` for a playing bar, `.toolbar` items, `Button(role: .close)`, `.searchable`, `ContentUnavailableView` for empty states, `.confirmationDialog` before anything destructive.
- `.fullScreenCover` for a task you finish (a workout, Now Playing), sheets for everything you dip into, and `.presentationDetents` when the sheet is the main surface over a map.
- Measure with `.onGeometryChange`, not `GeometryReader`.
- A plain `ScrollView` + `VStack` instead of `List` when rows change height with animation: `List` animates row heights on its own clock.

### Motion and feedback

- Springs with a duration and a little bounce: `.spring(duration: 0.4, bounce: 0.2)`, `.smooth`, `.snappy`. Give each a value to animate on.
- `.contentTransition(.numericText())` on numbers that change, `.contentTransition(.symbolEffect(.replace))` on symbols that swap, and `.blurReplace` for views that come and go.
- `matchedGeometryEffect` for a selection that moves (the week strip, the colour ring), and `.navigationTransition(.zoom)` from a playing bar into its full screen.
- To expand a card, keep its content laid out and reveal it by height (`frame(height: open ? nil : 0)`, `.clipped()`), so opening animates as smoothly as closing.
- Haptics with `.sensoryFeedback(_, trigger:)` tied to the state that changed, not `UIImpactFeedbackGenerator`.
- `.monospacedDigit()` on every number that updates in place.

### Accessibility

- Every icon-only button has an `accessibilityLabel`, and every element a test touches has an `accessibilityIdentifier`.
- Selected states get `.isSelected`, section titles `.isHeader`.
- Custom gestures have an accessible equivalent, such as `accessibilityAdjustableAction` for drag-to-reorder.

### Privacy

- Offline first. The app works fully without an account or the network, and nothing leaves the device unless you ask. aza sign-in is always optional.

### Tests

- End-to-end XCUITests on the Simulator, never unit tests of pieces. Tests drive the app the way you would and never touch the Mac's mouse or keyboard.
- One launch per run: a DEBUG-only `network-aza-<app>://reset` deep link closes everything and goes back to the first screen between tests.
- Poll every 0.1 s (`AzaUITesting.poll`/`wait`). XCTest's own waits check about once a second.
- Tests find their data instead of assuming it, such as a training day in whatever plan the Simulator has.
- `launchPastSignIn(signedIn:)` skips the sign-in screen. Test the sign-in screen itself in one test.
- Mock data and launch-state variables open the app in any state for screenshots (`SIMCTL_CHILD_<APP>_MOCK=1`, `<APP>_SHEET=profile`).

### Scripts

Every app has the same scripts, so you never have to look up how to ship one:

| Script | Does |
|---|---|
| `scripts/deploy.sh` | Build Release, install and launch on the iPhone (`DEVICE=` to pick another). |
| `scripts/testflight.sh [build]` | Archive and upload to TestFlight with the App Store Connect API key. The build number is a timestamp unless given. |
| `scripts/test.sh [xcodebuild args]` | UI tests on the Simulator. Builds only when a source file changed since the last build. |
| `scripts/screenshots.sh` | Refresh the README screenshots from mock data. |

### README

Each app's README follows the same shape: the icon and name, four screenshots, **Features** (what you can do, one line each), **How it works** (the architecture in a paragraph, naming the system frameworks that do the work), and **Develop** (a table of tasks and commands).

## Develop

Needs Xcode 26.

| Task | Command |
|---|---|
| Build for iPhone and Mac | `scripts/build.sh` |
| Release a version | `git tag 0.x.y && git push --tags` |
