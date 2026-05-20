# Android Port — Analysis & Plan

> Status: **planning document**. No Android code exists yet. This is the design baseline before Phase 0 begins.

The goal: bring Lumen to Android as a true native runtime (not a wrapper) with a single shared fast-app JS surface, so a fast-app written once runs on both iOS and Android with identical semantics.

## 1. Current iOS architecture — layers

| Layer | Files | LOC | What it does |
|---|---|---|---|
| **JS engine** | `JSEngine.swift` + 27 × `JSEngine+*.swift` | ~3,500 | JavaScriptCore (`JSContext`). Bridge protocol: `context.setObject(callback, forKeyedSubscript: "lumen.X")`. Push-channels via `JSManagedValue` (GC-safe). |
| **Renderer** | `Renderer.swift` | 918 | CALayer mount/reconcile. Same-id node → `applyGeometryOnly`; otherwise `applyAll`. Per-prop patch path via `lumen._patchProp`. |
| **Layout** | `LumenLayout/FlexLayout.swift` | 413 | Self-contained Flexbox in pure Swift. No Yoga / no deps. |
| **Animations** | `AnimationManager.swift` | 363 | Off-main: `CABasicAnimation` / `CASpringAnimation` on CALayer. Render server (backboardd) animates independently — even if JS stalls 200ms, motion doesn't stutter. **This is the iOS magic.** |
| **Native embeds** | ScrollView / BlurView / MapView / TextInputView / VirtualList / BottomSheet | ~1,500 | UIKit views as CALayer-backed children; hit-test via `GestureRouter`. |
| **Reactivity (JS)** | `CoreFramework.swift` heredoc | ~600 | `signal/effect/mount/Slot/View/Text/Pressable/...`. **No Proxy, no WeakRef** — Hermes-compatible (verified). |
| **Sandbox** | `Origin.swift`, `NetworkPolicy.swift`, `PermissionStore.swift`, `StorageQuota.swift`, `OriginContext.swift` | ~800 | Per-origin (`scheme+host+port`) isolation: storage / keychain / FS / network policy. Default-deny cross-origin. |
| **HMR** | `DevServerClient.swift` | ~80 | `URLSessionWebSocketTask` → `ws://host:port/__hmr`. The Bun dev-server itself is platform-independent. |
| **Shell** | `LumenShell/*` | ~2,000 | SwiftUI: BrowserView / AddressBar / TabBar / StartSheet / WebTabView (WKWebView). |

**Key insight.** `BuiltinFastApps.swift` already exposes `lumen.platform = "ios"`. `CoreFramework` JS is pure ES2020 — no iOS dependencies. Therefore:

> **The JS stack ports as-is: fast-apps, CoreFramework, lumen-types, dev-server, manifest format, bridge protocol. We rewrite only the native runtime.**

## 2. What is reusable 1:1 (don't rewrite)

- `packages/lumen-cli/` — TypeScript, cross-platform.
- `packages/lumen-types/` — TS types, add `Platform.OS` for rare branches.
- `tools/dev-server.ts` — Bun, HTTP + WebSocket.
- `Examples/*` — fast-apps, pure TS (except PlatformLab edge cases and the Liquid Glass demo).
- `CoreFramework.swift` heredoc → **extract to `packages/lumen-framework-js/index.js`** and embed as a resource on both platforms. This must happen first to avoid drift between an iOS copy and an Android copy.
- Bridge protocol (method names, signal shapes) — formalize as `docs/bridge-protocol.md`; both runtimes follow it.

## 3. Platform divergences requiring a decision before Phase 0

### 3.1 JS engine — Hermes

| Option | Pros | Cons |
|---|---|---|
| **Hermes** (Meta, RN) | Small (~3 MB), fast startup, AOT bytecode, production-proven | Not full ES2022 — but we're ES2020-only and don't use Proxy (verified) |
| V8 (J2V8 / Chromium) | Most capable, identical to Chrome | +10–15 MB APK, heavier startup |
| QuickJS | Tiny (~200 KB), embeddable | Slower, less tooling |

**Decision: Hermes.** Matches iOS JSC in character (embedded, no JIT in release, fast startup). Bridge protocol on Hermes uses `jsi::Function` / `jsi::Object` — maps cleanly to our `context.setObject(callback, ...)`.

**Audit needed:** `JSManagedValue` (push-channels for `lumen.notifications.onTap.subscribe`) → Hermes equivalent is `jsi::WeakObject`. Semantics close but not identical. Risk: GC cycles. Mitigation: every push-channel API already exposes an explicit `unsubscribe()`.

### 3.2 Render layer — the biggest divergence

| iOS | Android |
|---|---|
| `CALayer` — stateful, mutate `layer.backgroundColor` and it just renders | `RenderNode` (API 21+) — display lists; visual change requires `beginRecording()` / `endRecording()` again |
| Render server (backboardd) animates independently of main thread | `RenderThread` only animates through `RenderNodeAnimator` / `ViewPropertyAnimator` — *partially* off-main, less expressive |
| Hit-testing built into the CALayer hierarchy | None — we walk it ourselves (our `GestureRouter` already does; ports cleanly) |

