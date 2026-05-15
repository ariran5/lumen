# Lumen

> 🇬🇧 English: this file · 🇷🇺 Russian: [README.ru.md](README.ru.md)
>
> ⚠️ **Pre-1.0.** Lumen is under active development. The fast-app API and runtime may break between releases. Not production-ready.

An alternative iOS browser with two engines inside one shell:

1. **WKWebView** — regular web, like Safari.
2. **Native Runtime** — "fast sites" (fast-apps) render directly through CALayer, layout uses an in-house Flexbox, JS runs on JavaScriptCore.

The browser decides which engine to use based on the `/.well-known/lumen.json` manifest. Transparent for the user; for the fast-app developer it's a separate SDK.

The goal: 120 fps on ProMotion, the feel of a native app, while still being able to open any regular site via WebView.

For motivation and architecture see [docs/IDEA.md](docs/IDEA.md), [docs/PLAN.md](docs/PLAN.md), [docs/ROADMAP.md](docs/ROADMAP.md).

## Repository layout

```
.
├── App/                       SwiftUI entry point — LumenApp, ContentView, Info.plist
├── Sources/
│   ├── LumenRuntime/          Fast-app runtime (~50 files)
│   │   ├── JSEngine.swift            JavaScriptCore context + bridges
│   │   ├── JSEngine+*.swift          per-domain bridges (Render, Patch, Fetch, …)
│   │   ├── Renderer.swift            CALayer mount/reconcile
│   │   ├── RenderNode.swift          immutable tree representation
│   │   ├── CoreFramework.swift       JS-side @lumen/core: View/Text/signal/mount/Slot/...
│   │   ├── ViewStyle.swift           layer-style → CGColor/borderRadius/...
│   │   ├── ScrollView.swift, VirtualList.swift, BlurView.swift, MapView.swift,
│   │   │   TextInputView.swift       native-view embeds
│   │   ├── BottomSheetViewController.swift, GestureRouter.swift,
│   │   │   AnimationManager.swift    UIKit integration
│   │   ├── Origin.swift, NetworkPolicy.swift, OriginContext.swift
│   │   │                             sandbox / per-origin isolation
│   │   └── BundleLoader.swift        manifest + entry script fetcher
│   ├── LumenShell/            Browser UI on top of Runtime
│   │   ├── BrowserView.swift         SwiftUI shell: address bar + tabs + page host
│   │   ├── FastAppHost.swift         mounts a fast-app inside a UIViewController
│   │   ├── WebTabView.swift          WKWebView host for regular sites
│   │   ├── TabModel.swift, TabsStore.swift, HistoryStore.swift
│   │   └── AddressBar.swift, AddressSuggestions.swift, URLTextField.swift
│   └── LumenLayout/
│       └── FlexLayout.swift          self-contained Flexbox in Swift (no Yoga deps)
├── Tests/
│   ├── ReactivityTests.swift         signal → thunk → patch → CALayer end-to-end
│   ├── ReconcilerTests.swift         CALayer mount/diff/append/remove
│   ├── FlexLayoutTests.swift         flex layout regressions
│   └── NetworkPolicyTests.swift      sandbox / origin / manifest connect
├── Examples/                  Fast-apps (TS, loaded via dev-server inside Lumen)
│   ├── HelloApp/                     minimal single-file example
│   ├── BankApp/                      mid-sized app with router + ScrollView + Sheet
│   ├── BankLab/                      lab variant of BankApp
│   ├── HN/                           Hacker News reader (real-world demo)
│   ├── BlurLab, DragLab, InputLab, MapLab, PlatformLab,
│   │   ScrollLab, SheetLab, TabsLab  narrow labs for individual APIs
├── packages/
│   ├── lumen-cli/                    @lumen/cli — bun-based init/dev/build
│   └── lumen-types/                  @lumen/types — TS definitions for the runtime API
├── tools/
│   └── dev-server.ts                 shim: `bun tools/dev-server.ts <path> <port>`
├── docs/                      IDEA / PLAN / ROADMAP + UI prototypes
├── project.yml                xcodegen spec — source of truth
└── Lumen.xcodeproj            generated from project.yml
```

## Requirements

