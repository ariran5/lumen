# Session 001 — 2026-05-13: Native APIs, fetch, routing, full-screen

> Этот файл — снимок состояния проекта в конце сессии. Прочти его перед следующей сессией, чтобы быстро вкатиться. Хронология коммитов: `git log --oneline`. Архитектурный план: [docs/ROADMAP.md](../docs/ROADMAP.md). Концепция: [docs/IDEA.md](../docs/IDEA.md).

---

## TL;DR

В этой сессии Lumen из «JS-движка с одним экраном» стал **настоящим браузером с двумя движками**:

- Адресная строка определяет тип сайта по манифесту (`/.well-known/lumen.json`)
- Обычный URL → `WKWebView`, fast-app URL → `FastAppHost`
- Внутри fast-app — настоящий `UINavigationController` с iOS push/pop, нативным swipe-back, native nav bar
- JS API для всего пакета: `lumen.render`, `lumen.virtualList`, `lumen.router.push/pop`, `lumen.bottomSheet`, `lumen.alert`, `lumen.haptics`, `setTimeout`, `fetch`
- Внешний dev-flow: `bun tools/dev-server.ts Examples/HN` → ввёл URL в Lumen → реальный HN-ридер

**Главный результат:** работает end-to-end. Тап по новости в HN → push на detail page → tap на comments → ещё push → swipe-back возвращает.

---

## Что добавилось в коде

### Новые файлы

| Путь | Назначение |
|---|---|
| [Sources/LumenRuntime/BundleLoader.swift](../Sources/LumenRuntime/BundleLoader.swift) | Probe и load manifest+entry для fast-app |
| [Sources/LumenRuntime/JSEngine+Platform.swift](../Sources/LumenRuntime/JSEngine+Platform.swift) | bottomSheet / alert / haptics / setTimeout |
| [Sources/LumenRuntime/JSEngine+Fetch.swift](../Sources/LumenRuntime/JSEngine+Fetch.swift) | `fetch` global через Promise-wrapper + `_nativeFetch` ObjC-block |
| [Sources/LumenRuntime/JSEngine+Router.swift](../Sources/LumenRuntime/JSEngine+Router.swift) | `lumen.router.push/pop/popToRoot/setTitle` |
| [Sources/LumenRuntime/BottomSheetViewController.swift](../Sources/LumenRuntime/BottomSheetViewController.swift) | `UISheetPresentationController` с Lumen-контентом |
| [Sources/LumenRuntime/LumenPageViewController.swift](../Sources/LumenRuntime/LumenPageViewController.swift) | VC для одной страницы fast-app, держит свой Renderer |
| [Sources/LumenRuntime/ImageLoader.swift](../Sources/LumenRuntime/ImageLoader.swift) | URLSession + URLCache + NSCache + CGImageSource downsampling |
| [Sources/LumenRuntime/TopViewController.swift](../Sources/LumenRuntime/TopViewController.swift) | Поиск top-most presented VC для модалок |
| [Sources/LumenShell/FastAppHost.swift](../Sources/LumenShell/FastAppHost.swift) | UIViewControllerRepresentable, обёртка `UINavigationController` |
| [tools/dev-server.ts](../tools/dev-server.ts) | Bun HTTP сервер для отдачи fast-app папки |
| [Examples/HelloApp/](../Examples/HelloApp/) | Демо: bottomSheet + Pressable + haptics |
| [Examples/HN/](../Examples/HN/) | Hacker News reader с virtualList + router + favicons |

### Расширенные файлы

- `RenderNode` — добавлены `onTap: JSValue?`, `source: String?` (image), `image` kind
- `ViewStyle` — `contentMode` для image, парсер styles
- `Renderer` — `init(hostView:)` устанавливает tap gesture, `detach()` метод
- `TabModel` — `mode: TabMode` enum (`.start`/`.web`/`.fastApp`)
- `BrowserView` — рендерит `FastAppHost` инлайн, fullscreen
- `AddressBar` — home button, цвет иконки по моде