**Architectural decision:** a custom `LumenSurfaceView extends View` (one View hosting the entire tree); inside, our own tree of `LumenLayer` objects, each owning a `RenderNode`. Reconcile / mount / patch — exactly mirror iOS. This gives:

- RenderNode performance (GPU-cached display lists, hardware compositor)
- Same mental model as iOS-side
- Our own hit-testing — no Android View boundaries per node

**Tradeoffs:**

- A RenderNode requires re-recording its display list on any visual change. We already have dirty-tracking via `lumen._patchProp` — use it as the invalidation trigger for the affected RenderNode.
- Embedding native Views (WebView, MapView, EditText) into this tree is *not* as clean as UIKit (where every `UIView` is CALayer-backed). On Android we keep an overlay layer of regular Views above the Surface and sync their geometry from the reconciler.

### 3.3 Animations — fidelity gap

iOS hands animation state to the render server, and the JS thread can be silent. Android gives us `RenderNodeAnimator` (transforms/opacity) — off-main but less flexible.

- **Identical:** translateX/Y, scale, rotate, opacity with spring physics.
- **Degraded:** color transitions, complex interpolated transforms, mid-animation interruption (iOS catches instantly; Android `ValueAnimator.cancel()` has quirks).

For v0.1 we accept the gap and document it as a known limitation.

### 3.4 Sandbox / origin model

iOS gives free boundaries: Keychain ACLs, App Sandbox containers. Android only gives per-app data dirs; there is no built-in "origin" inside one app.

We enforce it ourselves:

- Storage: `SharedPreferences` named `lumen.origin.<sha256(origin)>`
- SecureStorage: `EncryptedSharedPreferences` + `MasterKey` per origin
- FS: per-origin subdir under `context.filesDir/origins/<hash>/`
- NetworkPolicy: same logic via an OkHttp `Interceptor`

`NetworkPolicyTests` and `StorageQuotaTests` port directly.

### 3.5 iOS-only features that need unification at the API surface BEFORE the port starts

| Feature | Status today | Plan |
|---|---|---|
| **Liquid Glass** (UIGlassEffect, iOS 26) | iOS-only | API becomes `Blur({ variant: 'glass' \| 'material' })`. On Android `'glass'` → graceful fallback to material blur (`RenderEffect.createBlurEffect`, API 31+); on lower API, static tint. |
| **Safe area** | `lumen.safeArea.{top,bottom,left,right}` | Android via `WindowInsetsCompat`. Identical surface. |
| **Haptics** | `'light' / 'medium' / 'success' / 'warning' / ...` | Android `HapticFeedbackConstants` maps almost 1:1. Two rounded mappings (e.g. `'warning'` ≈ `LONG_PRESS`). |
| **MapView** | MKMapView | **MapLibre** (open-source, OSM-based, free) — preferred over Google Maps (per-key pricing). |
| **Bottom sheets** | `UISheetPresentationController` + nested Renderer | Material `BottomSheetBehavior` or custom via MotionLayout. iOS `medium`/`large` detents ≈ `STATE_HALF_EXPANDED`/`STATE_EXPANDED`. |
| **WebView** (non-fast-app sites) | WKWebView | Android `WebView` — close to 1:1, but cookie/storage isolation needs verification. |

### 3.6 Manifest extension

Today `manifest.json` does not declare compatible platforms. Add optional `platforms: ('ios' | 'android')[]`. Missing field → assume `['ios', 'android']` (backward-compat).

## 4. Phased plan

Estimates assume one full-time engineer. Phase 0 must complete before Phase B begins, otherwise rework risk is high.

### Phase 0 — Pre-work (1 week) ⚠️ blocking

- Extract `CoreFramework` heredoc → `packages/lumen-framework-js/index.js`; wire it into both platforms as an embedded resource.
- Lock the bridge protocol in `docs/bridge-protocol.md`: list every `lumen.*` method, signature, sync/async/push semantics.
- Extend manifest schema with optional `platforms?: string[]`.
- Restructure monorepo: `apps/ios/` (current root) + `apps/android/` (new). Large renaming PR.

### Phase A — Foundation (3–4 weeks)

- Gradle project (Kotlin, AGP 8.x, minSdk 26 — RenderEffect needs 31+, below that we fall back).
- Hermes integration via `com.facebook.hermes` (or standalone build).
- Minimal Activity: load manifest by URL → eval entry script → empty `LumenSurfaceView`.
- `console.log` / `lumen.platform = "android"` / `lumen.version`.
- Port `FlexLayout.swift` → `FlexLayout.kt` (~413 LOC, mechanical, ~1 week; reuse the Swift test cases).

