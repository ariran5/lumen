# Session 008 — 2026-05-13: Phase 5 (Shell Foundation) + Vapor-style Reactivity

> Огромная сессия. Phase 5 закрыт целиком: все примитивы для shell-as-fast-app готовы + рефактор реактивности по Vue Vapor / Solid модели. Pre-condition для shell rewrite полностью обеспечен.

---

## TL;DR

| ID | Фича | Результат |
|---|---|---|
| P5.1 | `TextInput` (native UITextField overlay) | InputLab demo |
| P5.2 | `ScrollView` (nested Renderer + intrinsic content height) | ScrollLab |
| P5.3 | `lumen.safeArea.{top,bottom,left,right}` (reactive signals) | автоматический re-render по rotation/keyboard |
| P5.4 | `Blur` + `Glass` (iOS 26 Liquid Glass через UIGlassEffect) | GlassLab |
| P5.5 | `position: absolute` + top/right/bottom/left | sticky overlay поверх ScrollView |
| P5.6 | `Image` принимает children | overlay поверх backdrop |
| P5.7 | `TabsStore` + multi-tab BrowserView + `lumen.tabs.*` JS API | TabsLab + Swift tab strip |
| P5.8 | `onScroll` event на ScrollView | sticky pill с прогрессом |
| P6.1 | EffectScope в CoreFramework | scope.dispose() cascades |
| P6.2 | Builders разделяют style/bindings (function = thunk) | `View({opacity: () => sig.value})` |
| P6.3 | `lumen._patchProp(id, key, value)` + post-render `registerBindings(tree)` | **150 r/s → 2 r/s** на ScrollLab |

Плюс 6 demo-приложений на разных портах + StartPage с быстрыми ссылками.

---

## P5.1 — TextInput

[Sources/LumenRuntime/TextInputView.swift](../Sources/LumenRuntime/TextInputView.swift): `LumenTextField: UITextField` + `TextInputController: UITextFieldDelegate`. Native UIView как overlay (паттерн VirtualList). Controlled value: `field.text = value` только если отличается — иначе iOS сбрасывает cursor на end-of-text.

Props: `value`, `placeholder`, `keyboardType` (default/url/email/number/decimal/phone/search), `returnKey` (default/go/next/done/search/send/continue), `autocapitalize` (none/sentences/words/characters), `autocorrect`, `secure`. Events: `onChange/onSubmit/onFocus/onBlur`. Padding — custom UIEdgeInsets через override `textRect/editingRect/placeholderRect`.

Demo [Examples/InputLab/](../Examples/InputLab/): Name (autocap=words), URL (kb=url, return=go, autocorrect=off, submit→haptics), Password (secure). Validated на iPhone — каретка не прыгает на signal-rerender'ах.

---

## P5.2 — ScrollView

[Sources/LumenRuntime/ScrollView.swift](../Sources/LumenRuntime/ScrollView.swift): `LumenScrollView: UIScrollView` с **nested Renderer** внутри `contentView`. Outer Renderer создаёт scroll-узел; inner Renderer (на `contentView.layer`) рендерит scroll's children.

Главный трюк — Renderer получил режим `.scrollContent`:
```swift
enum ContentMode { case stretch, scrollContent }
```
В `.scrollContent` mode `relayout()` подставляет `height: .greatestFiniteMagnitude`, дети получают свои intrinsic размеры (P2.3) и натурально стэкаются. Сохраняется `lastFlexRoot`. `computedContentHeight()` возвращает `max(root.children.map { $0.frame.maxY }) + root.style.padding.bottom`. LumenScrollView получает это число, ставит `contentView.frame.height` и `scrollView.contentSize`.

Synthetic wrapper: scroll-узел оборачивается в column-View с padding/gap из scroll-стиля + `flex.direction = .column`, `flex.height = .auto`, `flex.width = .auto`. Тогда intrinsic-sizing работает корректно.