- macOS with Xcode 15+ (iOS SDK 17+).
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`.
- [Bun](https://bun.sh) — `brew install bun`. Used for the dev-server and CLI.
- An Apple Developer account (a free one is enough) for running on a physical device.

## Regenerating the Xcode project

`project.yml` is the source of truth. When you add files under `Sources/` or `Tests/`, usually it's enough to run:

```sh
xcodegen generate
```

Without this Xcode won't pick up the new files.

## Build and run

### iOS Simulator

Through Xcode (recommended):

1. Open `Lumen.xcodeproj`.
2. Pick a simulator (e.g. iPhone 17 Pro) → Run (⌘R).

Via CLI:

```sh
xcodebuild -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build
```

### Physical device

Pick your team in Xcode: select the Lumen target → Signing & Capabilities → choose your team. `project.yml` ships with an empty `DEVELOPMENT_TEAM`, and the generated `*.xcodeproj` is gitignored, so this stays local.

```sh
xcrun devicectl list devices                                     # get UDID
xcodebuild -scheme Lumen -showdestinations | grep <your iPhone>  # xcodebuild id format
xcodebuild -scheme Lumen -destination 'id=<xcodebuild-id>' \
  -derivedDataPath build build

xcrun devicectl device install app --device <devicectl-id> \
  build/Build/Products/Debug-iphoneos/Lumen.app
xcrun devicectl device process launch --device <devicectl-id> com.lumen.browser
```

xcodebuild and devicectl use **different formats** for device IDs — that's why both are listed above.

## Building fast-apps

Each example under `Examples/` is a self-contained fast-app: `manifest.json` + an entry script. Lumen loads them over HTTP from `http://<host>:<port>/` (the manifest lives at `/.well-known/lumen.json`).

### Running the dev-server

```sh
bun tools/dev-server.ts Examples/HelloApp 8080
```

The server serves the files, transpiles `.ts/.tsx` on the fly via `Bun.Transpiler`, and pushes a `reload` over WebSocket on changes (HMR).

The start page in `BrowserView.swift` lists built-in examples at `http://127.0.0.1:80XX` (works out of the box for the simulator). For a physical device replace `127.0.0.1` with your machine's LAN IP on the same Wi-Fi network.

### Your own fast-app

```sh
bunx @lumen/cli init my-app
cd my-app
bun ../tools/dev-server.ts . 8090
# open http://<host>:8090 in Lumen
```

Layout:

```
my-app/
├── manifest.json        name, version, entry, permissions, connect-rules
├── tsconfig.json        strict TS, no DOM lib (Text/Image are global)
└── index.ts             entry — start with mount(() => View(...))
```

The runtime API is described by the types in [packages/lumen-types/index.d.ts](packages/lumen-types/index.d.ts). Main building blocks: `View / Text / Pressable / Image / ScrollView / Glass / VirtualList / TextInput / MapView / Slot`, `signal / computed / effect / mount`, `lumen.fetch / lumen.bottomSheet / lumen.haptics / lumen.alert / lumen.router / …`.

For a hands-on walkthrough see [docs/guide/](docs/guide/).

## Tests

Unit tests on the simulator:

```sh
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

A specific class or test:

```sh
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:LumenTests/ReactivityTests
```

Coverage:

- **ReactivityTests** — fine-grained per-prop reactivity (signal → thunk → `lumen._patchProp` → CALayer). Catches the tab-bar-flicker bug: a sibling-slot rebuild overwrites per-prop patches with stale `lastTree.style` via reconcile/applyAll.
- **ReconcilerTests** — mount/reconcile invariant: same-kind reuse layer, kind change replaces layer, append/remove children, detach clears tree.
- **FlexLayoutTests** — flex regression suite (`row` / `column` / `flex` / `padding` / `justify` / `align` / intrinsic measure).
- **NetworkPolicyTests** — fetch sandbox: own-origin allow, cross-origin block, manifest connect whitelist (exact host / subdomain wildcard / scheme normalization).

## Architecture notes

- **Fast-apps never block the main thread.** JS lives in a JSContext, the renderer sets explicit CALayer positions inside `CATransaction.setDisableActions(true)` — the render server animates on top of that independently.
- **Vapor-style fine-grained reactivity.** A thunk in a style slot (`opacity: () => sig.value`) becomes a per-prop effect via `lumen._patchProp`. The mount tree is rebuilt only when the component function itself reads `.value` directly (usually it doesn't).
- **Reconcile invariant.** Same-id node = JS didn't rebuild the subtree → `applyGeometryOnly` (geometry + text/image content sync + gestures); visual styles are NOT overwritten. This is critical: otherwise a sibling-slot rebuild would overwrite just-applied per-prop patches (see `applyGeometryOnly` in `Renderer.swift` + `ReactivityTests.testSiblingSlotRebuildPreservesPerPropPatchedColor`).
- **Sandbox model:** per-origin storage / keychain / FS / network policy. Origin = scheme+host+port. Default-deny on cross-origin fetches; the manifest can widen via `connect`.
- **Bottom sheet** — UIKit `UISheetPresentationController`. Glass/Liquid Glass on iOS 26 is native, via `UIGlassEffect`. Sheet content is rendered through a nested Renderer; layout is fixed to medium-detent bounds (see `BottomSheetViewController.swift`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). For security issues see [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).
