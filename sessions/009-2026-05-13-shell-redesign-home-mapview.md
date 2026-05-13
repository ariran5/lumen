# Session 009 — 2026-05-13: Shell Redesign + lumen://home + Native Bridges

> Длинная сессия. Shell-chrome переосмыслен под iOS 26 Liquid Glass dark, реактивность дочищена до per-node EffectScope, `lumen.history` / `lumen.tabs.subscribe` через generic `NativeNotifier`, builtin fast-apps (home / history / library-stub), нативный `MapView` мост, interactive swipe-back, compact chrome с pre-selected URL'ом через UITextField.

---

## TL;DR

| ID | Фича | Файлы |
|---|---|---|
| P7.1 | `untracked(fn)` + `Slot(props, thunk)` для children-thunks | CoreFramework.swift |
| P7.2 | Per-node EffectScope cleanup (nodeScopes Map + `_disposeNodes` batch) | CoreFramework, Renderer.swift, JSEngine+Render.swift |
| P7.3 | `NativeNotifier` — generic Swift→JS push-канал (subscribe/fire) | NativeNotifier.swift, JSEngine+Notify.swift, JSEngine.swift |
| P7.4 | `HistoryStore` + `lumen.history.{list,remove,clear,subscribe}` | HistoryStore.swift, JSEngine+History.swift, CoreFramework |
| P7.5 | `lumen.tabs.subscribe` через `withObservationTracking` | TabsStore.swift, CoreFramework |
| P7.6 | `lumen://` scheme + `BuiltinFastApps` (history / home / library) | BundleLoader.swift, BuiltinFastApps.swift |
| P7.7 | Bank Lab — banking app demo на Slot/thunks | Examples/BankLab/ |
| P7.8 | HN reader миграция на Slot/thunks (ScrollView + Slot, per-row opacity thunk) | Examples/HN/ |
| P7.9 | Shell-chrome rewrite — dark theme + Liquid Glass bottom bar | BrowserView, AddressBar, DarkPalette |
| P7.10 | Address suggestions panel (history matches с filter) | AddressSuggestions.swift |
| P7.11 | iOS-router slide → interactive swipe-from-edge | BrowserView |
| P7.12 | URL stack per-tab + `goBack()` | TabModel.swift |
| P7.13 | Priority-probe для http URL (без JSON-flash в WebView) | TabModel.commit() |
| P7.14 | Native `<MapView/>` (MKMapView мост) | MapView.swift, RenderNode, Renderer, CoreFramework |
| P7.15 | Compact chrome (disc 46×46) на всех не-home табах + UITextField selectAll | URLTextField.swift, AddressBar |
| P7.16 | `lumen.tabs.navigate(url)` — навигация ТЕКУЩЕЙ табы (без открытия новой) | JSEngine+Tabs.swift |

Параллельно — Liquid Glass Bottom sheet (iOS 26 backgroundColor=.clear), keyboard avoidance, fixed `nav.setNavigationBarHidden`, `.ignoresSafeArea()` на fast-apps.

---

## P7.1 — `untracked` + `Slot`

Проблема Vapor-варианта из прошлой сессии: реактивные children (списки, conditionals) требовали либо `VirtualList(count, render)` API, либо `mount-rerun` всего дерева при изменении массива.

[CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift) `untracked(fn)` — eval'нуть thunk без подписки текущего effect'а на signal'ы:
```js
function untracked(fn) {
  const prev = currentEffect
  currentEffect = null
  try { return fn() } finally { currentEffect = prev }
}
```

Используется в `splitStyle` и `Text`/`Slot` builders для initial-eval thunks: layout надо измерить с начальными значениями, но **не** подписывать mount-effect на signal'ы (иначе любая мутация → full mount rerun → обратно к не-Vapor).