### Phase B — Renderer core (3–4 weeks)

- `LumenSurfaceView` hosting the tree.
- `LumenLayer` (Kotlin) ≈ MountedNode (Swift): owns a `RenderNode`, children, lastTree.
- Mount + reconcile + same-id `applyGeometryOnly` / `applyAll` (port `Renderer.swift`).
- Visual style: background color, borderRadius, borderWidth, opacity, transform, shadow.
- Text → `StaticLayout` / `TextPaint` with correct lineHeight, fontWeight, color.
- Image → Coil (one acceptable dep) or `BitmapFactory` for the basic case.
- `lumen._patchProp` bridge → invalidates the affected RenderNode.

### Phase C — Bridges round 1 (must-have, 2–3 weeks)

- Fetch (OkHttp + NetworkPolicy `Interceptor`)
- Storage (per-origin SharedPreferences)
- History (Room or SQLite)
- Tabs (Kotlin TabsStore)
- Haptics (Vibrator + HapticFeedbackConstants mapping)
- Alert / ActionSheet (AlertDialog wrappers)
- Share (`Intent.ACTION_SEND`)
- Clipboard (ClipboardManager)
- StatusBar / SafeArea (WindowInsetsCompat)
- Linking (Intent filters → `lumen.linking.onIncoming`)
- SecureStorage (EncryptedSharedPreferences + MasterKey)
- Biometrics (BiometricPrompt)

### Phase D — Native views (2–3 weeks)

- ScrollView (custom — Android's `ScrollView` doesn't mesh with our dirty-tracking; build on `NestedScrollView` + reconciled content).
- TextInput (EditText wrapper).
- VirtualList (recycler-style, but in our reconcile format).
- BlurView (RenderEffect on API 31+, static tint below).
- BottomSheet (BottomSheetBehavior or custom + nested LumenSurfaceView).
- WebView (for non-fast-app sites).
- MapView (MapLibre).

### Phase E — Sandbox + permissions (1–2 weeks)

- Per-origin namespacing in storage / secure / FS.
- Permission prompt UI (port PermissionStore + PermissionPrompt).
- HTTPS-only gate (+ Developer Mode, + LAN exception).
- Storage quotas.

### Phase F — Animations (1–2 weeks)

- `RenderNodeAnimator` integration for transform/opacity.
- `SpringAnimation` (androidx.dynamicanimation) for spring physics.
- AnimatedValue ↔ RenderNode binding registry (port `AnimationManager.swift`).
- Mid-flight interruption testing — expect edge cases vs iOS.

### Phase G — Shell UI (2–3 weeks)

- Activity-based shell (or single-activity + fragments).
- AddressBar / suggestions.
- TabBar + TabRuntime port.
- StartSheet (Home embed + Tabs list + search).
- History screen — it's the `lumen://history` built-in fast-app, should work "for free" after Phase B.

### Phase H — Polish + release (2 weeks)

- HMR client (OkHttp WS → reload).
- All `Examples/*` verified on Android, platform-diff bug fixes.
- Android CI (Gradle + emulator test).
- Update README / CHANGELOG / docs.
- APK / AAB release artifacts.

**Total: ~17–24 weeks** for one engineer to reach iOS feature-parity.

## 5. Risks and open questions

| # | Risk | Mitigation |
|---|---|---|
| R1 | Hermes can't keep callback push-channels as cleanly as `JSManagedValue` | Bridge protocol mandates explicit `unsubscribe()`. Stress-test GC early in Phase A. |
| R2 | RenderNode re-record overhead exceeds CALayer mutation on complex trees | Profile on BankApp during Phase B; if bad, switch to batched per-frame recording. |
| R3 | Visible animation parity gap | Accept for v0.1; explicit note in `docs/ROADMAP`. |
| R4 | Embedding WebView/MapView in Surface-tree causes scroll glitches | Overlay layer of plain Views above the Surface; sync geometry inside `reconcile()`. |
| R5 | Material BottomSheet visually differs from iOS, breaks unified fast-app UX | Build a custom bottom sheet (MotionLayout or hand-rolled), don't use stock Material. |
| R6 | Liquid Glass on iOS 26 is an uncatchable fidelity gap | Already decided: `Blur({variant:'glass'})` graceful fallback. |
| R7 | Permission UX diverges (Android Settings vs iOS in-app prompt) | In-app prompt on Android too; deep-link to Settings for system-level requests (camera/contacts/etc). |
| R8 | Google Play may reject an app that "loads JS over the network" | Play allows it (RN does it) provided JS doesn't change core functionality; market as a "browser", not an "app store". |

## 6. Recommended pre-work (do these even if Android port slips)

1. **Extract `CoreFramework` JS into its own package.** Benefits iOS independently — separate tests for JS-side reactivity, versioning, no monster heredoc in Swift.
2. **Write `docs/bridge-protocol.md`** — 27 bridges × signatures × sync/async/push semantics. This is already half the Android-runtime design doc.
3. **Decide monorepo structure** — `apps/ios/` + `apps/android/` + `packages/` + `tools/` + `Examples/`. This is a renaming PR; do it before the port starts.