Жесты внутри ScrollView: nested Renderer создаёт свой GestureRouter на contentView — onTap на карточке внутри scroll работает независимо от scroll-pan'а.

[Examples/ScrollLab/](../Examples/ScrollLab/): 40 Pressable-карточек с тапами.

---

## P5.3 — SafeArea (reactive)

Первый случай **native → JS reactive sync** в Lumen. CoreFramework:
```js
const _saT = signal(0), _saB = signal(0), _saL = signal(0), _saR = signal(0)
Object.defineProperty(lumen, 'safeArea', {
  value: Object.freeze({
    get top()    { return _saT.value },
    get bottom() { return _saB.value },
    /* etc */
  }), writable: false, configurable: false
})
lumen._updateSafeArea = function (t, b, l, r) {
  _saT.value = t; _saB.value = b; _saL.value = l; _saR.value = r
}
```

Native: [LumenPageViewController.viewSafeAreaInsetsDidChange](../Sources/LumenRuntime/LumenPageViewController.swift) → `onSafeAreaChange` callback → [FastAppHost.Coordinator](../Sources/LumenShell/FastAppHost.swift) хукает в `engine.updateSafeArea(insets)` → [JSEngine+SafeArea](../Sources/LumenRuntime/JSEngine+SafeArea.swift) зовёт `lumen._updateSafeArea(t,b,l,r)`.

Поскольку safeArea — signal'ы, чтение `lumen.safeArea.bottom` внутри `mount` автоматически subscribe'ит компонент: rotation/keyboard/status-bar → push в signal → microtask flush → effect re-runs.

Эта же модель планируется для orientation, theme, и других системных значений.

---

## P5.4 — Blur + Liquid Glass

[Sources/LumenRuntime/BlurView.swift](../Sources/LumenRuntime/BlurView.swift): `LumenBlurView: UIView` с UIVisualEffectView внутри. Children рендерятся в `effectView.contentView` через nested Renderer (стретч-режим).

`intensity` поддерживается:
- iOS-материалы (always): `ultraThin / thin / regular / thick / chrome` → `UIBlurEffect.Style.system*Material`
- **iOS 26+ Liquid Glass**: `glass / glassClear` → `UIGlassEffect()` / `UIGlassEffect(style: .clear)`. На iOS < 26 авто-fallback на systemMaterial / systemThinMaterial.

