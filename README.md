# AzaUI

Shared SwiftUI for Coach, Stream and Timeline: the parts that must look and behave the same in every app. Anything else, apps write with SwiftUI directly.

## Contents

| | |
|---|---|
| `.azaUI(name:icon:accent:appearance:appID:scopes:showsSignIn:)` | On the window's root view. Applies the theme and colour, provides `Account.shared`, shows the sign-in screen on first launch, and takes the aza app's answer when it opens the app. |
| `ProfileButton` | Top right of the main screen. Your picture in a glass ring when signed in, a glass person button when not. |
| `AccountRow` | First row of the app's profile page. Opens the account page (picture, @handle, sign out), or signs in. |
| `AppearanceSection` | Theme (System, Light, Dark) and colour (presets plus a custom picker). |
| `Account`, `Profile` | Who's signed in: name, picture and handle (protocol section 6), and `Account.client`, the app's [AzaKit](https://github.com/plarza/protocol) client for sync data and server sign-ins. |
| `Accent`, `Appearance`, `Color(hex:)` | The stored colour and theme (`accent`, `appearance` keys). `Accent.standard` is black in light mode and white in dark. |
| `\.accent`, `\.onAccent` | The app's colour and the colour that reads on it. |
| `ChromeLogo` | The aza mark (or any logo) as polished chrome you can spin. See [Chrome logo](#chrome-logo). |
| `Chat.Transcript`, `Chat.Composer`, `Chat.Turn`, `Chat.Markdown`, `Chat.Part` | A chat with an AI, streamed, with what it thought and did on the way. See [Chat](#chat). |
| `ServerSentEvents` | Reads a `text/event-stream` and picks it back up after a dropped connection. |
| `UITestSupport` | `poll`, `wait`, `launchAtSignIn()` and `launchPastSignIn(signedIn:)` for UI tests. |

Signing in asks the aza app for a certificate (protocol section 7). AzaUI opens `aza:approve#req=…`; the aza app shows what the app asks for and, once approved, opens `https://<app ID>/aza#aza=…`. That's a universal link back to the app, so only the real app can receive it. AzaUI then uploads the certificate and loads the profile. The client's keys and certificate stay in the Keychain, for this device only. Without the aza app, signing in says to get it.

The app needs:

- An app ID: a domain the app's team controls, such as `coach.aza.network`.
- `/.well-known/apple-app-site-association` on that domain, listing the app for `/aza`.
- The Associated Domains entitlement `applinks:<app ID>`.

An app with no `appID:` signs in as `Profile.sample`, shown as “Sample account” with a grey picture and a Preview label.

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
    RootView().azaUI(name: "Timeline", accent: "0A84FF", appID: "timeline.aza.network")
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

To build against a local AzaKit rather than the released one, run `scripts/build-swift.sh` in the protocol repository and set `AZA_PROTOCOL_PATH=<protocol>`.

| Identifier | Element |
|---|---|
| `signIn`, `skip` | Sign-in screen buttons |
| `profile` | Profile button |
| `account`, `signOut` | Account row, sign out on the account page |
| `theme`, `accent.<HEX>` | Appearance controls |

## Chat

A chat with an AI that answers in streamed markdown, as in Coach's chat with Jarvis.

```swift
Chat.Transcript(messages: messages, turn: turn, retry: resend) {
    Text("Tell Jarvis what you're training for.")
}
.safeAreaInset(edge: .bottom) {
    Chat.Composer(text: $draft, answering: turn != nil, send: send, stop: stop)
}
```

| | |
|---|---|
| `Chat.Message` | One message: yours or the assistant's, with an optional label (“After your run”), and `sending` or `failed` for yours, which shows a retry. An assistant message is its `parts` in order (`thought`, `tool` with its `detail`, `text`) and how long it `worked`; all but the answer, the last text, fold into one line above it (“Worked for 14s · 5 steps”) that opens them in order. |
| `Chat.Turn` | The assistant's turn as it streams, with the ID it'll be stored under and when it started: `think` and `thinking`, `use` and `detail`, `say` and `write`, then `end`. Each adds to the last part or starts a new one, so nothing shown is ever taken back. Every part shows in order under “Working · 12s”, the current one shimmering; text is let out at an even pace a fraction of a second behind. `settle()` waits until it's all shown; then put the stored message in `messages` and drop the turn, and it takes the turn's place without anything moving. |
| `Chat.Transcript` | Your messages in bubbles, the assistant's turns full width, a date over each day, and the turn being written at the end. It keeps to the bottom while you're there (new text, a turn folding, the keyboard); scrolled up, it stays put and shows a button back down. Sending always brings you back. The latest 40 messages show, earlier ones a page at a time. A finished answer has a Copy button under it. |
| `Chat.Composer` | Grows to six lines. While the assistant answers, send turns into stop and you can keep writing. Return sends from a hardware keyboard, Shift-Return starts a line. Keep its text in `@AppStorage` so a draft outlives the app. |
| `Chat.Markdown` | Paragraphs, headings, lists, quotes, code with a copy button, tables and rules. Each block is its own view, so while streaming only the last one redraws; an unfinished `*`, `**`, `` ` `` or link at the end is closed or held back rather than shown raw. |
| `ServerSentEvents.follow` | Reads a stream and, when the connection drops, asks again with the last event ID until the server sends the last event or 204. |

A chat that holds up needs the server to:

- Write the answer on its own task, not the request's, so it carries on when the app closes or loses signal.
- Keep the answer's events and give each an ID, so a phone that comes back with `Last-Event-ID` gets what it missed, then the rest live. Coach does this on every return to the front.
- Take the phone's ID for each message, so it shows at once and never twice once the chat syncs.
- Stop on request, keeping what was said.
- Notify when an answer ends with nobody watching.

Jarvis's `/v1/chat` is the model.

## Chrome logo

Any SVG as a chrome object: a rounded rim, a bevel and a flat face, lit by a studio. It comes as a SwiftUI view, a Svelte component, and a CLI that renders stills and videos. Drag it and it keeps turning, then settles; it leans toward the pointer, and on phones with the phone.

```swift
ChromeLogo()                                  // the aza mark
ChromeLogo(studio: .kominka)                  // another studio
ChromeLogo(layout: url, settings: settings)   // another logo, from the CLI's .chromelayout
```

```svelte
<script>
  import { ChromeLogo } from '@aza/ui';
</script>

<ChromeLogo />                                <!-- the aza mark -->
<ChromeLogo svg={markup} studio="kominka" settings={{ depth: 0.08 }} />
```

The Svelte package installs from git (`"@aza/ui": "github:plarza/ui"`) and needs Vite, which loads each studio only when a logo uses it.

Every setting (shape, material, light, view, motion) is listed with its range in `web/chrome/settings.ts` and by `bun web/cli.ts --help`. The Svelte `settings` prop, the CLI's flags and `ChromeSettings` in Swift take the same values.

```sh
bun web/cli.ts logo.svg              # everything, into the current folder
bun web/cli.ts logo.svg --only png,video --size 2160 --motion spin --depth=0.08
```

| Output | |
|---|---|
| `logo.png` | Still with transparency |
| `logo.mp4` | H.264 on black, plays anywhere |
| `logo.webm` | VP9 with transparency, for Chrome and Firefox |
| `logo-hevc.mov` | HEVC with transparency, for Safari and Apple apps |
| `logo-prores.mov` | ProRes 4444 with transparency, for editing |
| `logo.glb` | The mesh, for Blender and other 3D tools |
| `logo.chromelayout` | What `ChromeLogo(layout:)` reads |

Videos loop seamlessly: `--motion sway` (default) rocks it, `spin` turns it all the way round.

How it works: three.js's SVG parser and Clipper2 turn the SVG into clean outlines (fill rules applied, strokes widened). Rings are offset inward from the outline and triangulated with Delaunator and Constrainautor; every point keeps its distance from the edge. The bevel is a function of that distance (`web/chrome/bevel.ts`). The face dome comes from the outline inflated like a membrane (Poisson's equation on a grid), which curves each stroke like a cushion without the crease distance would leave down its middle. Both are worked out once per SVG, so changing a setting moves vertices without triangulating again. On the web a shader evaluates the bevel per pixel; RealityKit uses per-vertex normals. The chrome itself is only reflection: a metal with no colour of its own, reflecting a photographed studio. Eleven ship (`monochrome`, the default, `broadway`, `countryHall`, `christmas`, `kominka`, `white`, `brown`, `wizja`, `london`, `neon`, `blocky`), each a CC0 Poly Haven panorama stored as an 8-bit grey AVIF of log brightness, about 25 KB at 2048 × 1024 (`Sources/AzaUI/Resources/Studios`, rebuilt by `bun web/studios.ts`). Only the studio a logo uses is loaded. `studio` (Svelte, Swift) or `--studio` (CLI) picks one; the web and CLI also take any `.hdr` panorama. On the web the dome's slope is read per pixel from a texture of the inflation, so mirror reflections never show the triangles.

The bevel, settings and motion exist twice, in `web/chrome/*.ts` and `Sources/AzaUI/Chrome/*.swift`. Change both together. After changing the outline or the layout code, regenerate the layout AzaUI bundles:

```sh
bun web/cli.ts assets/aza.svg --only layout --out Sources/AzaUI/Resources
```

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
| Records you edit | SwiftData (Coach) |
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
| A drag handle with a vertical-only `DragGesture` and `accessibilityAdjustableAction` for a list of cards | `.reorderable()` | On iOS 27 its lifted preview shrinks, moves sideways with the finger and carries a square background. |
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
| Chrome logo still, videos and mesh | `bun install && bun web/cli.ts logo.svg` |
| Type-check the web code | `bun run check` |
| Release a version | `git tag 0.x.y && git push --tags` |
