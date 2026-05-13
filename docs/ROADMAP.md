# Lumen — roadmap (живой документ)

> Этот файл фиксирует **текущее состояние** и **что дальше**, чтобы между сессиями ничего не терялось. Концептуальная основа в [IDEA.md](IDEA.md), оригинальный Phase 0 план в [PLAN.md](PLAN.md). Обновляется по мере прогресса.

---

## Где мы сейчас (snapshot)

> Последний снимок состояния — [sessions/001-2026-05-13-routing-fullscreen.md](../sessions/001-2026-05-13-routing-fullscreen.md). Читай его перед началом новой сессии.

### Готово

| ID | Что | Метрика / Acceptance |
|---|---|---|
| M0 | Project skeleton (XcodeGen + iOS app) | build clean ✓ |
| M1 | Browser shell (WKWebView + AddressBar) | open HN, scroll ✓ |
| M2 | JavaScriptCore + Playground | 1e6 loop = 20ms ✓ |
| M3 | Minimal Flexbox в Swift (deviation от Yoga) | 7/7 unit tests, 9ms ✓ |
| M4 | CALayer renderer | 111 layers @ 0.62ms ✓ |
| M5 | Text node (CATextLayer + CoreText measure) | numberOfLines truncation ✓ |
| M8 (spike) | Virtual list 10k items | 0 dropped frames на 60Hz ✓ |
| M9-lite | Bundle loader (URL → manifest → script) | external dev flow работает ✓ |
| Bonus | Native API bridges | bottomSheet/alert/haptics/setTimeout ✓ |
| P1.1 | Pressable + onTap | tap по строке HN работает ✓ |
| P1.2 | Image node + ImageLoader (CGImageSource, URLCache, NSCache) | favicons в HN скроллятся плавно ✓ |
| P1.3 | `fetch` global (Promise-wrapper над `_nativeFetch`) | GET/POST + `.json()`/`.text()` ✓ |
| P1.4 | HN reader demo (`Examples/HN`) | список + detail page + comments ✓ |
| Routing | `lumen.router.push/pop/popToRoot/setTitle` + `UINavigationController` | native swipe-back, nav bar ✓ |
| Fullscreen | FastApp фуллскрин (`.ignoresSafeArea(.bottom)`) | под home-indicator уходит контент ✓ |
| S1.1 | Top inset для router-pages | UIView-обёртка на safeAreaLayoutGuide.top ✓ |
| S1.2 | Smoke-тест WebView после refactor | news.ycombinator.com рендерится корректно ✓ |
| S1.3 | Promise.all диагностика | баг не воспроизводится, HN на parallel fetch'ах ✓ |
| S1.4 | Удалены legacy inline demo вьюхи | один путь (URL → fast-app/web) ✓ |
| S1.5 | `lumen.storage` поверх UserDefaults | get/set/remove/keys/clear ✓, HN метит visited ✓ |
| M6 / P2.1 | Reconciler (index-based diff + MountedNode) | 7/7 unit-тестов, 1000 nodes update=2.0ms ✓ |
| M6+ | `lumen.virtualList(...).reload()` handle | onPop refresh в HN, visited fade через diff без флэша ✓ |
| P2.1.1 | `kind: 'virtualList'` в дереве, render+virtualList coexistence | 9/9 unit-тестов; HN: header + list через один `lumen.render` ✓ |
| P2.3 | Intrinsic-sizing FlexLayout (shrink-to-fit для контейнеров) | 10/10 unit-тестов; HN header без явных width/height ✓ |
| P3.1 | `@lumen/core` (Flutter-style + signals + mount) | HN переписан; +0.2ms cell overhead ✓ |
| P3.3 | Hot reload (WS + file watch + page recreation) | edit `index.js` → app re-render ≤300ms ✓ |
| P4.4 | Real-device benchmark — render perf | iPhone 15 Pro Max: avg 1.8ms / p95 2.5ms / max 4ms — 2× от 8.3ms бюджета 120fps ✓ |
| P3.2 | `@lumen/types` + TS pipeline (dev-server transpile) | HN на TypeScript, tsc clean, runtime perf без изменений ✓ |
| P3.4 | `@lumen/cli` (`init/dev/build`) | E2E: `lumen init demo` → `lumen build` (0.6 KB bundle) → `lumen dev` → симулятор ✓ |
| P4.1 | Manifest discovery в AddressBar (parallel + cache) | localhost → fast-app, news.ycombinator.com → web; повторный visit из кэша ✓ |
| P4.2.a | Gestures (low-level): tap+coords, double-tap, longpress, pan, swipe, pinch, rotate | [GestureRouter.swift](../Sources/LumenRuntime/GestureRouter.swift) + DragLab demo ✓ |
| P4.2.b | `transform: {translateX/Y, scale, rotate}` в style | CALayer.transform через CATransform3D ✓ |
| P4.2.c | `animated()` AnimatedValue (off-main CABasicAnimation / CASpringAnimation) | `.set/.animateTo/.stop`, snap-back demo в DragLab, spring + easeIn/Out/Linear ✓ |
| P5.1 | `TextInput` (kind в дереве, native UITextField overlay) | controlled value, onChange/onSubmit/onFocus/onBlur, keyboardType/returnKey/secure, InputLab demo ✓ |
| P5.2 | `ScrollView` (kind в дереве, UIScrollView + nested Renderer) | intrinsic content height, gestures inside scroll работают, 40-карточек ScrollLab demo ✓ |
| P5.3 | `lumen.safeArea.{top,bottom,left,right}` (reactive signals) | viewSafeAreaInsetsDidChange → JS-signals → автоматический re-render ✓ |
| P5.4 | `Blur` + `Glass` (iOS 26 Liquid Glass через UIGlassEffect, fallback на UIBlurEffect) | GlassLab — sticky pill поверх скроллящихся stripes ✓ |
| P5.5 | `position: absolute` + `top/right/bottom/left` в FlexLayout | sticky overlay поверх ScrollView ✓ |
| P5.6 | `Image` принимает children (overlay поверх backdrop'а) | — |
| P5.7 | `TabsStore` (`@Observable` singleton) + multi-tab BrowserView + `lumen.tabs.*` JS API | TabsLab demo + tab-strip в shell ✓ |
| P5.8 | `onScroll` event на ScrollView (offset/viewport/contentHeight) | ScrollLab sticky overlay по offset ✓ |
| P6.1 | EffectScope в CoreFramework | scope.dispose() cascades child effects ✓ |
| P6.2 | Builders разделяют style/bindings (function → thunk-binding) | `View({opacity: () => sig.value})` ✓ |
| P6.3 | `lumen._patchProp(id, key, value)` + JS-side `registerBindings(tree)` per-prop effects | ScrollLab: 150 r/s → ~2 r/s (Vapor-style win) ✓ |

### Архитектурные решения, зафиксированные по дороге

- **Yoga отвергнут в пользу своего Flexbox** на Swift. Yoga = C++20 пакет, SPM-импорт в Swift через C++ headers нетривиален. Свой ~250 LOC покрыл наши кейсы. Свапнуть на Yoga можно когда понадобятся фичи которых нет (flex-wrap, shrink, basis, position absolute).
- **Один JSContext = один поток** (пока main). JSC thread affinity ограничивает свободу. См. P2.2 как план выноса.
- **CALayer напрямую, не UIView.** UIView'ы только на границах (host containers, cells). Внутри — голые CALayer'ы для эффективности.
- **Bundle = URL + manifest**, не упакованный архив. Простая структура `/.well-known/lumen.json` + entry-скрипт. Архив (`.lumen` файлы) — будущая оптимизация.

---

## Phase 1 — Interactive apps ✓ ЗАКРЫТА

Все P1.1–P1.4 + Routing + Native APIs выкатились в сессии 001. HN reader работает end-to-end. См. снимок состояния в [sessions/001](../sessions/001-2026-05-13-routing-fullscreen.md).

---

## Phase 1.5 — Стабилизация ✓ ЗАКРЫТА (sessions/002)

S1.1–S1.5 закрыты в сессии 002. Подробности в [sessions/002-2026-05-13-sprint-S1.md](../sessions/002-2026-05-13-sprint-S1.md).

Ключевые находки:
- Top inset для router-страниц решён через UIView-обёртку, привязанную к `safeAreaLayoutGuide.top` ([LumenPageViewController.swift](../Sources/LumenRuntime/LumenPageViewController.swift)). VirtualList в [FastAppHost.swift](../Sources/LumenShell/FastAppHost.swift) монтируется в этот же контейнер.
- WebView режим работает без правок — `WebTabView` пережил refactor.
- **`Promise.all` параллельный fetch — баг не воспроизводится.** Тесты на 5 и 20 параллельных запросах к HN Firebase API успешно завершаются за 0.4–0.8s. Sequential workaround удалён, HN reader загружает 30 stories через `Promise.all`.
- Legacy demo (`DemoFastTabView`, `FastTabView`, `VirtualListDemoView`, `JSPlaygroundView`) удалены. Точка входа одна: URL → fast-app или WebView по манифесту.
- `lumen.storage` (UserDefaults-backed) — get/set/remove/keys/clear. HN demo помечает прочитанные новости через storage.

---

## Phase 2 — Reconciler & off-main

### P2.1 — M6 Reconciler ✓ MVP закрыт (session 003)

MVP-уровень закрыт: index-based diff + MountedNode tree. Подробности — [sessions/003-2026-05-13-reconciler.md](../sessions/003-2026-05-13-reconciler.md).

**Что есть:**
- [MountedNode](../Sources/LumenRuntime/Renderer.swift) — параллельное дерево с ссылками на CALayer'ы.
- `Renderer.render(tree)` ветвится: initial mount vs reconcile.
- Reconcile reuse'ит layer'ы при том же `kind`, меняет prop'ы (frame/background/opacity/border/text/image source). Изменение `kind` → swap layer.
- Index-based сопоставление детей: добавление в хвост и удаление с хвоста — O(1) per child. Без поддержки move'ов (LIS отложен).
- `LumenCell.prepareForReuse` больше не сбрасывает sublayers — reuse теперь идёт через diff.
- `lumen.virtualList({...})` возвращает handle с `.reload()`. HN reader вызывает reload в `onPop`, ячейки видимого списка переходят в visited-состояние через дельту opacity без флэша.

**Метрики (на симуляторе iPhone 17 Pro):**
- 1000 nodes initial mount: 3.0ms
- 1000 nodes update (5 опасити-дельт): 2.0ms (~33% быстрее initial)
- 7/7 unit-тестов ([Tests/ReconcilerTests.swift](../Tests/ReconcilerTests.swift)): identity-preserved при update opacity, append/remove children, kind swap, detach

**Что отложено (P2.1.x):**
- **Keyed-LIS move-патчи.** Сейчас перестановка детей даёт remount всех «съехавших» узлов. Для текущих кейсов (HN list где порядок не меняется) хватает index-based.
- **Render + virtualList в одном дереве.** Сейчас `virtualList` отдельный API, монтирует UICollectionView поверх contentView. M6 не решает это структурно — нужен `kind: 'virtualList'` в RenderNode (next step P2.1.1).
- **Incremental layout.** Layout всё ещё пересчитывается полностью каждый render (Yoga-style инвалидация дерева — следующая оптимизация).
- **Intrinsic-sizing FlexLayout (P2.3)** — задача отдельная, не часть M6.

**Acceptance — выполнен:**
- ✓ 1000 nodes, 5 дельт, update < 10ms бюджета (фактически ~2ms).
- ✓ opacity update не флэшит, layer identity сохранена (доказано unit-тестом).
- ✗ `render` + `virtualList` coexistence — отложено до P2.1.1.

### P2.1.1 — virtualList как kind в дереве ✓ закрыт (session 003)

`kind: 'virtualList'` добавлен в RenderNode. Renderer на mount создаёт `VirtualListController` + `VirtualListView`, добавляет UICollectionView как subview hostView с absolute frame из flex layout. На reconcile — переиспользует view и контроллер, обновляет count/itemHeight/renderFn и дёргает `reloadData()`. На kind swap (например text → virtualList) корректно создаёт overlay; на обратный swap — снимает.

Old side-channel API `lumen.virtualList(config)` и `installVirtualListBridge` **удалены**: один путь через дерево.

**Известное ограничение:** virtualList узел использует `flex.frame` как абсолютные координаты относительно `rootLayer` (≈ hostView). Это работает когда virtualList сидит на верхнем уровне дерева (root или прямой ребёнок root flex-контейнера, как в HN). Для произвольного вложения нужен `CALayer.convert(_, to: rootLayer)` — добавится при первом use-case.

HN demo переписан: `lumen.render({...children: [header, {type: 'virtualList', flex: 1, count, render, ...}]})`. Header (CALayer) и virtualList (UICollectionView overlay) живут в одном дереве, обновляются через reconciler.

### P2.2 — Off-main thread computation (~1 сессия)

После M6 у нас уже есть промежуточная форма `[Patch]`. Её и считать в фоне.

**Шаги:**

1. **Flex build + calculateLayout** в отдельной `DispatchQueue.global(qos: .userInteractive)`. FlexNode — Swift-структура, нет связи с UIKit, можно безопасно.
2. **TextMeasure off-main + LRU cache** на `CTFramesetter` по `(text, font, maxWidth)`.
3. **Diff в фоне** на иммутабельных snapshot'ах prev/next tree.
4. **Image decode** уже off-main, ничего не меняем.
5. **На main приезжает** только `[Patch] + Map<NodeRef, CGRect>` (frames). Apply — синхронно, чисто Layer-операции.

**Гранитная проблема:** `JSValue` не Sendable, callbacks в `onTap` нельзя унести в фон. Решение: парсинг JSValue → RenderNode остаётся на main (быстрый), а уже Swift-struct RenderNode уходит в фон. Handlers map отдельно.

**Acceptance:**
- В M8-демо при `CADisplayLink`-scroll main thread utilization < 20%.
- HN list scroll показывает stable 120fps на симуляторе (cap), 100+ на железе.

### P2.3 — Intrinsic-sizing в FlexLayout ✓ закрыт (session 003)

`FlexLayoutEngine.intrinsicSize(_:available:isParentRow:)` рекурсивно меряет shrink-to-fit: leaf через `measure` callback, контейнер — bounding box детей + padding + gaps. Используется в `calculateLayout` как fallback когда у ребёнка нет explicit width/height/flex/measure.

Параллельно исправлен баг в cross-axis: проверка `cs.alignItems == .stretch` смотрела на child вместо parent (CSS говорит stretch определяется родителем). После фикса children могут иметь intrinsic cross-size, когда parent `alignItems != .stretch`.

HN header переписан без явных width/height. Layout сам считает intrinsic. Visually подтверждено: header сжимается под контент, button "Clear visited" — sized по тексту + padding.

Image-узлы пока без intrinsic measure (ждёт загрузки). Это допустимо — обычно у image задают explicit size.

---

## Phase 3 — Developer Experience

Это самая важная фаза для **продуктового пути B/C (SDK / hybrid)** — без неё писать настоящие приложения мучительно.

### P3.1 — `@lumen/core` ✓ закрыт (session 004)

Реализован как embedded JS-runtime ([CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift)) — глобально доступен в каждом fast-app'е, не требует npm-install. **Flutter-style functional API** вместо JSX/htm:

```js
function Counter() {
  return View({padding: 16, gap: 8},
    Text(`Count: ${count.value}`),
    Pressable({onTap: () => count.value++},
      Text('Increment'))
  )
}
mount(Counter)
```

API: `signal/computed/effect`, `View/Text/Pressable/Image/VirtualList`, `mount(componentFn)`.

Внутреннее: signals invalidate подписанные effects через `Promise.resolve().then()` (fallback от `queueMicrotask`, который не работает в JSC). Mount = effect, который дёргает `lumen.render(componentFn())`. Reconciler из M6 применяет дельту без флэша.

Метрика overhead: HN на framework = avg 1.8ms / p95 2.5ms / max 4ms vs до framework 1.6 / 2.3 / 3.2ms — **+0.2ms на cell**, zero-cost abstraction.

### (старая редакция P3.1, в архив)

Сейчас разработчик руками строит JS-объекты с полями `kind`, `children`, `style`. Это RN до-Reacta. Нужен React-подобный слой.

**API цели:**
```js
import { signal, View, Text, Pressable, render } from '@lumen/core'

const count = signal(0)
function Counter() {
  return (
    <View style={{ padding: 16 }}>
      <Text>Count: {count.value}</Text>
      <Pressable onTap={() => count.value++}>
        <Text>Increment</Text>
      </Pressable>
    </View>
  )
}
render(<Counter />)
```

**Шаги:**
1. **JSX-runtime** — мини `h(type, props, ...children)`. esbuild конфигурируется `jsxFactory: 'h'`.
2. **Signals** — `signal(initial)`, `.value` getter/setter с автотрекингом, `computed(() => ...)`, `effect(() => ...)`. ~150 LOC, без шедулера — синхронный invalidate с batching через `queueMicrotask`.
3. **Компоненты** — функциональные. State через `useState`/`useReducer` (обёртка над signal+effect). Hooks: useEffect, useMemo, useCallback, useRef.
4. **Reconcile с M6** — на изменение сигнала компонент перерендеривается → собирается новое дерево → diff (P2.1) → patch.
5. **Built-in компоненты** — `View`, `Text`, `Pressable`, `Image`, `ScrollView` (потом), `VirtualList` (рендерится в `kind: 'virtualList'` node после P2.1).

**Acceptance:** переписать HN reader на JSX + signals. Должно стать чище в 5-10×.

### P3.2 — `@lumen/types` ✓ закрыт (session 005)

[packages/lumen-types/index.d.ts](../packages/lumen-types/index.d.ts) — ambient типы для globals (`View`, `Text`, `Pressable`, `Image`, `VirtualList`, `signal`, `computed`, `effect`, `mount`, `lumen.*`, `fetch`, `console`, `setTimeout`).

Подключение через `tsconfig.files`:
```json
{
  "compilerOptions": {
    "lib": ["ES2020"],     // важно: без DOM, иначе Text/Image конфликтуют
    "types": [],
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true
  },
  "files": [
    "../../packages/lumen-types/index.d.ts",
    "index.ts"
  ]
}
```

Pipeline: `.ts/.tsx` файлы отдаёт [dev-server](../tools/dev-server.ts) через `new Bun.Transpiler({loader: 'ts'}).transformSync(src)` — клиент Lumen видит чистый JS, типы вырезаны. Production-серверы делают аналогично, либо `lumen build` (будущий P3.4) делает AOT.

[Examples/HN/index.ts](../Examples/HN/index.ts) переписан с типами (`interface Story`, `signal<Story[]>`, `Signal<T>`). Также добавлен пример **`lumen.bottomSheet`** — тап на "Open article" выезжает sheet с native UISheetPresentationController, внутри Lumen-rendered контентом.

Реализация занимает 1 .d.ts файл + package.json + 5 LOC в dev-server.

### P3.3 — Hot reload ✓ закрыт (session 004)

- `tools/dev-server.ts` — WebSocket на `/__hmr` + `fs.watch(root, {recursive:true})` с дебаунсом 50ms. На любое изменение файла бродкастит `{type:'reload', file}` всем подключённым клиентам.
- [DevServerClient.swift](../Sources/LumenRuntime/DevServerClient.swift) — `URLSessionWebSocketTask`, auto-reconnect через 2с при разрыве.
- В манифесте `"dev": true` активирует подключение к WS (production-бандлы без флага HMR не вызовут).
- Reload-стратегия: полное пересоздание `LumenPageViewController` через `nav.setViewControllers([newPage], animated: false)` + новый JSEngine. Это чище partial-cleanup (была crash на `_updateSafeAreaInsets` из-за dangling UIView ref) и держит heap чистым.
- State теряется (Promise.all загружает stories снова) — это MVP. Persistence через `lumen.storage` уже доступен.

**Что работает:** правишь `index.js`, сохраняешь → через ~300ms симулятор/железо показывает обновлённое дерево. Подтверждено E2E на симуляторе.

### P3.4 — `@lumen/cli` ✓ закрыт (session 006)

Пакет в [packages/lumen-cli/](../packages/lumen-cli/) с тремя командами:

- **`lumen init <name>`** — копирует [templates/default/](../packages/lumen-cli/templates/default/) в `<name>/`. Создаёт manifest.json (с подставленным name), index.ts (counter demo), tsconfig.json (strict, `lib: ["ES2020"]`, без DOM), lumen-types.d.ts (копия `@lumen/types`), README.
- **`lumen dev [path] [port]`** — обёртка над `startDevServer()` из [packages/lumen-cli/src/dev-server.ts](../packages/lumen-cli/src/dev-server.ts). Тот же файл переиспользует и [tools/dev-server.ts](../tools/dev-server.ts) как тонкий shim — один исходник, два entrypoint.
- **`lumen build [path]`** — `Bun.build` минифицирует entry → `dist/bundle.js`, пишет production `dist/manifest.json` (без `dev:true`, entry → `/bundle.js`). На counter-демо: **0.6 KB bundle за 6ms**.

E2E подтверждено: `lumen init demo` → `tsc --noEmit` clean → `lumen build` (0.6 KB) → `lumen dev` → симулятор открыл `http://localhost:8080` и показал counter `0` с кнопками `Tap me` / `Reset`.

Distributable: `bunx @lumen/cli init my-app` (когда опубликуем в npm).

### P3.5 — Inspector / DevTools (отложен, 2-3 сессии)

Дерево узлов, выделение слоёв в рантайме (как Safari Inspector → DOM). Полезно когда приложений станет несколько и без визуального обхода непонятно почему layout не как ожидаешь.

Реализация: shake-gesture в DEBUG → bottomSheet с tree-view `RenderNode`, тап выделяет CALayer (border).

---

## Phase 4 — Production polish & гейты Phase 0

### P4.1 — Manifest discovery в AddressBar ✓ закрыт (session 006)

`TabModel.commit()` теперь работает по схеме:

1. **Cache check** — `BundleProbeCache.shared.get(host:)` (TTL 24h). Hit → мгновенно открыть в нужном режиме, никаких network-запросов.
2. **Cache miss** — оптимистично выставить `mode = .web(url)` (WKWebView начинает грузить **сразу**), параллельно запустить `BundleLoader.probe()` в фоне.
3. **Probe вернулся `.fastApp`** — если пользователь ещё на том же URL → swap `mode = .fastApp(url)`, иначе игнорируем.
4. **Любой результат сохраняется в кэш** — повторный visit того же хоста мгновенный.

[BundleProbeCache](../Sources/LumenRuntime/BundleLoader.swift) — MainActor-isolated singleton, in-memory словарь. Persistent storage (UserDefaults) пока не нужен — TTL 24h хватает на сессию.

E2E проверено:
- `localhost:8080` → fast-app (probe находит manifest)
- `https://news.ycombinator.com` → WebView (нет manifest, WebView грузится без задержки)

Это и есть **«браузер с двумя движками»** из IDEA.md §1: для пользователя прозрачно, для разработчика fast-app — манифест на `/.well-known/lumen.json`.

**Известный артефакт:** на первый visit fast-app URL виден flash WebView ~50-100ms (на localhost) — пока probe не вернулся. Решение если станет заметным — gate 200ms перед `mode = .web(url)`, и если probe ответил раньше → не показывать WebView вообще.

### P4.2.a — Gestures (low-level) ✓ закрыт (session 006)

[GestureRouter](../Sources/LumenRuntime/GestureRouter.swift) — один на rootLayer, вешает все нужные UIGestureRecognizer'ы на hostView и через `CALayer.hitTest` находит target узла, у которого есть handler нужного типа.

Поддержка:
- `onTap(e)` — теперь с координатами `{x, y}` (backwards-compat — старый код без аргумента работает)
- `onDoubleTap(e)` — отдельный recognizer, single-tap require(toFail: doubleTap)
- `onLongPress(e)` — UILongPressGestureRecognizer (0.45s)
- `onPan(e)` — `e = {state, x, y, dx, dy, vx, vy}`, state: `'start'/'changed'/'ended'/'cancelled'`. Hit-test делается на `state == .began`, target layer captured for whole gesture cycle.
- `onSwipe(e)` — 4 recognizer'а (left/right/up/down), `e = {direction, x, y}`
- `onPinch(e)` — `e = {state, scale, velocity}`
- `onRotate(e)` — `e = {state, rotation, velocity}` (rotation в радианах)

Pinch и Rotate работают одновременно (типичный жест "двумя пальцами crop + rotate"), остальные взаимоисключающие — UIKit defaults.

**Финальная архитектура (после real-device debug):**
- Каждый recognizer через `gestureRecognizerShouldBegin` проверяет hit-test и **активируется только если под пальцем узел с нужным handler'ом**. Это убирает конкуренцию между типами без необходимости `require(toFail:)` — pan, swipe, pinch разведены по узлам.
- Hit-test — собственный recursive walker с явной конверсией координат. `CALayer.hitTest` от Apple на real device даёт артефакт «работает только в нижней половине».
- Применение размеров через `bounds + position`, не `frame` — иначе frame setter компенсирует transform и шарик не двигается.

**Известные ограничения:**
- DoubleTap recognizer убран — на real device воровал события у single tap через `require(toFail:)` и давал 300ms delay. Вернётся через custom `touchesBegan/Ended` + время-anchor когда понадобится.
- Distance-threshold для pan пока нет (UIPanGestureRecognizer не имеет встроенного). Если узел имеет и `onTap` и `onPan`, микро-движения пальца могут воровать tap. Решение когда дойдём — custom touch arbitration через UIResponder.

[Examples/DragLab/index.ts](../Examples/DragLab/index.ts) — демо: draggable шарик (pan + transform), Tap/Double/Long boxes, swipe-area, pinch+rotate area.

### P4.2.b — `transform` в style ✓ закрыт (session 006)

Добавлено в [ViewStyle.swift](../Sources/LumenRuntime/ViewStyle.swift) поле `Transform` со свойствами `translateX/Y`, `scale`, `scaleX/Y`, `rotate`. На apply — преобразуется в `CATransform3D` через `Translate → Rotate → Scale`. Это и **готовая база для P4.2.c (animations)** — `CABasicAnimation` на `transform` будет анимировать любое из этих значений off-main.

### P4.2.c — Animations ✓ закрыт (session 006)

Реализован вариант **D — AnimatedValue с `.set/.animateTo/.stop`** (как RN Animated). Главная фишка: значение хранится на native стороне в [AnimationManager](../Sources/LumenRuntime/AnimationManager.swift), анимации крутятся на render-сервере (backboardd) через `CABasicAnimation` / `CASpringAnimation`. JS-loop никак не участвует в кадрах — анимация не дрогнет даже если JS на 200ms залип.

JS API:
```ts
const x = animated(0)
const y = animated(0)

View({
  transform: {translateX: x, translateY: y},
  onPan: (e) => {
    if (e.state === 'start') { x.stop(); y.stop() }       // catch mid-flight
    if (e.state === 'changed') { x.set(e.dx); y.set(e.dy) }
    if (e.state === 'ended') {
      x.animateTo(0, {easing: 'spring'})                  // off-main spring
      y.animateTo(0, {easing: 'spring'})
    }
  },
})
```

**Поддерживаемые свойства:** `transform.translateX/Y/scale/scaleX/scaleY/rotate` и `opacity`. Остальное (`backgroundColor`, `cornerRadius`) — добавится по запросу через тот же механизм.

**Easing:** `linear / easeIn / easeOut / easeInOut / spring`. Spring — `CASpringAnimation(mass=1, stiffness=200, damping=18)`, duration = settlingDuration.

**Архитектура:**
- JS `animated(initial)` создаёт `AnimatedValue` с `__anim` sentinel id. Объект-носитель пробрасывается прямо в `transform.translateX` / `opacity`.
- [RenderNode.parseStyle](../Sources/LumenRuntime/RenderNode.swift) детектит `__anim` в transform/opacity, сохраняет `animId` отдельно от static value.
- [Renderer.applyVisualStyle](../Sources/LumenRuntime/Renderer.swift) — если у узла есть хоть один animated binding, делегирует transform+opacity в `AnimationManager.bindLayer(...)`. Иначе классический прямой apply.
- [AnimationManager](../Sources/LumenRuntime/AnimationManager.swift) держит `[animId: AnimNode(current, layerIds)]` и `[layerID: LayerState(animIds, staticParts)]`. На `.set/.animateTo/.stop` итерирует bound layer'ы и applies composed transform/opacity.
- `.stop()` читает `layer.presentation()`, декомпозирует translation/scale/rotation из transform-матрицы, сетит model = presentation, удаляет CABasicAnimation. Layer стоит ровно там же где был визуально — никакого jump'а.

**Lifecycle:**
- `removeMountTree` → `AnimationManager.unbindLayer` (cleanup при kind-swap / remove)
- Hot reload → `AnimationManager.reset()` в `FastAppHost.performReload`, чтобы id'ы новых AnimatedValue не наложились на stale-записи мёртвых layer'ов

**Demo:** [Examples/DragLab/index.ts](../Examples/DragLab/index.ts) — секция Snap-back ball. Орандевый шарик ездит за пальцем, на release летит spring'ом в (0,0). Touch на летящий шарик ловит его на лету (через `.stop()`), дальше можно тащить снова.

**Известные ограничения:**
- Spring параметры захардкожены — позже добавятся opts `{stiffness, damping, mass, velocity}`.
- Декомпозиция matrix → translation/scale/rotation работает чисто для 2D-аффинных трансформов (наш случай). Skew не поддерживается.
- Initial velocity для spring не пробрасывается из gesture-velocity — добавится когда понадобится «бросок» с инерцией.

Hooks-обёртка типа `<Animated.View>` не нужна — AnimatedValue работает на уровне примитива, прозрачно для `@lumen/core`.

### P4.3 — Bytecode caching (~1 сессия)

`JSScript.cacheBytecode(at:)` API. Pipeline:
1. Первая загрузка: получили `.js`, parse → JSC AST → store bytecode в `Library/Caches/lumen-bc/<sha256>.jsbc`.
2. Старт: смотрим в кэш по `sha256(entry.js)`. Если есть — `JSScript(bytecode:)`, иначе обычный путь.
3. Invalidation: новый hash → новый файл (старый удаляется по LRU).

**Acceptance:** cold start fast-app (bundle закэширован) < 50ms до first paint на симуляторе. < 150ms на iPhone 17 Pro.

### P4.4 — Real-device benchmark ✓ render-часть закрыта (session 004)

Запущено на iPhone 15 Pro Max (A17 Pro, ProMotion 120Hz), Release build, HN reader с 30 stories.

**Render per cell (полный JS+parse+reconcile+mount цикл):**

| Метрика | Цель (бюджет 120fps = 8.3ms) | Получили | Запас |
|---|---|---|---|
| avg | <8.3ms | 1.8ms | **4.6×** |
| p95 | <8.3ms | 2.5ms | **3.3×** |
| max | <8.3ms | 4.0ms | **2.1×** |

**Гипотеза IDEA.md ("JS → CALayer даёт near-native perf") подтверждена.** Main thread не bottleneck.

**Что насчёт display 60fps вместо 120 на скролле** — это **iOS ProMotion adaptive behavior**, не наша проблема. iOS снижает refresh rate когда не детектит "достаточно быстрого" движения; UIScrollView в стандартном режиме не всегда запрашивает full 120Hz. Если когда-то понадобится 120Hz hard guarantee — есть `UIScrollView` private API + `CADisplayLink preferredFrameRateRange`, но это полировка.

**Что ещё не измерено** (отложено):
- Cold start <150ms (нужен bytecode caching — P4.3)
- Cold start без кэша 4G <800ms
- JS heap typical app <20MB
- RSS таба <60MB
- Bridge call <10μs

Эти метрики важны для Phase 0 closure, но render perf — главный показатель — пройден.

### P4.5 — Permissions модель (~1 сессия)

Per-origin permissions (камера, гео, нотификации, accelerometer). API:
```js
const granted = await lumen.permissions.request('geolocation')
```

UI: системный prompt + наш «домен X запрашивает доступ к Y» (как Safari).

Хранение: `UserDefaults` с ключом `permission.<host>.<type>`.

---

## Backlog (идеи на потом, не приоритет)

### Observability / OpenTelemetry SDK

Встроенный в runtime сборщик логов / трейсов / метрик в OTLP-формате. Идея — `@lumen/telemetry` подключается одной строкой:

```ts
lumen.telemetry.configure({
  endpoint: 'https://otel-collector.example.com',
  service: 'hn-reader',
})
```

Что собираем:
- **Logs** — `console.log/warn/error` буферизуются и отправляются как `LogRecord`'ы
- **Traces** — spans на: page navigation, fetch call, mount/reconcile, gesture handler, JS exceptions
- **Metrics** — renderMs per cell, frame drops, JS heap size, network latency

Реализация: батчинг + periodic flush HTTP POST в OTLP/HTTP endpoint. На native стороне — можно расширить за счёт CADisplayLink-сэмплинга для frame drops.

Размер: ~500-1000 LOC. Дистрибутируется как опциональный пакет — приложения которые не подключают, не платят.

Польза огромная: разработчик подключает свой Grafana/Honeycomb/Tempo и видит реальные метрики продакшен-фастаппов без отдельной интеграции.

### Gesture optimization

Сейчас `RenderNode.parse` делает 7 JSValue lookups для каждого узла (onTap/onDoubleTap/.../onRotate). На больших деревьях (>500 узлов) даёт ~3-6ms парсинга. Оптимизация — итерировать JS keys узла один раз вместо 7 лукапов; либо markers (`hasGestures: true`) от компонент-builder'ов чтобы pre-filter. Запас перфоманса ~30% на gesture-light деревьях.

### Runtime TypeScript на клиенте

Открывать `.ts` / `.tsx` URLs напрямую из Lumen — клиент сам транспилирует.

**Сейчас работает через server-side** (dev-server использует `Bun.Transpiler`, prod-server должен делать аналог; `lumen build` будет делать AOT).

**Реализация на клиенте** когда понадобится:
- Опция A: встроить **sucrase** UMD bundle (~500KB) — industry-grade transpiler без typechecking. +50ms cold start на первый .ts файл.
- Опция B: написать **свой mini-stripper** (~200 LOC, ~5KB) — типажи, generics, `as`/`!`, `interface`, `type`, `enum`, `import type`. Покрывает ~80% TS features, без decorators/namespaces.

Use-case появится когда захочется "open any .ts URL anywhere" без полагания на server-side build. Сейчас не блокер — все production-сетапы имеют build step.

---

## Phase 5 (открытое) — что ещё нужно для продакшена

Пока не блокирует, но важно для реального продукта:

- **Permissions**: per-origin модель (gradio camera/notifications/geolocation на запрос)
- **Cookies**: shared между WebView и Fast Mode
- **Storage**: `lumen.storage` (key-value, AsyncStorage-подобный)
- **WebSocket**: для realtime приложений
- **Notifications**: APNs + local
- **Deep links**: универсальные ссылки
- **Share extension**: открыть URL из других приложений
- **Crash reporting**: для production
- **Settings sync** между устройствами
- **iCloud / signin**

---

## Открытые архитектурные вопросы

1. **JSC vs Hermes на Android.** Когда дойдём до Android — JIT не разрешён вне браузерных движков на iOS, но на Android можно V8/Hermes. Lумен на Android — отдельный проект.
2. **Какой продуктовый путь:** браузер (path A) vs SDK (path B) vs оба (path C). Это решение лучше принимать после P1.4 (real demo) когда увидим API в живом использовании.
3. **App Store policy.** Bundle-with-JS может вызвать review. Узнать через юриста до публичного релиза.
4. **DevTools.** Safari Web Inspector работает на JSContext, но Element Inspector нужен свой — отдельная задача.

---

## Лог принятых решений

- 2026-05-12 — Yoga отвергнут, минимальный Flex на Swift
- 2026-05-12 — CALayer напрямую, не UIView, для каждого узла
- 2026-05-12 — Один JSContext на main thread (на старте). P2.2 — план выноса.
- 2026-05-12 — Bundle = URL + manifest, не архив
- 2026-05-13 — Tests-target в xcodegen, минимальный Flex покрыт unit-тестами
- 2026-05-13 — ATS NSExceptionDomains для localhost (dev-only)
- 2026-05-13 — Native API через `JSEngine+Platform.swift`, паттерн `@convention(block)` + `MainActor.assumeIsolated`
- 2026-05-13 — Phase 1 закрыта: P1.1–P1.4 + routing + fullscreen работают в HN demo
- 2026-05-13 — Pattern `Renderer.detach()` — временное решение для `render`/`virtualList` coexistence; правильный фикс ждёт M6 (P2.1)
- 2026-05-13 — `fetch` через JS Promise-wrapper над void-блоком, потому что `@convention(block) → JSValue?` не биджится в JSC
- 2026-05-13 (session 002) — Router-pages используют UIView-обёртку на `safeAreaLayoutGuide.top`, а не прямой рендер в `view.layer`; VirtualList мoнтируется в тот же contentView
- 2026-05-13 (session 002) — `lumen.storage` поверх UserDefaults с префиксом `lumen.storage.`; per-origin модель отложена на Phase 5
- 2026-05-13 (session 002) — `engine.onLog → print` в FastAppHost для DEBUG: JS console.* виден в Xcode/simctl console-pty
- 2026-05-13 (session 003) — Reconciler MVP через `MountedNode`-параллельное дерево; index-based матчинг детей; LIS-move отложен до реального use-case с перестановкой
- 2026-05-13 (session 003) — `lumen.virtualList(config)` сначала вернулся как JS handle с `.reload()` (паттерн `_nativeVirtualList(config, handle)` + wrapper), затем заменён на `kind: 'virtualList'` в дереве — старый side-channel API удалён полностью
- 2026-05-13 (session 003) — kind-swap в reconciler теперь корректно перемонтирует virtualList overlay (баг: ранее `mountFresh` для swap'нутого узла не вызывался, только для его детей; для virtualList это значило что UICollectionView не появлялась)
- 2026-05-13 (session 003) — FlexLayout: cross-axis stretch теперь определяется только родителем (`node.style.alignItems`), не child'ом (`cs.alignItems`); это исправление позволило intrinsic-sizing работать для контейнеров без explicit cross
- 2026-05-13 (session 003) — Intrinsic shrink-to-fit для контейнеров без `flex` и без explicit dimension; image-нод пока без intrinsic (ждёт async load), допустимо
- 2026-05-13 (session 004) — `@lumen/core` — Flutter-style functional API (`View(props, ...children)`) выбран вместо JSX/htm; работает без build-step
- 2026-05-13 (session 004) — Signals: `Promise.resolve().then()` как fallback от `queueMicrotask` — последний в JSContext не вызывает callbacks
- 2026-05-13 (session 004) — HMR через page-recreation (`nav.setViewControllers`), а не partial cleanup; partial daw EXC_BAD_ACCESS в `_updateSafeAreaInsets`
- 2026-05-13 (session 004) — `NSAllowsLocalNetworking: true` в ATS для подключения симулятора/iPhone к Mac LAN dev-server'у по http
- 2026-05-13 (session 004) — P4.4 render-метрика: avg 1.8ms / p95 2.5 / max 4 на iPhone 15 Pro Max → main thread не bottleneck, гипотеза подтверждена
- 2026-05-13 (session 005) — TypeScript для приложений выбран через server-side transpile (Bun.Transpiler в dev-server); runtime TS в Lumen-клиенте отложен в backlog
- 2026-05-13 (session 005) — `tsconfig` для Lumen-апп: `lib: ["ES2020"]` обязателен — иначе DOM globals `Text`/`Image` конфликтуют с нашими компонентами
- 2026-05-13 (session 006) — `@lumen/cli` использует `Bun.build` (не esbuild напрямую) — оно уже включено в bun, нет внешних deps
- 2026-05-13 (session 006) — `tools/dev-server.ts` стал shim'ом на `packages/lumen-cli/src/dev-server.ts` — один исходник, монорепо без дублирования
- 2026-05-13 (session 006) — Manifest discovery: оптимистично открываем WebView, swap на FastApp на позднем .fastApp ответе; кэш per-host TTL 24h (in-memory MVP)
- 2026-05-13 (session 006) — Animations API выбран как **D (AnimatedValue с explicit .set/.animateTo/.stop)** вместо declarative B — главный аргумент: контроль над interrupt (drag mid-flight)
- 2026-05-13 (session 006) — Gestures: 1 GestureRouter на rootLayer, не N recognizer на N layer (effizient). 7 типов: tap/doubleTap/longPress/pan/swipe/pinch/rotate. Pan/Pinch/Rotate работают с state-машиной `start/changed/ended/cancelled`
- 2026-05-13 (session 006) — `transform: {translateX/Y, scale, rotate}` в style. Реализовано через `CATransform3D` — даст бесплатно animations через `CABasicAnimation(keyPath: "transform")`
- 2026-05-13 (session 006) — `CALayer.hitTest` от Apple ведёт себя нестабильно на реальном устройстве (work-only-on-bottom-half артефакт); заменён на custom recursive walker с явной конверсией координат
- 2026-05-13 (session 006) — `UITapGestureRecognizer` для double-tap конкурирует с single tap на real device через `require(toFail:)` — даёт 300ms delay и event-stealing. DoubleTap пока убран из router'а; вернётся через custom `UIResponder.touchesBegan/Ended` если понадобится
- 2026-05-13 (session 007) — Финальная архитектура gestures: `gestureRecognizerShouldBegin` фильтрует recognizers по hit-test (pan активен только на узле с onPan, etc), `require(toFail:)` не используется — конкуренции нет, каждый жест на «своих» узлах
- 2026-05-13 (session 007) — Animations API дизайн: выбран **D (AnimatedValue с .set/.animateTo/.stop)** вместо declarative B — главное обоснование от пользователя: interrupt mid-flight (drag хватает летящий шарик)
- 2026-05-13 (session 008) — Animations реализованы: AnimatedValue живёт на native стороне ([AnimationManager](../Sources/LumenRuntime/AnimationManager.swift)), JS только pushет команды через `lumen._animValue.*`. Renderer композирует transform + opacity из static + animated current values.
- 2026-05-13 (session 008) — `.stop()` декомпозит presentation transform-матрицу (m41/m42 для translation, sqrt от m11²+m12² для scale, atan2(m12,m11) для rotation) — даёт корректный «freeze where you see».
- 2026-05-13 (session 008) — Hot reload должен дёргать `AnimationManager.reset()` перед setupEngine: AnimatedValue id'ы стартуют с 1 в новом контексте, без reset наложились бы на stale-записи мёртвых layer'ов.
- 2026-05-13 (session 009) — **Phase 5 стартовала**: dogfood-направление — переписать browser shell на самом Lumen. Это требует расширения runtime'а примитивами (TextInput → ScrollView → Blur → tabs API), потом shell-as-fast-app.
- 2026-05-13 (session 009) — TextInput реализован через native UITextField как overlay (паттерн VirtualList): kind: 'textInput', LumenTextField subclass с padding-overrides, controlled-value (textField.text сетится только если изменилось, чтобы каретка не прыгала).
- 2026-05-13 (session 009) — ScrollView реализован через **nested Renderer**: UIScrollView содержит contentView, чей CALayer — rootLayer для inner Renderer'а в режиме `.scrollContent` (height: ∞). После layout `computedContentHeight()` отдаёт max(child.frame.maxY) → contentSize.
- 2026-05-13 (session 009) — SafeArea — **reactive через signal'ы в CoreFramework**, не статические getter'ы. Native `viewSafeAreaInsetsDidChange` дёргает `lumen._updateSafeArea` → пушит в `_saT/_saB/_saL/_saR` signals → автоматический re-render компонентов читающих `lumen.safeArea.bottom`.
- 2026-05-13 (session 009) — Лендинг Lumen-на-Lumen добавлен в backlog как showcase-фастапп — позже как наследник готовности ScrollView+SafeArea+Blur. Дизайн обсудить отдельно перед реализацией.

---

## Текущая стратегия (после session 001)

**Технический фокус (короткий)** — закрыть стабилизационный спринт S1, чтобы дальнейшие изменения шли на твёрдом основании. Главная задача после стабилизации — **M6 Reconciler (P2.1)**, потому что он разблокирует:
- сосуществование render + virtualList без хаков,
- off-main (P2.2),
- realistic update-перформанс,
- JS-фреймворк (P3.1), который опирается на reactive re-render.

**Продуктовый вопрос на потом** — после P3.1 (HN на JSX+signals) посмотреть на API в живом коде и решить продуктовый путь (A/B/C/D из IDEA.md §4). Слишком рано выбирать сейчас — мало кода писали в этой парадигме.

**Что не делаем сейчас, хотя руки чешутся:**
- Android (отдельный проект, см. открытый вопрос #1)
- DevTools / Inspector (отложен до P3.5 — без него можно жить)
- WebSocket / Notifications / cookie sharing (см. Phase 5)
- Свой layout-движок поверх Yoga (минимальный Swift Flex уже покрыл наши кейсы; миграция — только когда нужны flex-wrap/shrink/position-absolute)