JS API два builder'а:
- `Blur({intensity: 'regular'}, children)` — общий
- `Glass({variant: 'regular' | 'clear'}, children)` — sugar для iOS 26 glass (новая ML-эстетика, рекомендуется для shell'а)

borderRadius/borderColor применяются к **wrapper** UIView (LumenBlurView сам), а не к effectView — это даёт корректный clip.

[Examples/BlurLab/](../Examples/BlurLab/): три pill'а (regular/clear/legacy) поверх многоцветной ScrollView'шки. Видно как glass-материал «следит» за цветом под собой когда скроллишь.

---

## P5.5 — `position: absolute`

[Sources/LumenLayout/FlexLayout.swift](../Sources/LumenLayout/FlexLayout.swift): добавлен `FlexPosition` enum + поля `position/top/right/bottom/left` в `FlexStyle`.

Алгоритм layout:
1. `flowChildren = node.children.filter { $0.style.position == .relative }` — flex/intrinsic как обычно
2. `absoluteChildren = ...filter { $0.style.position == .absolute }` — отдельный pass после flow
3. Для absolute:
   - Width: explicit → если есть; left+right оба → `contentW - left - right`; иначе intrinsic
   - Height: аналогично
   - Position: `left` имеет приоритет над `right`; `top` — над `bottom`
4. **`intrinsicSize` исключает absolute из bounding box** — иначе ScrollView пытался бы expand'нуть под sticky-overlay

Z-order: порядок объявления (declaration order = addSublayer order). Sticky-элементы пиши **после** scroll'а в коде.

Парсинг в [RenderNode.parseStyle](../Sources/LumenRuntime/RenderNode.swift) — `position: 'absolute' | 'relative'` + `top/right/bottom/left: number`.

---

## P5.6 — Image accepts children

В `Image(props, ...children)` теперь принимаются дети — overlay'я text/Glass/etc поверх загруженной картинки. Children рендерятся как sublayers Image-layer'а. ImageLayer не leaf теперь.

---

## P5.7 — Multi-tab + lumen.tabs.*

### TabsStore (Swift)

[Sources/LumenShell/TabsStore.swift](../Sources/LumenShell/TabsStore.swift): `@MainActor @Observable` singleton с `tabs: [TabModel]` + `activeID: UUID?`. Operations: `open(url?)`, `close(id)`, `switchTo(id)`. Никогда не остаётся 0 таб (auto-add empty).

`TabModel` получил `let id = UUID()`, `displayTitle` (pageTitle > host > "New Tab"), `Identifiable`.

### BrowserView (Swift)

[Sources/LumenShell/BrowserView.swift](../Sources/LumenShell/BrowserView.swift) переписан: рендерит **все** табы через `ZStack { ForEach(tabs) }` с `.opacity(isActive ? 1 : 0)` и `.allowsHitTesting(isActive)`. Это **сохраняет state** (WKWebView scroll position, JSContext heap) при переключениях.

### TabBar (SwiftUI, temp)

[Sources/LumenShell/TabBar.swift](../Sources/LumenShell/TabBar.swift) — горизонтальный strip чипов + "+". Не финальная эстетика — переедет на Lumen в shell-as-fast-app.

### JS bridge

[Sources/LumenRuntime/JSEngine+Tabs.swift](../Sources/LumenRuntime/JSEngine+Tabs.swift) — `lumen.tabs.*` API. Каждый JSEngine получает `ownTabID` через `installTabsBridge(ownTabID:)` — используется как дефолт в `close()`.

**Sendable workaround**: Swift 6 strict concurrency не пропускает `[String: Any]` / `JSValue` как return type @convention(block). Native возвращает **JSON-строки** для list/current/own, CoreFramework оборачивает в lumen.tabs:
```js
const raw = lumen._tabsRaw
const parse = (s) => (s === 'null' || s == null) ? null : JSON.parse(s)
lumen.tabs = {
  list:    () => parse(raw._listJSON()) || [],
  current: () => parse(raw._currentJSON()),
  own:     () => parse(raw._ownJSON()),
  open: (url) => raw.open(url ?? null),
  close: (id) => raw.close(id ?? null),
  switch: (id) => raw['switch'](String(id)),
}
```

API: `list() / current() / own() / open(url?) / close(id?) / switch(id)`. Each returns/accepts `TabInfo = {id, url, title, isLoading, isActive}`.

Demo [Examples/TabsLab/](../Examples/TabsLab/) — Identity panel показывает own/current, Actions открывает разные URLs, List отображает все табы с switch/close-кнопками.

---

## P5.8 — onScroll event

UIScrollViewDelegate.scrollViewDidScroll → JS `onScroll(e: {offset, viewportHeight, contentHeight})`. Fires ≤120Hz на ProMotion. Используется для sticky-headers / progress-indicators / parallax. В первой версии ScrollLab пропсы opacity/text обновлялись через signals → mount-rerun → 150 r/s, что стало триггером для Vapor-рефактора (см. P6 ниже).

---

## P6 — Vapor-style reactivity

### Проблема

После добавления onScroll user заметил просадку до 40fps в ScrollLab. HUD показал: **`fps 60 · 150 r/s · render 7.3ms (max 37)`**. Диагноз: каждый scroll-tick → 3 signal.set → mount-effect re-runs → outer Renderer.render(App) + inner Renderer.render(ScrollView children) = 2 рендера × 75 onScroll-tick'ов = 150 r/s.

### Research: Vue Vapor + Solid.js

Ключевой insight (выяснили через agent-research):

> **Vapor — компилятор-сахар над «оберни каждое реактивное выражение в свой effect»**. Component-функция бежит ОДИН раз, для каждого dynamic-binding создаётся отдельный `renderEffect`, который меняет одно свойство одного DOM-узла. Сигнал меняется → срабатывает только тот effect.

Vapor-compiled `<div :style="{opacity: x.value}">{{name}}</div>`:
```js
const n0 = template('<div></div>')()
const n1 = createTextNode(); insert(n1, n0)
renderEffect(() => setStyle(n0, {opacity: x.value}))   // effect #1
renderEffect(() => setText(n1, name.value))            // effect #2
```

### Перенос в Lumen (без компилятора)

Не имея template-компилятора, мы перенесли идею через **API contract**: «функция в style-слоте = реактивный thunk». Static значение → применяется один раз. Function → per-prop effect.

```ts
// СТАРОЕ — читаем .value на месте, mount-effect ловит зависимость
View({opacity: opacity.value, padding: 16}, ...)

// НОВОЕ — реактивное = thunk
View({opacity: () => opacity.value, padding: 16}, ...)
```

### Реализация (P6.1-3)

**EffectScope** в CoreFramework (Vue/Solid-style):
```js
function EffectScope() { this._effects = []; this._disposed = false }
EffectScope.prototype.run = function (fn) {
  const prev = currentScope; currentScope = this
  try { return fn() } finally { currentScope = prev }
}
EffectScope.prototype.dispose = function () {
  this._disposed = true
  for (const e of this._effects) e.dispose()
  this._effects.length = 0
}
```

Effect constructor регистрирует себя в `currentScope` если есть.

**splitStyle**:
```js
function splitStyle(props) {
  const style = {}; let bindings = null
  for (const k in props) {
    if (NON_STYLE[k]) continue
    const v = props[k]
    if (typeof v === 'function') {
      if (!bindings) bindings = []
      bindings.push([k, v])
    } else { style[k] = v }
  }
  return {style, bindings}
}
```

**Node IDs** — JS-counter `let _nextNodeId = 0`. Каждый builder делает `id: nextId()`. Native индексирует:
```swift
@MainActor static var nodeIndex: [Int: WeakMountedRef] = [:]
```
В `mountFresh` → `nodeIndex[nid] = WeakMountedRef(mount)`. В `removeMountTree` → `nodeIndex.removeValue(forKey: nid)`.

**`lumen._patchProp(id, key, value)` bridge** [JSEngine+Patch.swift](../Sources/LumenRuntime/JSEngine+Patch.swift):
```swift
let patch: @convention(block) (Int, String, JSValue) -> Void = { id, key, jsValue in
    MainActor.assumeIsolated {
        Self.applyPatch(id: id, key: key, value: jsValue)
    }
}
```
Supported keys: `opacity, backgroundColor, borderColor, borderWidth, borderRadius, text, color`. CATransaction.disable обёртка чтобы не было implicit-анимаций.

**`registerBindings(tree)`** — после `lumen.render(tree)`:
```js
function registerBindings(node) {
  if (node.bindings && node.id) {
    const id = node.id
    for (const [prop, thunk] of node.bindings) {
      effect(() => lumen._patchProp(id, prop, thunk()))
    }
  }
  if (node.children) {
    for (const child of node.children) registerBindings(child)
  }
}
```

**mount()** оборачивает в EffectScope:
```js
function mount(component) {
  let scope = null
  return effect(function () {
    if (scope) scope.dispose()
    scope = new EffectScope()
    const tree = component()
    lumen.render(tree)
    scope.run(() => registerBindings(tree))
  })
}
```

### ScrollLab миграция

```ts
// Sticky overlay — thunks вместо .value на месте
function StickyOverlay() {
  return View({
    position: 'absolute',
    top: lumen.safeArea.top + 8,
    left: 16, right: 16,
    opacity: () => Math.min(1, Math.max(0, scrollOffset.value / 80)),  // ← thunk
  },
    Glass({...},
      Text({fontSize: 13, color: '#0F0F12'}, 'Scroll Lab'),
      Text({fontSize: 11},
        () => {                                                          // ← thunk
          const progress = ...
          return `${pct}% · offset ${o}pt`
        }),
    ),
  )
}
```

### Результат

| | Старая модель | Vapor-style |
|---|---|---|
| r/s при скролле | **150** | **~2** |
| Renderer.render() | весь App + 40 cards × 75/sec | **0** (не зовётся) |
| Что обновляется | каждый CALayer property через reconcile | один CALayer.opacity + один CATextLayer.string |

Пользователь подтвердил «перфоманс значительно вырос». Это новая основа реактивности для shell и всех будущих fast-app'ов.

### Что НЕ доделано в Vapor-стеке

- **Children-thunks** (`() => cond ? A : B`, `() => items.map(Row)`) — для conditional/list reactivity. Сейчас структурные изменения дерева требуют mount-rerun. Это P6.4.
- **`_patchProp` ограничен** — поддерживает opacity, backgroundColor, borderColor/Width, borderRadius, text, color. Не поддерживает: **transform** (translateX/Y/scale/rotate), padding, gap, dimensions. Расширить когда дойдёт до shell-анимаций.
- **Per-MountedNode EffectScope** — сейчас один scope на весь mount. При reconcile удаление узла НЕ диспозит его per-prop effect'ы (утечка, патчат «мёртвый» nodeIndex который возвращает nil — silent no-op, но всё равно).
- **Migration других демо** — HN/InputLab/TabsLab/SheetLab всё ещё используют старый `signal.value` подход. Работает (mount-effect re-runs), но не fine-grained. Мигрировать когда понадобится перф.

---

## Bonus: diagnostics

[Sources/LumenRuntime/FPSOverlay.swift](../Sources/LumenRuntime/FPSOverlay.swift) расширен:
- `RenderMetrics.totalCount` — монотонный счётчик
- `quickSnapshot()` — дешёвая версия без сортировки
- HUD теперь показывает `120 fps · 110 r/s · 7.3ms (max 37)` — fps, renders/sec, avg/max render time

Также `Renderer.relayout` теперь сам пишет в `RenderMetrics.shared.record(lastRenderMs)` (раньше только VirtualList cells'ы). Это даёт «истинный» r/s.

Методика дебага:
1. В покое: `r/s` должно быть 0
2. Во время action: `r/s` показывает реактивную «громкость»
3. `render time > 8.3ms` (120fps бюджет) → дерево слишком тяжёлое или мерять granularity

---

## StartPage с demo-каталогом

[BrowserView.StartPage](../Sources/LumenShell/BrowserView.swift) — 7 кнопок-примеров, каждый на своём порту:

| Порт | Demo |
|---|---|
| 8080 | Tabs Lab — multi-tab API |
| 8081 | HN reader |
| 8082 | Drag Lab — gestures + spring |
| 8083 | Glass Lab — iOS 26 Liquid Glass |
| 8084 | Scroll Lab — scroll + sticky overlay (Vapor-style) |
| 8085 | Input Lab — TextInput |
| 8086 | Sheet Lab — bottomSheet variants |

URL'ы привязаны к Mac LAN IP `192.168.0.108:NNNN`. Сменишь сеть — обнови в `BrowserView.exampleApps`.

---

## Файлы

### Новые
- [Sources/LumenRuntime/TextInputView.swift](../Sources/LumenRuntime/TextInputView.swift)
- [Sources/LumenRuntime/ScrollView.swift](../Sources/LumenRuntime/ScrollView.swift)
- [Sources/LumenRuntime/BlurView.swift](../Sources/LumenRuntime/BlurView.swift)
- [Sources/LumenRuntime/JSEngine+SafeArea.swift](../Sources/LumenRuntime/JSEngine+SafeArea.swift)
- [Sources/LumenRuntime/JSEngine+Tabs.swift](../Sources/LumenRuntime/JSEngine+Tabs.swift)
- [Sources/LumenRuntime/JSEngine+Patch.swift](../Sources/LumenRuntime/JSEngine+Patch.swift)
- [Sources/LumenShell/TabsStore.swift](../Sources/LumenShell/TabsStore.swift)
- [Sources/LumenShell/TabBar.swift](../Sources/LumenShell/TabBar.swift)
- [Examples/InputLab/](../Examples/InputLab/)
- [Examples/ScrollLab/](../Examples/ScrollLab/)
- [Examples/BlurLab/](../Examples/BlurLab/) (Glass Lab)
- [Examples/TabsLab/](../Examples/TabsLab/)
- [Examples/SheetLab/](../Examples/SheetLab/)

### Расширены
- [Sources/LumenLayout/FlexLayout.swift](../Sources/LumenLayout/FlexLayout.swift) — `FlexPosition`, edges, absolute pass
- [Sources/LumenRuntime/RenderNode.swift](../Sources/LumenRuntime/RenderNode.swift) — `id`, parsing для всех новых kind'ов
- [Sources/LumenRuntime/ViewStyle.swift](../Sources/LumenRuntime/ViewStyle.swift) — ничего нового в этой сессии (transform animBindings были раньше)
- [Sources/LumenRuntime/Renderer.swift](../Sources/LumenRuntime/Renderer.swift) — `ContentMode`, nodeIndex, mountTextInput/Scroll/Blur, reconcile branches, `lastFlexRoot`/`computedContentHeight`, `RenderMetrics.record`
- [Sources/LumenRuntime/CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift) — EffectScope, splitStyle, nextId, registerBindings, mount(scope), TextInput/ScrollView/Blur/Glass/Image builders, NON_STYLE, lumen.tabs wrapper, lumen.safeArea reactive
- [Sources/LumenRuntime/LumenPageViewController.swift](../Sources/LumenRuntime/LumenPageViewController.swift) — `viewSafeAreaInsetsDidChange` callback
- [Sources/LumenRuntime/FPSOverlay.swift](../Sources/LumenRuntime/FPSOverlay.swift) — `totalCount`, `quickSnapshot`, r/s display
- [Sources/LumenRuntime/JSEngine+Platform.swift](../Sources/LumenRuntime/JSEngine+Platform.swift) — все новые install*Bridge() вызовы
- [Sources/LumenShell/BrowserView.swift](../Sources/LumenShell/BrowserView.swift) — TabsStore.shared, ZStack of tabs, 7-кнопочный StartPage
- [Sources/LumenShell/FastAppHost.swift](../Sources/LumenShell/FastAppHost.swift) — `tabID` параметр, `installTabsBridge`, `onSafeAreaChange` wire
- [Sources/LumenShell/TabModel.swift](../Sources/LumenShell/TabModel.swift) — `Identifiable`, `id: UUID`, `displayTitle`
- [packages/lumen-types/index.d.ts](../packages/lumen-types/index.d.ts) — TextInputProps, ScrollViewProps (+ onScroll), BlurProps, GlassProps, TabInfo, LumenTabs, lumen.safeArea, position+edges, `Thunk<T>`, `AnimatableNumber` extended

---

## Что осталось (next session backlog)

### Vapor-stack завершение (P6.4-6)
- Children-thunks (`() => cond ? A : B`, `() => items.map(Row)`)
- Per-MountedNode EffectScope для cleanup
- Extended `_patchProp`: transform parts (translateX/Y/scale/rotate), padding, gap, dimensions
- Migration демо'шек на thunk-style (HN, InputLab, TabsLab, SheetLab)

### Shell-as-fast-app (P7)
- Embedded shell-bundle в App resources (`lumen://shell` или `bundle:` URL scheme)
- BrowserView превращается в контейнер, грузит shell-фастапп
- Под shell'ом — таб-контент (WebTabView/FastAppHost как сейчас)
- Shell использует `lumen.tabs.*` для управления табами
- **Перед началом design talk** — пользователь явно просил обсудить визуальное направление прежде чем рисовать UI (см. [memory/feedback_minimal_ui.md])

### Дальше после shell
- Home / Library / TabSwitcher на Lumen runtime (с design talk'ом)
- Landing page Lumen-на-Lumen (showcase)
- Tab persistence (UserDefaults / lumen.storage)
- P4.3 bytecode caching
- P4.5 permissions
- P3.5 DevTools / Inspector

---

## Commands (быстрый запуск)

```bash
# Build + install (simulator)
xcodegen generate
xcodebuild -project Lumen.xcodeproj -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Build + install (iPhone 15 Pro Max real device)
DEVICE_ID="00008130-001C21593CC0001C"
xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Release \
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates build
APP="/Users/arian/Library/Developer/Xcode/DerivedData/Lumen-faxjlouniqfhksbtqnrbcjymwgmf/Build/Products/Release-iphoneos/Lumen.app"
xcrun devicectl device install app --device $DEVICE_ID "$APP"
xcrun devicectl device process launch --device $DEVICE_ID com.lumen.browser

# Все 6 dev-серверов одновременно
for spec in "Examples/TabsLab 8080" "Examples/HN 8081" "Examples/DragLab 8082" \
            "Examples/BlurLab 8083" "Examples/ScrollLab 8084" \
            "Examples/InputLab 8085" "Examples/SheetLab 8086"; do
  bun packages/lumen-cli/bin/lumen.js dev $spec &
done

# TS check во всех примерах
for d in Examples/*/tsconfig.json; do
  (cd "$(dirname $d)" && bun x tsc --noEmit --project tsconfig.json) && echo "✓ $d"
done
```

---

## Архитектурные решения (decision log этой сессии)

- **P5.1 controlled value**: `field.text = newValue` только если `field.text != newValue`, иначе iOS jumps cursor. JS-side responsible for source of truth (signal).
- **P5.2 nested Renderer**: ScrollView, Blur используют отдельный Renderer на их contentView. Это decouple'ит layout (scroll имеет infinite height) и позволяет reuse-у весь рендеринг pipeline.
- **P5.3 native→JS reactive**: signals в CoreFramework + push-bridge от native. Это новая модель для **любых** системных значений (orientation, theme, network).
- **P5.4 iOS 26 conditional API**: `if #available(iOS 26.0, *)` для UIGlassEffect, fallback на UIBlurEffect.
- **P5.5 absolute excluded from intrinsic**: bounding box parent'а не должен учитывать absolute детей — иначе ScrollView expand'ил бы под sticky.
- **P5.7 TabsStore singleton**: `static let shared = TabsStore()`, поскольку single-window app. SwiftUI BrowserView использует `@State private var tabs = TabsStore.shared`.
- **P5.7 Sendable workaround**: native bridges возвращающие сложные объекты пишутся через JSON-строки + CoreFramework parsing wrapper. JSValue / [String:Any] не Sendable в Swift 6 strict mode.
- **P6.2 function in style slot = thunk**: heuristic из Solid/Vapor. Handler'ы исключаются через NON_STYLE list (`onTap`, `onChange` и т.д.).
- **P6.3 node id = JS counter**: монотонный `_nextNodeId`. Native индексирует через `[Int: WeakMountedRef]` — weak references чтобы removeMountTree не оставлял dangling.
- **P6.3 CATransaction.setDisableActions в _patchProp**: иначе implicit-анимации CALayer на каждый patch стоили бы 1-2 кадра.