### Удалённые файлы

- `Sources/LumenShell/RemoteFastAppView.swift` — заменён на `FastAppHost`

---

## Архитектура fast-app

```
BrowserView (SwiftUI)
├── AddressBar  (textfield + home button)
└── ZStack (.frame(maxHeight:.infinity), .ignoresSafeArea(.bottom) для fast-app)
    └── FastAppHost (UIViewControllerRepresentable)
        └── UINavigationController
            ├── LumenPageViewController (root)
            │   ├── view.layer ← Renderer rootLayer
            │   │   └── CALayer tree (от lumen.render)
            │   └── view ← VirtualListView (от lumen.virtualList) — после detach
            ├── LumenPageViewController (pushed) ← router.push
            └── LumenPageViewController (deeper)
```

Каждая страница имеет:
- Свой `Renderer` (bound to its view)
- Свой gesture recognizer
- Tap handlers map (CALayer → JSValue)
- Onpop callback в JS

JSEngine один на весь FastApp, разделяется между страницами.

---

## API surface для JS-разработчика

```js
// Render
lumen.render(tree)
lumen.virtualList({ count, itemHeight, render })

// Routing
lumen.router.push({ title, render, onPop })
lumen.router.pop()
lumen.router.popToRoot()
lumen.router.setTitle(t)

// Native UI
lumen.bottomSheet({ content, height, onClose })
lumen.alert({ title, message, onOK })
lumen.haptics('light'|'medium'|'heavy'|'soft'|'rigid'|'success'|'warning'|'error')

// Standard
setTimeout(fn, ms)
clearTimeout(id)
fetch(url, options).then(r => r.json())
console.log/info/warn/error
```

Globals: `lumen.platform = 'ios'`, `lumen.version = '0.0.1'`, `Promise`.

---

## Баги, решённые в этой сессии

### 1. Crash в accessibility scan (`objc_msgSend` at 0x10)

Симптом: app падает через ~2 секунды после открытия fast-app.

Причина: `UITapGestureRecognizer.target` ссылался на `TapProxy`, который Renderer хранил в `var tapProxy`. При деинициализации Renderer'а проxy умирал, но recognizer оставался привязан к view. Accessibility-сканер iOS периодически проходит по subviews, дёргает `valueForKey:` на recognizer, упирается в dangling target.

Фикс: `objc_setAssociatedObject(recognizer, &key, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)`. Proxy теперь живёт ровно столько же, сколько recognizer.

Коммит: `bbf96c1` (хотя сам фикс в более раннем `Cell taps + full-screen polish` — нужно искать).

### 2. `Renderer` затирал `VirtualListView`

Симптом: `lumen.virtualList` срабатывал (логи показывали корректный mount), но визуально оставался placeholder. Через 0.1 секунды экран снова показывал placeholder вместо списка.

Причина: после `lumen.virtualList` следующий `viewDidLayoutSubviews` на `LumenPageViewController` вызывал `renderer?.relayout()` с сохранённым `lastTree` (placeholder). Relayout делал `rootLayer.sublayers?.forEach { removeFromSuperlayer() }` — что **включало** слой UICollectionView, потом монтировал placeholder заново.

Фикс: `Renderer.detach()` — clears `lastTree` и sublayers и tapHandlers. `installVirtualListBridge` вызывает `detach` на renderer'е текущей страницы перед добавлением UICollectionView.

### 3. Promise.all с параллельными fetch — **починено в S1.3 (не воспроизвелось)**

Симптом из этой сессии: `Promise.all(ids.map(id => fetch(...)))` якобы зависал, sequential работал. Workaround был sequential loader.

В диагностике S1.3 баг не воспроизвёлся: Promise.all с 5 и с 20 параллельными запросами к HN Firebase API завершается за ~0.8s, все ответы корректно резолвятся, порядок результатов сохраняется. URLSession `httpMaximumConnectionsPerHost = 6` отвечает за батчинг.