---

## Appendix A — iOS native API → Android equivalent

| iOS | Android |
|---|---|
| `JSContext` | Hermes runtime (or V8) |
| `URLSession` (Fetch) | OkHttp / `HttpURLConnection` |
| `URLSessionWebSocketTask` | OkHttp WebSocket |
| `UNUserNotificationCenter` | NotificationManager + AlarmManager + NotificationChannel |
| `LAContext` (Biometrics) | BiometricPrompt (androidx.biometric) |
| Keychain (SecureStorage) | EncryptedSharedPreferences + Android Keystore |
| `UserDefaults` | SharedPreferences |
| `UIPasteboard` | ClipboardManager |
| `UIActivityViewController` | `Intent.ACTION_SEND` |
| `UIAlertController` (ActionSheet) | AlertDialog + items |
| `UIDocumentPickerViewController` | `Intent.ACTION_OPEN_DOCUMENT` |
| `UIImagePickerController` | Photo Picker API (API 33+) / `Intent.ACTION_PICK` |
| `MKMapView` | MapLibre (recommended) / Google Maps SDK |
| `WKWebView` | WebView |
| `UISheetPresentationController` | BottomSheetBehavior (Material) or custom |
| `UIGlassEffect` | RenderEffect.createBlurEffect (API 31+) / static tint fallback |
| `UIRefreshControl` | SwipeRefreshLayout |
| Haptics (`UIImpactFeedbackGenerator`) | Vibrator + HapticFeedbackConstants |
| StatusBar (`setStatusBarStyle`) | WindowInsetsController |
| SafeArea (`safeAreaInsets`) | WindowInsetsCompat |
| `CADisplayLink` | Choreographer |
| `CABasicAnimation` / `CASpringAnimation` | RenderNodeAnimator + SpringAnimation (androidx.dynamicanimation) |
| CALayer | RenderNode (display list, GPU-cached) |

## Appendix B — bridges count

Verified via `ls Sources/LumenRuntime/JSEngine+*.swift | wc -l` → **27 bridge files**. Each maps to one or more `lumen.*` methods. The bridge protocol document needs to enumerate all of them with signatures.

---

# Implementation Plan

This section is the concrete blueprint: every file the Android tree needs, every Kotlin class to write, every test to port, every external dependency to add.

## 7. Bridge protocol — full enumeration

The 27 bridge domains, each mapped to its iOS file, its `lumen.*` surface, and the Android equivalent.

