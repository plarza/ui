# AzaUI

Shared SwiftUI for Heavier, Stream and Timeline: the parts that must look and behave the same in every app. Anything else, apps write with SwiftUI directly.

## Contents

| | |
|---|---|
| `.azaUI(name:icon:accent:appearance:showsSignIn:)` | On the window's root view. Applies the theme and colour, provides `Account.shared`, and shows the sign-in screen on first launch. |
| `ProfileButton` | Top right of the main screen. Your picture in a glass ring when signed in, a glass person button when not. |
| `AccountRow` | First row of the app's profile page. Opens the account page (picture, @handle, sign out), or signs in. |
| `AppearanceSection` | Theme (System, Light, Dark) and colour (presets plus a custom picker). |
| `Account`, `Profile` | Who's signed in: name, picture and handle (protocol section 6). |
| `Accent`, `Appearance`, `Color(hex:)` | The stored colour and theme (`accent`, `appearance` keys). `Accent.standard` is black in light mode and white in dark. |
| `\.accent`, `\.onAccent` | The app's colour and the colour that reads on it. |
| `UITestSupport` | `poll`, `wait`, `launchAtSignIn()` and `launchPastSignIn(signedIn:)` for UI tests. |

Signing in is a stand-in until the aza app exists: it signs in as `Profile.sample`, shown as “Sample account” with a grey picture and a Preview label. Profiles saved by earlier builds are replaced by it. The real flow asks the aza app for a `sign-in` certificate ([protocol](https://github.com/plarza/protocol), section 7).

## Use

```yaml
# project.yml
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
        product: UITestSupport
```

```swift
WindowGroup {
    RootView().azaUI(name: "Timeline", accent: "0A84FF")
}

// Main screen
.overlay(alignment: .topTrailing) { ProfileButton { showProfile = true } }

// Profile page
NavigationStack {
    ScrollView {
        AccountRow()
        // the app's own sections
        AppearanceSection()
    }
}
```

The sign-in screen shows the image set named `Icon` (a copy of the app icon) unless `icon:` names another.

| Identifier | Element |
|---|---|
| `signIn`, `skip` | Sign-in screen buttons |
| `profile` | Profile button |
| `account`, `signOut` | Account row, sign out on the account page |
| `theme`, `accent.<HEX>` | Appearance controls |

## Building an app

Only what isn't obvious. Each rule comes from one of the apps or from the iOS 27 SDK.

### Identity

| | |
|---|---|
| Bundle ID | `network.aza.<app>` |
| URL scheme | `network-aza-<app>` |
| Team | `H5A6B4L9W8` |
| Minimum | iOS 27, macOS 27 |
| Project | XcodeGen `project.yml`; the `.xcodeproj` is gitignored |

### Info.plist

| Key | Why |
|---|---|
| `CADisableMinimumFrameDurationOnPhone: true` | Without it, iPhone caps the app's animations at 60 Hz. |
| `ITSAppUsesNonExemptEncryption: false` | TestFlight stops asking on every upload. |
| `UIRequiresFullScreen: true` | On iOS 27 it only limits resizing to discrete sizes; it no longer opts out. |

On iOS 27, iPhone apps resize (on iPad and in iPhone Mirroring), and supported orientations are only a preference. Lay out by the view's size, never by orientation, idiom or `UIScreen.main`.

### Build settings

| Target | Setting |
|---|---|
| App, extensions | `SWIFT_VERSION: 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY: YES` |
| UI tests | `SWIFT_VERSION: 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated`. `XCTestCase`'s overrides are nonisolated. |

### Concurrency

- `nonisolated async` functions run on the caller's actor. Mark work that must leave the main actor `@concurrent`.
- Closures that a framework calls on its own thread trap if they were made on the main actor. Examples: dynamic colours (`UIColor { traits in … }`), `MPMediaItemArtwork`'s image closure, `AVAudioSourceNode`'s render block. Build them in a `nonisolated` function or type.
- Generated bindings (UniFFI) go in their own target with `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated`, or every call into the core becomes main-actor code.
- SwiftData `@Model` types are nonisolated, so anything they call (`oneRepMax`, `Catalog`) must be `nonisolated` too.
- Non-`Sendable` system objects such as `Activity` can't be captured into a `Task`. Keep the ID, and look the object up inside a `@concurrent` function.
- If iOS can relaunch the app in the background (location, audio), build the model in the app delegate's `didFinishLaunching`. No scene connects on a background relaunch.

### Data

| Data | Store |
|---|---|
| Records you edit | SwiftData (Heavier) |
| High-rate append-only samples | One file per day, rebuilt on read (Timeline) |
| Heavy or shared with the Mac | Rust core over UniFFI (Stream) |
| Preferences | `@AppStorage`. The `appearance`, `accent`, `account` and `signInAnswered` keys belong to AzaUI. |
| Secrets | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |

`@State` is a macro on iOS 27, and an `@Observable` held in `@State` is created once. Don't give it a default and also assign it in `init`.

### SwiftUI

| Do | Instead of | Because |
|---|---|---|
| `window.overrideUserInterfaceStyle` (AzaUI does this) | `preferredColorScheme` | It doesn't reach a sheet that's already open. |
| `ScrollView` + `VStack` for cards that change height | `List` | `List` animates row heights on its own clock, so cards jump. |
| Keep content laid out and reveal it with `frame(height: open ? nil : 0)` + `clipped()` | Inserting it with `if` | Opening animates as smoothly as closing. |
| `.reorderable()` + `.reorderContainer(for:)` | A custom drag gesture | Works in any container on iOS 27 and is accessible. |
| `.swipeActionsContainer()` on a `ScrollView` | Rebuilding as a `List` for swipes | |
| `.alert(_:item:)`, `.confirmationDialog(_:item:)` | A `Bool` plus a separate value | |
| `.onGeometryChange` | `GeometryReader` | Measures without changing layout. |
| Show an always-on sheet only once `Account.answered` is true | `.sheet(isPresented: .constant(true))` | The first-launch sign-in screen can't present over a sheet. |
| `AsyncImage` | Your own image cache | It follows HTTP caching on iOS 27. Use `.asyncImageURLSession` for a custom session. |

Liquid Glass:

- Use glass for controls that float over content, never for content itself.
- Use `.interactive()` only on things you can tap.
- Put glass that should merge or morph in one `GlassEffectContainer`, with `glassEffectID`. Timeline's calendar grows out of its button this way.

### Tests

- Write end-to-end XCUITests on the Simulator only. They never touch the Mac's mouse or keyboard.
- Launch once per run. A DEBUG-only `network-aza-<app>://reset` link returns to the first screen between tests.
- Poll every 0.1 s (`UITestSupport.poll`). XCTest's own waits check about once a second.
- Tests find their data, for example a training day in whatever plan exists. Never assume it.
- Environment variables open the app in any state, for screenshots: `<APP>_MOCK=1`, `<APP>_SHEET=profile`.
- `scripts/test.sh` runs `build-for-testing` only when a source file is newer than the last build.

### Scripts

| Script | Does |
|---|---|
| `scripts/deploy.sh` | Release build, install and launch on the iPhone (`DEVICE=`) |
| `scripts/testflight.sh [build]` | Archive and upload with the App Store Connect API key; the build number defaults to a timestamp |
| `scripts/test.sh [xcodebuild args]` | UI tests on the Simulator |
| `scripts/screenshots.sh` | README screenshots from mock data |

### App README

Icon and name, four screenshots, then **Features** (one line each), **How it works** (one paragraph naming the frameworks that do the work), and **Develop** (a table of commands).

## Develop

Needs Xcode 27.

| Task | Command |
|---|---|
| Build for iPhone and Mac | `scripts/build.sh` |
| Release a version | `git tag 0.x.y && git push --tags` |