Возможные причины расхождения:
- Network/DNS глюк во время прошлой сессии (HN Firebase подтормаживал).
- `loadSequentially` имел свой баг, который маскировал реальный hang как hang Promise.all.
- Какое-то промежуточное состояние fetch bridge до его финального fix'а.

HN demo переключен на `Promise.all` с 30 stories. Sequential workaround удалён.

### 4. ObjC-block с return type `JSValue?` не биджится в JSC

Симптом: `typeof fetch === 'undefined'` в JS, при том что `installFetchBridge` отрабатывал.

Причина: `@convention(block) (...) -> JSValue?` не конвертится правильно для JS-bridge через ObjC. Block молча отбрасывается, global не появляется.

Фикс: native block теперь `-> Void`, принимает `resolve` и `reject` JSValues. Сверху JS-обёртка строит Promise:

```js
globalThis.fetch = function(url, options) {
  return new Promise(function(resolve, reject) {
    _nativeFetch(url, options || null, resolve, reject)
  })
}
```

### 5. Cell taps в virtualList не работали

Симптом: тап по строке HN ничего не делал.

Причина: `LumenCell` создавал renderer через `Renderer(rootLayer: contentView.layer)` — это инициализатор БЕЗ gesture recognizer (только `Renderer(hostView:)` его ставит).

Фикс: `Renderer(hostView: contentView)`. Gesture recognizer теперь на cell'е contentView, координируется с UICollectionView через делегатов жестов.

---

## Известные ограничения и продукт-долги

1. ~~**`Promise.all` параллельные fetch виснут.**~~ Не воспроизводится; HN на parallel fetch'ах работает.
2. **`lumen.render` + `lumen.virtualList` не сосуществуют** — `detach` одноразовый. Если JS после `virtualList` вызовет `render`, virtualList пропадёт. M6 reconciler даст clean решение.
3. **FlexLayout без intrinsic-sizing** — `auto` height у контейнера не вычисляется из детей. Обходится явным `height` (видно в HelloApp/HN).
4. **Detail-страница HN** — layout слегка наезжает (avatar поверх title) из-за top inset под nav bar. Нужен `additionalSafeAreaInsets` или `view.layoutMargins`.
5. **WebView режим** не тестировался в этой сессии после refactor. Может быть сломан.
6. **Reconciler (M6) ещё не реализован** — каждый `lumen.render` пересоздаёт всё CALayer-дерево.
7. **Off-main computation (P2.2)** — всё ещё на main thread.

---

## Где лежит что