| # | Domain | iOS file | `lumen.*` surface | Sync/Async/Push | Android equivalent |
|---|---|---|---|---|---|
| 1 | ActionSheet | `JSEngine+ActionSheet.swift` | `lumen.actionSheet(opts) → Promise<index>` | Async | AlertDialog with items |
| 2 | Animation | `JSEngine+Animation.swift` | `lumen.AnimatedValue(initial)`, `.set / .animateTo / .stop` | Sync + push | androidx.dynamicanimation `SpringAnimation` / `FlingAnimation` + `RenderNodeAnimator` |
| 3 | Appearance | `JSEngine+Appearance.swift` | `lumen.appearance.theme`, `subscribe` | Sync + push | Configuration.uiMode + ContentObserver |
| 4 | Bench | `JSEngine+Bench.swift` | `lumen.bench.start/end` | Sync | SystemClock.uptimeNanos |
| 5 | Biometrics | `JSEngine+Biometrics.swift` | `lumen.biometrics.available() / .authenticate(reason)` | Async | BiometricPrompt (androidx.biometric) |
| 6 | Clipboard | `JSEngine+Clipboard.swift` | `lumen.clipboard.copy(s) / .paste()` | Sync | ClipboardManager |
| 7 | DocumentPicker | `JSEngine+DocumentPicker.swift` | `lumen.documentPicker(opts) → Promise<file[]>` | Async | `Intent.ACTION_OPEN_DOCUMENT` via ActivityResultContracts |
| 8 | Fetch | `JSEngine+Fetch.swift` | `lumen.fetch(url, init) → Promise<Response>` | Async | OkHttp + NetworkPolicy `Interceptor` |
| 9 | History | `JSEngine+History.swift` | `lumen.history.list() / .add / .remove / .clear / .subscribe` | Sync + push | Room database + Flow |
| 10 | ImagePicker | `JSEngine+ImagePicker.swift` | `lumen.imagePicker(opts) → Promise<asset>` | Async | Photo Picker API (API 33+) / `ACTION_PICK` |
| 11 | Lifecycle | `JSEngine+Lifecycle.swift` | `lumen.appState.{current, subscribe}` | Sync + push | ProcessLifecycleOwner |
| 12 | Linking | `JSEngine+Linking.swift` | `lumen.linking.canOpen(url) / .open(url) / .onIncoming.subscribe` | Sync + Async + push | Intent / PackageManager.queryIntentActivities |
| 13 | Network | `JSEngine+Network.swift` | `lumen.network.{online, type, subscribe}` | Sync + push | ConnectivityManager.NetworkCallback |
| 14 | Notifications | `JSEngine+Notifications.swift` | `lumen.notifications.{requestPermission, schedule, cancel, cancelAll, onTap.subscribe}` | Async + push | NotificationManager + AlarmManager + NotificationChannel + PendingIntent |
| 15 | Notify | `JSEngine+Notify.swift` | internal `_notify` (push-channel dispatcher) | Push (internal) | Custom dispatcher in `LumenNotify.kt` |
| 16 | Patch | `JSEngine+Patch.swift` | `lumen._patchProp(layerId, prop, value)`, `lumen._replaceChildren`, `lumen._remove` | Sync | Direct calls into `Renderer.kt` |
| 17 | Permissions | `JSEngine+Permissions.swift` | `lumen.permissions.{request, check, revoke}` | Async | Custom prompt UI + persistent store + system runtime perms |
| 18 | Platform | `JSEngine+Platform.swift` | `lumen.platform`, `lumen.version`, `lumen.haptics(kind)`, `lumen.alert(opts)` | Sync | `"android"` constant + Vibrator + AlertDialog |
| 19 | Render | `JSEngine+Render.swift` | `lumen._mount(tree)`, `lumen._unmount()` | Sync | Direct call into `Renderer.kt` |
| 20 | Router | `JSEngine+Router.swift` | `lumen.router.{push, pop, replace, current}` | Sync + push | Custom router (matches `LumenPageViewController` semantics) |
| 21 | SafeArea | `JSEngine+SafeArea.swift` | `lumen.safeArea.{top, bottom, left, right}` (reactive) | Sync + push | WindowInsetsCompat + ViewCompat.setOnApplyWindowInsetsListener |
| 22 | SecureStorage | `JSEngine+SecureStorage.swift` | `lumen.secureStorage.{get, set, remove, keys}` | Async | EncryptedSharedPreferences + MasterKey |
| 23 | Share | `JSEngine+Share.swift` | `lumen.share({text, url, files}) → Promise<bool>` | Async | `Intent.ACTION_SEND` / `ACTION_SEND_MULTIPLE` |
| 24 | StatusBar | `JSEngine+StatusBar.swift` | `lumen.statusBar.style({theme, hidden})` | Sync | WindowInsetsController.setSystemBarsAppearance |
| 25 | Storage | `JSEngine+Storage.swift` | `lumen.storage.{get, set, remove, has, keys, clear}` | Sync | Per-origin SharedPreferences |
| 26 | Tabs | `JSEngine+Tabs.swift` | `lumen.tabs.{open, navigate, close, switch, current}` + push | Sync + push | Kotlin `TabsStore` (parity with Swift) |
| 27 | WebSocket | `JSEngine+WebSocket.swift` | `lumen.ws(url, handlers) → handle` | Async + push | OkHttp WebSocket |

**Bridge protocol formal spec.** Every method follows one of three shapes:

```
// Sync
lumen.X.foo(args) → result        ← native returns immediately

// Async (Promise)
lumen.X.foo(args) → Promise<R>    ← native invokes resolve/reject callbacks held as managed refs

// Push channel
lumen.X.subscribe(handler) → () => void
                                  ← native invokes handler periodically; returned fn unsubscribes
```

All async/push methods MUST expose explicit unsubscribe/cancel. No method may hold a JS callback indefinitely without an opt-out path — this is what keeps Hermes GC sound.

## 8. Android module structure

Gradle multi-module project. One app, three library modules.