`Slot(props, thunk)` — реактивный flex-контейнер (аналог `<For>`/`<Show>` в Solid, `v-for`/`v-if` в Vue Vapor):
```js
function Slot(props, thunk) {
  const sb = splitStyle(props)
  let initial = []
  try {
    const r = untracked(thunk)
    initial = Array.isArray(r) ? r.filter(x => x != null && x !== false && x !== true) : (r ?? [])
  } catch (e) {}
  return {type: 'view', id: nextId(), style: sb.style, children: initial, slotThunk: thunk, ...}
}
```

`registerBindings` подхватывает `slotThunk`:
```js
if (node.slotThunk && node.id) {
  effect(function () {
    const arr = filterNodes(slotThunk())
    lumen._replaceChildren(id, arr)
    for (const child of arr) registerBindings(child)
  })
}
```

Native bridge `lumen._replaceChildren(id, [RenderNode])` ([JSEngine+Patch.swift](../Sources/LumenRuntime/JSEngine+Patch.swift)):
```swift
let replaceChildren: @convention(block) (Int, JSValue) -> Void = { id, val in
    MainActor.assumeIsolated {
        Self.applyReplaceChildren(id: id, childrenValue: val)
    }
}
```
→ `renderer.replaceChildren(id:newChildren:)` мутирует `lastTree`, запускает `relayout()`, дёргает `onAfterLayout` (нужно ScrollView'у чтобы пересчитать `contentSize` когда slot изменил число детей).

---

## P7.2 — Per-node EffectScope cleanup

До этого scope был **mount-level**: одна scope для всего дерева. На mount-rerun (signal change) старая scope dispose'илась оптом, ВСЕ effect'ы пересоздавались. Утечка появлялась если node-id сменился но scope осталась подписана на сигналы.

Дизайн:
- JS: `const nodeScopes = new Map()` — id → EffectScope.
- `registerBindings(node)` для каждого id'шного узла создаёт свою EffectScope, все binding-effect'ы + slot-effect живут внутри.
- Native: `Renderer.disposalBuffer: [Int]` накапливает ids в `removeMountTree` и `updateMountedNode` (когда reconcile перезаписал id).
- В конце `relayout()` / `replaceChildren()` буфер flush'ится через `onNodesDisposed?(ids)` → `lumen._disposeNodes([ids])` → JS dispose'ит соответствующие scope'ы.

Без этого на mount-rerun старые id-effect'ы продолжали патчить layer'ы по уже мёртвым id (no-op на native, но JS-side утечка). Теперь чисто.

[CoreFramework.swift:524-580](../Sources/LumenRuntime/CoreFramework.swift), [Renderer.swift:440-460](../Sources/LumenRuntime/Renderer.swift).

---

## P7.3 — `NativeNotifier`: generic Swift→JS push

Бэкбон native-side реактивности. Любой native-store (History, Tabs, …) фаерит канал, JS-стороны слушают.

```swift
// NativeNotifier.swift
@MainActor
final class NativeNotifier {
    static let shared = NativeNotifier()
    private var engines: [WeakEngine] = []
    func register(_ engine: JSEngine) { ... }
    func fire(_ channel: String) {
        for w in engines { w.engine?.dispatchNotify(channel: channel) }
    }
}
```

JSEngine при init регистрируется. У движка `notifyListeners: [String: [(Int, JSManagedValue)]]` — `JSManagedValue` ОБЯЗАТЕЛЬНО, иначе retain-cycle JS↔Swift.

```swift
// JSEngine+Notify.swift
let subscribe: @convention(block) (String, JSValue) -> Int = { channel, fn in
    let mv = JSManagedValue(value: fn)!
    self.context.virtualMachine.addManagedReference(mv, withOwner: self)
    let id = self.nextNotifyID()
    self.notifyListeners[channel, default: []].append((id, mv))
    return id
}
```

JS-side обёртка в [CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift):
```js
lumen.history.subscribe = function (fn) {
  const id = lumen._notify._subscribe('history', fn)
  return function () { lumen._notify._unsubscribe('history', id) }
}
```

---

## P7.4 — HistoryStore + `lumen.history`

[HistoryStore.swift](../Sources/LumenShell/HistoryStore.swift): Codable, persist в Documents/history.json, capped 500. Все мутации через `persist()` который зовёт `NativeNotifier.shared.fire("history")`.

`TabModel.commit()` пишет визит (`lumen://` URL'ы НЕ пишет).

[BuiltinFastApps.swift](../Sources/LumenRuntime/BuiltinFastApps.swift) `historyJS` — fast-app с List + Slot:
```js
const items = signal(lumen.history.list())
lumen.history.subscribe(() => { items.value = lumen.history.list() })
// ScrollView → Slot({...}, () => items.value.map(Row))
```

Открыл URL в **другом** табе → `HistoryStore.record` → `fire('history')` → во всех движках callback → History tab перерисуется реактивно.

---

## P7.5 — `lumen.tabs.subscribe`

[TabsStore.swift](../Sources/LumenShell/TabsStore.swift) использует `withObservationTracking` для авто-broadcast'а:
```swift
private func startBroadcast() {
    withObservationTracking { [weak self] in
        _ = self?.tabs.count
        _ = self?.activeID
        for tab in self?.tabs ?? [] {
            _ = tab.displayTitle
            _ = tab.isLoading
            _ = tab.currentURL
        }
    } onChange: { [weak self] in
        MainActor.assumeIsolated {
            guard let self, !self.rebroadcastScheduled else { return }
            self.rebroadcastScheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebroadcastScheduled = false
                NativeNotifier.shared.fire("tabs")
                self.startBroadcast()  // re-arm
            }
        }
    }
}
```

Плюс title-update: в том же broadcast tick'е идём по `tabs`, для каждого с `pageTitle && currentURL` зовём `HistoryStore.updateTitle(forURL:title:)` — идемпотентный (обновляет entry только если title пустой). Title визита приходит ПОЗЖЕ commit() (после загрузки страницы), поэтому отдельной seam'ы нет.

---

## P7.6 — `lumen://` scheme + Builtin fast-apps

[BundleLoader.swift](../Sources/LumenRuntime/BundleLoader.swift) расширен:
```swift
static func load(from root: URL) async throws -> LumenBundle {
    if root.scheme == "lumen" { return try loadBuiltin(url: root) }
    // ... HTTP path как было
}

private static func loadBuiltin(url: URL) throws -> LumenBundle {
    guard let host = url.host,
          let script = BuiltinFastApps.script(for: host) else {
        throw BundleLoadError.invalidRoot
    }
    let name = BuiltinFastApps.displayName(for: host) ?? host
    let manifest = LumenManifest(name: name, version: "0", entry: "inline", minRuntime: nil, dev: false)
    return LumenBundle(manifest: manifest, script: script, origin: url)
}
```

[BuiltinFastApps.swift](../Sources/LumenRuntime/BuiltinFastApps.swift) — switch по host'у: `home / history / library`. JS-код встроен Swift'овыми multi-line strings (`#"""..."""#`). Pure JS (без TS) — подаётся прямо в JSC без транспиляции.

`TabModel.commit()` для `lumen://` schemes — `mode = .fastApp(url)` напрямую, без probe и без записи в историю.

Probe тоже знает: `BundleLoader.probe(url:)` для `lumen://` возвращает `.fastApp` без сети.

---

## P7.7 — Bank Lab

[Examples/BankLab/index.ts](../Examples/BankLab/index.ts) — банковский dashboard. Реактивный hero card с балансом (computed), filter chips (Pressable + per-thunk backgroundColor/color), Slot для transactions list, bottomSheet с деталями. Light палитра (`#F2F2F7` / `#FFFFFF` / `#007AFF` / `#0A8754`).

Демонстрирует:
- `signal<Tx[]>(initial)` + `computed(() => sum balance)`
- `Slot({}, () => visibleTx.value.map(TransactionRow))` — реактивный список
- `backgroundColor: () => filter.value === value ? '#0F0F12' : '#FFFFFF'` — per-prop thunk
- bottomSheet с динамическим контентом
- Add income / Add spend — мутируют `transactions.value = [...]` → Slot перерисовывается без full re-mount

---

## P7.8 — HN reader → Slot/thunks

[Examples/HN/index.ts](../Examples/HN/index.ts) переписан с `VirtualList(count, render)` на `ScrollView + Slot`. visitedRev hack убран — `visited: signal<{[id]: boolean}>` + `opacity: () => visited.value[s.id] ? 0.55 : 1` thunk per-row.

Эффект: тап по истории больше не пересобирает все 30 рядов. Только `opacity` каждой строки фаерит per-prop effect, патчит ровно один CALayer-prop. На FPS-overlay (`lumen.bench.showFPS`) — r/s около нуля при «Clear visited» вместо полного rebuild'а.

---

## P7.9 — Shell-chrome rewrite (iOS 26 Liquid Glass dark)

Полный рестайл `BrowserView` + `AddressBar` под мокап [docs/browser-ui-mobile.html](../docs/browser-ui-mobile.html) (Home frame, тёмный).

[DarkPalette.swift](../Sources/LumenShell/DarkPalette.swift): `#0B0B0F` / `#ECECEE` / `#9A9AA5` / accent purple `#B69CFF` / accent blue `#7FB8FF` / ok green `#7FE0B0`.

[AddressBar.swift](../Sources/LumenShell/AddressBar.swift): bottom-anchored Liquid Glass капсула:
- `[🏠 home] [ 🔒 host | URLTextField ] [✦ AI]`
- Glass background через `.regularMaterial` (iOS 26 рендерит как Liquid Glass)
- subtle white-border `0.5pt` opacity `0.18`
- shadow `radius 22, y 18` + `radius 6, y 2`
- home: `tab.goHome()`; AI: `onOpenLibrary` (открывает `lumen://library`)

Status bar text — light (`.preferredColorScheme(.dark)`).

TabBar (горизонтальный strip) **полностью убран** — таб-management теперь только через future Library page или AI button.

---

## P7.10 — Address suggestions

[AddressSuggestions.swift](../Sources/LumenShell/AddressSuggestions.swift): панель над AddressBar когда `isFocused`. Источник — `HistoryStore.shared.entries`, фильтр по подстроке в `title`/`url`, max 6.

Каждая строка: mono-аватарка с первой буквой хоста + title + host + стрелка. Тап → `tab.addressInput = entry.url; commit(); isFocused = false`.

Пустой query → топ 5 свежих визитов.

`@FocusState` поднят в BrowserView (нужен ему чтобы знать когда показывать панель), AddressBar получает через `@FocusState.Binding`.

---

## P7.11 — Interactive swipe-back

Первоначально пытался `SwiftUI .transition` (asymmetric `.move`) для router-style slide. Получилось «странно» — на тяжёлых `UIViewControllerRepresentable` (FastAppHost с UINavigationController внутри) встроенные транзишны дёргают frame во время mount'а, jerky look.

Заменил на manual interactive drag:
```swift
@State private var swipeOffset: CGFloat = 0

DragGesture(minimumDistance: 6, coordinateSpace: .global)
    .onChanged { v in
        guard canSwipeBack, v.startLocation.x < 30, v.translation.width >= 0 else { return }
        isSwiping = true
        swipeOffset = v.translation.width  // палец двигает напрямую
    }
    .onEnded { v in
        let shouldPop = v.translation.width > 220 || v.predictedEndTranslation.width > 180
        if shouldPop {
            withAnimation(.easeOut(duration: 0.22)) { swipeOffset = 800 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                tabs.activeTab?.goBack()
                swipeOffset = 0
            }
        } else {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) { swipeOffset = 0 }
        }
    }
```

Можно вести палец, остановить, отпустить — content вернётся. За порогом — дослайдить до края + `goBack()`. На fast-app'ах с pan-захватом (например MapView) gesture не пробивается — тогда compact chrome даёт UI-альтернативу (см. P7.15).

---

## P7.12 — Per-tab URL stack + `goBack()`

[TabModel.swift](../Sources/LumenShell/TabModel.swift):
```swift
private(set) var urlStack: [URL] = []
private var isBackNavigating: Bool = false
var lastNavDirection: NavDirection = .forward

func commit() {
    // ...
    if !isBackNavigating, let current = currentURL, current != url,
       current != Self.homeURL, urlStack.last != current {
        urlStack.append(current)
    }
    if !isBackNavigating { lastNavDirection = .forward }
    // ...
}

func goBack() {
    lastNavDirection = .back
    guard let prev = urlStack.popLast() else { goHome(); return }
    isBackNavigating = true
    addressInput = prev.absoluteString
    commit()
    isBackNavigating = false
}
```

Дом не пушится в стек (он база, всегда возврат). Дубликаты подряд скип. `isBackNavigating` флаг не даёт `commit()` пушить URL обратно при reuse.

---

## P7.13 — Priority-probe (без JSON-flash)

До: `commit()` оптимистично ставил `mode = .web(url)`, probe в фоне, при `.fastApp` swap'ает. Проблема — на первом визите fast-app'а WebView успевал показать JSON-манифест белым, потом сменялось.

После: держим **старый mode** до ответа probe (800мс окно). За пределом — комитим `.web`, probe продолжается, может upgrade'нуть до `.fastApp`.

```swift
isLoading = true
let target = url

Task { @MainActor [weak self] in
    try? await Task.sleep(for: .milliseconds(800))
    guard let self else { return }
    guard self.addressInput == target.absoluteString else { return }
    if self.modeMatches(target) { return }
    self.mode = .web(target)
}

Task { [weak self] in
    let result = await BundleLoader.probe(url: target)
    BundleProbeCache.shared.set(host: host, result)
    await MainActor.run {
        guard let self else { return }
        guard self.addressInput == target.absoluteString else { return }
        switch result {
        case .fastApp: self.mode = .fastApp(target)
        case .web:
            if !self.modeMatches(target) { self.mode = .web(target) }
        }
        self.isLoading = false
    }
}
```

User-side caveat: dev-серверы по HTTP — `https://192.168.0.108:8088` НЕ работает (нет SSL). Был эпизод дебагинга белого экрана из-за случайного `https://` в URL bar'е.

---

## P7.14 — Native MapView мост

Полный end-to-end native UIKit-компонент через 6-шаговый recipe.

[MapView.swift](../Sources/LumenRuntime/MapView.swift):
```swift
@MainActor
final class LumenMapView: MKMapView, MKMapViewDelegate {
    var onRegionChange: JSValue?
    var onPinTap: JSValue?
    private var suppressNextRegionEvent = false

    func apply(region: MapRegionSpec?, pins: [MapPinSpec], mapType: MKMapType) {
        // ... setRegion (с suppression flag чтобы не было JS-feedback-loop)
        // ... diff pins по signature, removeAnnotations + addAnnotation
    }

    nonisolated func mapView(_ map: MKMapView, regionDidChangeAnimated: Bool) {
        MainActor.assumeIsolated {
            if suppressNextRegionEvent { suppressNextRegionEvent = false; return }
            onRegionChange?.call(withArguments: [["lat": ..., "lon": ..., ...]])
        }
    }
}
```

Annotation — `class LumenPinAnnotation: NSObject, MKAnnotation, @unchecked Sendable` (MapKit pробрасывает между потоками, поэтому не `@MainActor`).

[RenderNode.swift](../Sources/LumenRuntime/RenderNode.swift) — `enum Kind { ..., map }` + `mapRegion / mapPins / mapType / onMapRegionChange / onMapPinTap`. Парсинг в `parseValue`.

[Renderer.swift](../Sources/LumenRuntime/Renderer.swift) — `mapView: LumenMapView?` в `MountedNode`. `mountMap`, `reconcileMap`, dispatch в `mountFresh / reconcile / kind-change cleanup / removeMountTree`.

[CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift) — `MapView(props)` builder + `region/pins/mapType/onRegionChange/onPinTap` в `NON_STYLE` (чтобы splitStyle их не вытаскивал в style), + `exportsObj` + `globalThis.MapView = MapView`.

[packages/lumen-types/index.d.ts](../packages/lumen-types/index.d.ts) — `MapRegion / MapPin / MapType / MapViewProps / function MapView()`.

[Examples/MapLab/](../Examples/MapLab/) (port 8088): map + 3 пина (Ferry/Golden Gate/Mission), chips для mapType, "+ Drop pin here" — добавляет random пин в текущий регион. Tap pin → bottomSheet с координатами. Реактивный HUD-pill с `region.value.lat.toFixed(3)` и зумом.

**Recipe для любого native UIKit компонента**:

| # | Файл | Что | ~строк |
|---|---|---|---|
| 1 | `Sources/LumenRuntime/XxxView.swift` | UIView/Controller wrapper + delegate. JS callbacks как `JSValue?`, `MainActor.assumeIsolated { cb.call(...) }` в делегатных методах | 80 |
| 2 | `RenderNode.swift` | Kind case + поля + парсинг в `parseValue` | 30 |
| 3 | `Renderer.swift` | поле в MountedNode, mountXxx/reconcileXxx, dispatch в 4 местах (mountFresh/reconcile/kind-change/remove) | 50 |
| 4 | `CoreFramework.swift` | builder с `nextId()`, NON_STYLE для custom props, exports + global | 25 |
| 5 | `packages/lumen-types/index.d.ts` | TS-интерфейс | 20 |
| 6 | пример | tsconfig+manifest+index.ts | по вкусу |

Long-lived подписки (slot-style) — JSManagedValue через `addManagedReference(_, withOwner:)`. Event-only callback'и — обычный JSValue (retain'ится через JSContext, без cycle).

---

## P7.15 — Compact chrome + UITextField selectAll

Финальная итерация: на ВСЕХ не-home табах bar схлопывается в disc 46×46 (только leading-glyph: 🔒 https / sparkles lumen / globe http). Tap → разворачивается в полный bar с pre-selected URL'ом → typing перетирает.

Pre-selection — нативный UITextField через `UIViewRepresentable`. SwiftUI TextField не умеет `selectAll(nil)`.

[URLTextField.swift](../Sources/LumenShell/URLTextField.swift):
```swift
final class Coordinator: NSObject, UITextFieldDelegate {
    func textFieldDidBeginEditing(_ field: UITextField) {
        parent.isFocused = true
        DispatchQueue.main.async { field.selectAll(nil) }
    }
    // ...
}
```

@FocusState в BrowserView заменён на @State Bool (UIViewRepresentable не работает с @FocusState.Binding). URLTextField сам пушит isFocused в `textFieldDidBeginEditing/EndEditing`.

[BrowserView.swift](../Sources/LumenShell/BrowserView.swift) — `.safeAreaInset(edge: .bottom)` вместо ZStack-alignment'а. SwiftUI авто-лифтит inset на keyboard-show.

`isCompactChrome`:
```swift
private var isCompactChrome: Bool {
    guard !isAddressFocused else { return false }
    guard let tab = tabs.activeTab else { return false }
    return tab.currentURL != TabModel.homeURL
}
```

AddressBar в compact-режиме рендерит:
```swift
private var compactPill: some View {
    Button {
        if hasURL { tab.addressInput = tab.currentURL?.absoluteString ?? "" }
        isFocused = true
    } label: {
        Image(systemName: leadingGlyph ?? "magnifyingglass")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(iconStyle)
            .frame(width: 46, height: 46)
            .background(glassBackground(cornerRadius: 23))
    }
}
```

Home button (в full режиме) — действие `isFocused = false; tab.goHome()`. Раньше был `enabled: !isFocused` который ломал tap когда bar развёрнут через compact.

---

## P7.16 — `lumen.tabs.navigate(url)`

Добавлен в [JSEngine+Tabs.swift](../Sources/LumenRuntime/JSEngine+Tabs.swift):
```swift
let navigate: @convention(block) (String) -> Void = { url in
    MainActor.assumeIsolated {
        guard let tab = TabsStore.shared.tabs.first(where: { $0.id.uuidString == ownIDString }) else { return }
        tab.addressInput = url
        tab.commit()
    }
}
tabsNS.setObject(navigate, forKeyedSubscript: "navigate" as NSString)
```

`lumen.tabs.open(url)` создаёт **новую** табу; `navigate(url)` — навигирует **свою**. Используется builtin lumen://home: тап по pin'у / recent-строке — `lumen.tabs.navigate(url)`.

---

## lumen://home

[BuiltinFastApps.swift](../Sources/LumenRuntime/BuiltinFastApps.swift) `homeJS`:
- Greeting по времени (`Good morning` / `afternoon` / `evening` / `Late night`) + «What's on your mind?»
- AI card (лиловый ✦ + подсказка про bottom-bar)
- Pinned grid (2 ряда × 4 пина: GitHub / Figma / HN / Notion / X / YouTube / arXiv / lumen://history)
- Recent section (4 свежих визита из `lumen.history.list().slice(0, 4)`) + кнопка «All →»

`recent` реактивен через `lumen.history.subscribe(() => { recent.value = ... })` — открыл сайт, вернулся домой, строка уже там без перезагрузки.

[TabModel.swift](../Sources/LumenShell/TabModel.swift):
```swift
static let homeURL = URL(string: "lumen://home")!
var mode: TabMode = .fastApp(homeURL)  // default

func goHome() {
    lastNavDirection = .back
    mode = .fastApp(Self.homeURL)
    addressInput = ""
    urlStack.removeAll()
}
```

`.start` mode остался в enum но дефолтно не достижим — SwiftUI StartPage (старая) dead code.

---

## Open / Followups

- **Library tab switcher** — сейчас `lumen://library` stub. AI-button открывает заглушку. Сделать настоящий tab switcher через `lumen.tabs.subscribe`.
- **lumen-cli bundling** — добавить `bun build` в dev-server для npm-deps (TanStack Query core etc). Сейчас только TS→JS, без resolve'а bare imports.
- **`@lumen/ui` kit** — `Card`, `Row`, `Section`, `Button`, `Page` готовые компоненты + `lumen.theme.{color,spacing,text}` токены. Сейчас каждый fast-app копипастит палитру и flex-padding'и.
- **MapView**: pin diff неполный (по signature, не keyed). Для тысяч пинов нужен keyed reuse.
- **WebView gesture priority** — MKMapView и WKWebView ловят touches до SwiftUI .gesture(). Edge-swipe-back на сайтах с pan-захватом не пробивается. Compact disc (P7.15) — UI-фолбэк.
- **Builtin fast-apps DEV** — home/history/library JS встроены Swift'строкой, любая правка = rebuild iOS (~30 сек). В DEBUG конфиге можно отдавать с dev-server'а с HMR.
- **iOS 26 status bar** — на light fast-app (web сайтах) preferredColorScheme(.dark) делает status bar светлым, на белом фоне нечитаемо. Динамический style по active mode.

---

## Deploy / launch

```sh
xcodegen
xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Debug \
  -destination 'id=00008130-001C21593CC0001C' -allowProvisioningUpdates build
APP="$HOME/Library/Developer/Xcode/DerivedData/Lumen-faxjlouniqfhksbtqnrbcjymwgmf/Build/Products/Debug-iphoneos/Lumen.app"
xcrun devicectl device install app --device 3C968EEF-1505-5987-B4E8-FF7CD6C260F6 "$APP"
xcrun devicectl device process launch --device 3C968EEF-1505-5987-B4E8-FF7CD6C260F6 com.lumen.browser
```

Dev серверы (запускаются параллельно):
```sh
bun tools/dev-server.ts Examples/BankLab 8087 &
bun tools/dev-server.ts Examples/MapLab 8088 &
bun tools/dev-server.ts Examples/HN 8081 &
# ... etc
```

Stop: `pkill -f "tools/dev-server.ts"` или по-портам.