```
alternativeRenderer/
├── App/                          ← iOS app entry point
├── Sources/
│   ├── LumenLayout/              ← FlexLayout.swift (минимальный Flexbox в Swift)
│   ├── LumenRuntime/             ← JS engine, renderer, native bridges
│   │   ├── JSEngine.swift        ← JSContext wrapper
│   │   ├── JSEngine+Render.swift ← lumen.render
│   │   ├── JSEngine+VirtualList.swift ← lumen.virtualList
│   │   ├── JSEngine+Platform.swift ← bottomSheet/alert/haptics/setTimeout
│   │   ├── JSEngine+Fetch.swift  ← fetch global
│   │   ├── JSEngine+Router.swift ← lumen.router
│   │   ├── RenderNode.swift      ← парсер JSValue→Swift struct
│   │   ├── ViewStyle.swift       ← структуры стилей
│   │   ├── Renderer.swift        ← mount CALayer-дерево, tap gesture
│   │   ├── VirtualList.swift     ← UICollectionView обёртка
│   │   ├── BundleLoader.swift    ← manifest + entry загрузка
│   │   ├── BottomSheetViewController.swift
│   │   ├── LumenPageViewController.swift ← страница в nav stack
│   │   ├── ImageLoader.swift     ← image decode + cache
│   │   ├── TextMeasure.swift     ← CoreText measure
│   │   └── TopViewController.swift
│   └── LumenShell/               ← browser chrome
│       ├── BrowserView.swift     ← главный SwiftUI view
│       ├── AddressBar.swift
│       ├── TabModel.swift        ← mode: .start/.web/.fastApp
│       ├── WebTabView.swift      ← WKWebView wrapper
│       ├── FastAppHost.swift     ← UINavigationController wrapper
│       ├── DemoFastTabView.swift ← inline demo (старый)
│       ├── VirtualListDemoView.swift ← M8 spike (старый)
│       └── JSPlaygroundView.swift
├── Tests/
│   └── FlexLayoutTests.swift     ← 7 tests passing
├── Examples/
│   ├── HelloApp/                 ← 3 row Pressable demo
│   │   ├── manifest.json
│   │   └── index.js
│   └── HN/                       ← Hacker News reader
│       ├── manifest.json
│       └── index.js
├── tools/
│   └── dev-server.ts             ← Bun static server
├── docs/
│   ├── IDEA.md                   ← концептуальное обоснование
│   ├── PLAN.md                   ← оригинальный Phase 0 план
│   └── ROADMAP.md                ← живой план приоритетов
├── sessions/
│   └── 001-2026-05-13-routing-fullscreen.md ← этот файл
├── project.yml                   ← XcodeGen source of truth
└── App/Info.plist                ← generated by xcodegen (gitignored)
```

---

## Команды для запуска

```bash
# Сгенерировать Xcode проект
xcodegen generate

# Собрать
xcodebuild -project Lumen.xcodeproj -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Dev-server в одном терминале
bun tools/dev-server.ts Examples/HN 8080

# Запустить с автооткрытием URL в другом
xcrun simctl launch "iPhone 17 Pro" com.lumen.browser \
  -url http://localhost:8080
```

Запускать iPhone 17 Pro Simulator. macOS 26 Tahoe, Xcode 26.0.1, Swift 6.2.

---

## Что дальше (приоритеты)

В порядке убывания пользы / возрастания сложности:

### 1. Top inset для router-pages (тривиально, 30 минут)

Detail page контент наезжает на nav bar. Нужно установить `additionalSafeAreaInsets` или использовать `view.safeAreaLayoutGuide` в `LumenPageViewController`.

### 2. Fix `Promise.all` параллельных fetch (несколько часов)

Отладить bridge с multiple in-flight requests. Возможно нужен dispatch_semaphore или отдельная queue per fetch.

### 3. M6 Reconciler (1-2 дня)

Keyed diff между prev/next tree. Решит проблему `render` + `virtualList` coexistence, ускорит обновления, foundation для off-main computation.

### 4. P3.1 `@lumen/core` JS-фреймворк (несколько дней)

Signals + h() + hooks. Чтобы писать `<Counter />` а не дерево объектов вручную.

### 5. P4.4 Real-device benchmark (M10) — нужен реальный iPhone

Симулятор capped at 60Hz. Подтвердить 120fps на ProMotion-устройстве — это последний gate Phase 0.

### 6. Hot reload в dev-server (P3.3)

WebSocket в `tools/dev-server.ts`, app перевызывает eval на каждое изменение файла.

---

## Артефакты сессии

8 коммитов сегодня:
```
bbf96c1 Cell taps + full-screen polish
2280d87 Routing + full-screen FastApp (path A: real browser)
... (P1.2/P1.3/P1.4) Image + fetch + HN demo
... (P1.1) onTap on any node
... M9-lite + native API bridges: external dev flow works
```

Все билды чистые, тесты (7 FlexLayout) проходят.

Сессия закончилась с **рабочим HN reader, полноэкранным режимом, native push/pop, tap detection**. Дальнейшее обсуждалось — `Promise.all`, M6, JS framework.