```
apps/android/
├── settings.gradle.kts
├── build.gradle.kts              # root convention plugins
├── gradle.properties
├── gradle/libs.versions.toml     # version catalog
├── app/                          # Lumen browser application
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/com/lumen/app/
│       │   ├── LumenApplication.kt
│       │   ├── MainActivity.kt
│       │   ├── shell/            # BrowserView equivalents
│       │   │   ├── BrowserScreen.kt
│       │   │   ├── AddressBar.kt
│       │   │   ├── TabBar.kt
│       │   │   ├── StartSheet.kt
│       │   │   ├── WebTabView.kt
│       │   │   ├── TabsStore.kt
│       │   │   └── HistoryStore.kt
│       │   └── di/               # Hilt/Koin or hand-rolled
│       └── res/
├── runtime/                      # ≈ Sources/LumenRuntime/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── kotlin/com/lumen/runtime/
│       │   ├── JsEngine.kt
│       │   ├── BridgeRegistry.kt
│       │   ├── BuiltinFastApps.kt
│       │   ├── BundleLoader.kt
│       │   ├── DevServerClient.kt
│       │   ├── render/
│       │   │   ├── Renderer.kt
│       │   │   ├── RenderNode.kt     # our model (≠ android.graphics.RenderNode)
│       │   │   ├── LumenLayer.kt     # owns one android RenderNode
│       │   │   ├── LumenSurfaceView.kt
│       │   │   ├── GestureRouter.kt
│       │   │   └── AnimationManager.kt
│       │   ├── views/
│       │   │   ├── LumenScrollView.kt
│       │   │   ├── LumenTextInputView.kt
│       │   │   ├── LumenBlurView.kt
│       │   │   ├── LumenMapView.kt
│       │   │   ├── LumenVirtualList.kt
│       │   │   └── LumenBottomSheet.kt
│       │   ├── sandbox/
│       │   │   ├── Origin.kt
│       │   │   ├── OriginContext.kt
│       │   │   ├── NetworkPolicy.kt
│       │   │   ├── SecurityPolicy.kt
│       │   │   ├── StorageQuota.kt
│       │   │   ├── PermissionStore.kt
│       │   │   └── PermissionPrompt.kt
│       │   └── bridges/          # one Kotlin file per Swift JSEngine+*.swift
│       │       ├── ActionSheetBridge.kt
│       │       ├── AnimationBridge.kt
│       │       ├── AppearanceBridge.kt
│       │       ├── BenchBridge.kt
│       │       ├── BiometricsBridge.kt
│       │       ├── ClipboardBridge.kt
│       │       ├── DocumentPickerBridge.kt
│       │       ├── FetchBridge.kt
│       │       ├── HistoryBridge.kt
│       │       ├── ImagePickerBridge.kt
│       │       ├── LifecycleBridge.kt
│       │       ├── LinkingBridge.kt
│       │       ├── NetworkBridge.kt
│       │       ├── NotificationsBridge.kt
│       │       ├── NotifyBridge.kt
│       │       ├── PatchBridge.kt
│       │       ├── PermissionsBridge.kt
│       │       ├── PlatformBridge.kt
│       │       ├── RenderBridge.kt
│       │       ├── RouterBridge.kt
│       │       ├── SafeAreaBridge.kt
│       │       ├── SecureStorageBridge.kt
│       │       ├── ShareBridge.kt
│       │       ├── StatusBarBridge.kt
│       │       ├── StorageBridge.kt
│       │       ├── TabsBridge.kt
│       │       └── WebSocketBridge.kt
│       └── assets/
│           └── lumen-framework.js  # extracted CoreFramework JS
├── layout/                       # ≈ Sources/LumenLayout/
│   ├── build.gradle.kts
│   └── src/main/kotlin/com/lumen/layout/
│       └── FlexLayout.kt         # port of FlexLayout.swift
└── tests/                        # ≈ Tests/
    └── src/main/kotlin/com/lumen/tests/
        ├── ReactivityTests.kt
        ├── ReconcilerTests.kt
        ├── FlexLayoutTests.kt
        ├── NetworkPolicyTests.kt
        ├── SecurityPolicyTests.kt
        ├── PermissionTests.kt
        └── StorageQuotaTests.kt
```

Dependency graph: `app → runtime → layout`. Tests against `runtime` + `layout`.

## 9. Per-phase deliverables — concrete files and tests

### Phase 0 — Pre-work

| Deliverable | File(s) | Acceptance |
|---|---|---|
| Extract framework JS | new `packages/lumen-framework-js/index.js` + Swift Bundle.main.url loader replacing the heredoc | iOS still builds and `ReactivityTests` pass identically |
| Bridge protocol doc | `docs/bridge-protocol.md` | All 27 domains enumerated with TS-style signatures |
| Manifest schema | edit `Sources/LumenRuntime/BundleLoader.swift` to accept `platforms?: string[]` | An iOS-only manifest still loads on iOS; missing field defaults to all |
| Monorepo restructure | move iOS into `apps/ios/`, add `apps/android/` skeleton, update `project.yml` paths, CI workflow paths | iOS CI green after move; Android module has empty `:app` that builds |

### Phase A — Foundation

| Deliverable | File | Acceptance |
|---|---|---|
| Gradle project skeleton | `apps/android/settings.gradle.kts`, `build.gradle.kts` × 4 modules | `./gradlew :app:assembleDebug` produces an APK that launches a blank screen |
| Hermes integration | `runtime/build.gradle.kts` Hermes dep, `JsEngine.kt` with `runtime.evaluateJavaScript("'hello'")` | unit test: eval returns expected string |
| `lumen` global + console | `JsEngine.kt`, `PlatformBridge.kt`, `JsEngine+console` init | unit test: `lumen.platform === 'android'`; `console.log` captured by logcat |
| `FlexLayout.kt` | port of `FlexLayout.swift` | port of `FlexLayoutTests` — all 30+ cases pass |
| `BundleLoader.kt` | parses manifest + fetches entry script | integration test: loads `Examples/HelloApp` over HTTP, evals successfully |

### Phase B — Renderer core

| Deliverable | File | Acceptance |
|---|---|---|
| `LumenSurfaceView` + custom drawing | `LumenSurfaceView.kt` | unit test: mount a 1-node `View({backgroundColor:'#f00'})` → see red 100×100 |
| `Renderer.kt` mount/reconcile | port of `Renderer.swift` | port of `ReconcilerTests` — all cases pass |
| Same-id `applyGeometryOnly` | inside `Renderer.kt` | port of `ReactivityTests.testSiblingSlotRebuildPreservesPerPropPatchedColor` |
| `lumen._patchProp` bridge | `PatchBridge.kt` | port of `ReactivityTests` — per-prop patch path |
| Text rendering | `Renderer.kt` text branch using StaticLayout | snapshot tests on font/size/color/lineHeight |
| Image loading | Coil integration in `Renderer.kt` image branch | integration test: load a remote PNG, see it rendered |

### Phase C — Bridges round 1

Each bridge file is a self-contained Kotlin class with the surface listed in §7. Each ships with:

- Unit test for the sync surface (`PlatformBridgeTest`, `ClipboardBridgeTest`, etc.)
- Integration test through `JsEngine` (`lumen.X.foo()` returns expected value)
- Permission-gated tests where applicable (denied / granted / revoked paths)

Bridges in this round, in priority order:

1. `PlatformBridge` (haptics, alert, version)
2. `StorageBridge` + `SafeAreaBridge` (every fast-app uses these)
3. `FetchBridge` (network policy gate from `NetworkPolicy.kt`)
4. `HistoryBridge` (Room DB with `lumen_history.db`)
5. `TabsBridge` (mirrors Swift TabsStore semantics)
6. `ClipboardBridge`, `ShareBridge`, `ActionSheetBridge`
7. `StatusBarBridge`, `LinkingBridge`
8. `SecureStorageBridge` (EncryptedSharedPreferences)
9. `BiometricsBridge` (BiometricPrompt)

### Phase D — Native views

| View | File | Notes |
|---|---|---|
| ScrollView | `LumenScrollView.kt` | Custom — wraps `NestedScrollView`, hosts a `LumenSurfaceView` child; calls `onScroll` to JS; supports pull-to-refresh via `SwipeRefreshLayout` overlay |
| TextInput | `LumenTextInputView.kt` | EditText wrapped + sync with `lumen` value/onChange; manages focus, blur, selection |
| VirtualList | `LumenVirtualList.kt` | `RecyclerView` with a custom `Adapter` that renders each row through our reconciler |
| BlurView | `LumenBlurView.kt` | `RenderEffect.createBlurEffect(radius, radius, EDGE_REPLICATE)` on API 31+; static tint fallback on 26-30 |
| BottomSheet | `LumenBottomSheet.kt` | Custom (NOT Material) — DialogFragment with motion-animated content; medium/large detents at 50%/100% |
| MapView | `LumenMapView.kt` | MapLibre native view; markers, camera, gestures via our `GestureRouter` |

### Phase E — Sandbox + permissions

| File | Mirrors | Tests |
|---|---|---|
| `Origin.kt` | `Origin.swift` | port of `Origin` unit tests |
| `NetworkPolicy.kt` | `NetworkPolicy.swift` | port of `NetworkPolicyTests` — same `connect` manifest examples, same expected verdicts |
| `SecurityPolicy.kt` | `SecurityPolicy.swift` | port of `SecurityPolicyTests` — HTTPS gate, LAN allow-list, Developer Mode |
| `PermissionStore.kt` + `PermissionPrompt.kt` | `PermissionStore.swift` + `PermissionPrompt.swift` | port of `PermissionTests` |
| `StorageQuota.kt` | `StorageQuota.swift` | port of `StorageQuotaTests` |

### Phase F — Animations

| File | Mirrors | Tests |
|---|---|---|
| `AnimationManager.kt` | `AnimationManager.swift` | unit: AnimatedValue.set updates layer property; .animateTo runs over expected duration |
| `LumenLayer` bindings (translateX/Y/scale/rotate/opacity) | inside `LumenLayer.kt` | integration: animate opacity from 0→1 over 300ms, sample at midpoint, expect ~0.5 |
| Spring physics | androidx.dynamicanimation `SpringAnimation` per property | integration: spring response 0.32, damping 0.86 settles within tolerance |

### Phase G — Shell UI

| Screen | File | Mirrors |
|---|---|---|
| Browser screen | `BrowserScreen.kt` | `BrowserView.swift` (SwiftUI) |
| Address bar | `AddressBar.kt` | `AddressBar.swift` |
| Tab bar | `TabBar.kt` | `TabBar.swift` |
| Start sheet | `StartSheet.kt` | `StartSheet.swift` |
| Web tab view | `WebTabView.kt` | `WebTabView.swift` (Android `WebView` host) |

### Phase H — Polish + release

- `DevServerClient.kt` (OkHttp WS) — reuse all dev-server behavior; iOS-side untouched.
- All `Examples/*` smoke-tested on emulator + at least one physical device.
- `apps/android/CHANGELOG-android.md` snapshot of Android-side release notes.
- Update top-level `CHANGELOG.md` with Android arrival.
- AAB built and signed for Play Console upload.

## 10. Dependencies (acceptable third-party)

Listed in `gradle/libs.versions.toml`. Stick to widely-trusted libraries; avoid YAGNI.

| Library | Reason | Version target |
|---|---|---|
| `com.facebook.hermes:hermes-engine` | JS runtime | latest stable |
| `com.squareup.okhttp3:okhttp` | Fetch + WebSocket | 4.12+ |
| `io.coil-kt:coil` | Image loading (lazy bitmap, caches) | 2.x |
| `androidx.biometric:biometric` | BiometricPrompt | 1.2+ |
| `androidx.security:security-crypto` | EncryptedSharedPreferences | 1.1+ |
| `androidx.room:room-runtime` + `room-ktx` | History DB | 2.6+ |
| `androidx.dynamicanimation:dynamicanimation` | SpringAnimation | 1.0+ |
| `androidx.activity:activity-ktx` | ActivityResultContracts | 1.9+ |
| `androidx.lifecycle:lifecycle-process` | ProcessLifecycleOwner | 2.8+ |
| `org.maplibre.gl:android-sdk` | Map | 11.x |
| `androidx.test:runner` + `espresso-core` | Tests | latest |
| Kotlin Coroutines + Flow | async + push channels | bundled |

**No**: RxJava (Coroutines/Flow only), Dagger (hand-rolled DI or Koin), React Native, Compose UI (would compete with our reactivity).

## 11. Build pipeline

- **AGP** 8.5+ / **Gradle** 8.7+ / **Kotlin** 2.0+ / **JDK** 17.
- minSdk 26 (Android 8.0). RenderEffect requires 31 — wrapped with version check, fallback path for 26-30.
- targetSdk = latest stable.
- ProGuard/R8 enabled in release; explicit `keep` rules for Hermes interop classes and bridge entry points.
- Signing config externalized via `~/.gradle/gradle.properties` or env vars; no keys in repo.
- CI: GitHub Actions workflow `.github/workflows/android-ci.yml` running `./gradlew :app:assembleDebug :runtime:testDebugUnitTest :layout:testDebugUnitTest` on `ubuntu-latest`.

## 12. Per-phase acceptance criteria (gating)

A phase ships when its acceptance criteria pass on CI. Phases B–F have explicit test ports — those tests are the gate.

- **Phase A:** `FlexLayoutTests` 30/30 pass; `lumen.platform === 'android'`.
- **Phase B:** `ReconcilerTests` + `ReactivityTests` 100% pass; HelloApp renders correctly on emulator.
- **Phase C:** every bridge has at least one passing integration test through `JsEngine`; HN reader runs end-to-end.
- **Phase D:** ScrollLab + InputLab + SheetLab + MapLab + BankLab smoke-tested.
- **Phase E:** `NetworkPolicyTests` + `SecurityPolicyTests` + `PermissionTests` + `StorageQuotaTests` 100% pass.
- **Phase F:** DragLab spring physics match iOS qualitatively (recorded side-by-side video).
- **Phase G:** browsing through tabs, history, address bar, bottom sheet all functional; can install a fast-app, navigate, close.
- **Phase H:** all `Examples/*` smoke-tested; CI green; release AAB built.

## 13. Estimated calendar

Full-time, one engineer, sequential phases:

```
Phase 0:  week 1
Phase A:  weeks 2–5    (4w)
Phase B:  weeks 6–9    (4w)
Phase C:  weeks 10–12  (3w)
Phase D:  weeks 13–15  (3w)
Phase E:  weeks 16–17  (2w)
Phase F:  weeks 18–19  (2w)
Phase G:  weeks 20–22  (3w)
Phase H:  weeks 23–24  (2w)
                       ──────
total:    ~24 weeks (6 months)
```

Compressible to ~16 weeks with two engineers working in parallel after Phase B (one on bridges, one on shell + native views).

## 14. What ships in the first public Android release

Minimum-viable Android v0.1:

- HelloApp + HN reader run end-to-end.
- All bridges in Phase C are wired.
- Sandbox + HTTPS-only gate enforced.
- Tabs, history, address bar functional in the shell.
- BankApp **may** be partially broken — acceptable for v0.1 if documented.

Out of v0.1, deferred to v0.2:

- Liquid Glass parity (will visually differ — documented).
- MapLibre integration if licensing tracking is required (can use a `MapView({ provider:'none' })` fallback that shows a static tile).
- Full animation parity (spring physics work; mid-flight catch behavior tracked as known issue).

