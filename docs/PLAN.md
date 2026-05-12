# Lumen — план реализации Phase 0

> Снимок плана на 2026-05-12. Цель Phase 0 — **доказать одну гипотезу**: можно ли получить стабильные 120 fps на 10k-list через JS-driven CALayer-рендеринг. Если на M10 не выходим — стоп, переосмысление. См. контекст и обоснование в [IDEA.md](IDEA.md).

---

## Окружение

Подтверждено на 2026-05-12:

- macOS 26.0.1 (Tahoe)
- Xcode 26.0.1
- Swift 6.2
- Node 22.15.1, Bun 1.1.30

Дополнительно нужно поставить:
- `brew install xcodegen`
- `bun add -g esbuild` (после M0)

---

## Структура проекта

```
alternativeRenderer/
├── project.yml                    # XcodeGen — проект как код
├── Package.swift                  # SPM для shared модулей
├── App/                           # iOS/macOS app target
│   ├── LumenApp.swift
│   ├── ContentView.swift
│   └── Info.plist
├── Sources/
│   ├── LumenShell/               # адресная строка, табы, WKWebView
│   ├── LumenRuntime/             # JS-движок, reconciler, renderer
│   └── LumenLayout/              # Yoga C++ обёртка
├── Tests/
│   └── LumenRuntimeTests/
├── Examples/
│   └── BasicList/                # demo fast-app
│       ├── package.json
│       ├── manifest.json
│       └── src/index.js
├── tools/
│   └── lumen-cli/                # минимальный bundler на Bun
│       └── src/build.ts
└── docs/
    ├── IDEA.md
    └── PLAN.md
```

---

## Milestones

### M0 — Скелет проекта (1 день)

**Что делаем:**
- `project.yml` с двумя app-таргетами (iOS, macOS), оба линкуют `LumenRuntime`
- `Package.swift` с тремя локальными модулями: `LumenShell`, `LumenRuntime`, `LumenLayout`
- Подключение Yoga через SPM (`facebook/yoga`, SwiftPM-таргет с версии 3.1)
- Стартовый `ContentView.swift` показывает "Hello Lumen"
- `.gitignore`, `git init`, первый коммит

**Acceptance:** `xcodebuild -scheme Lumen build` собирается без ошибок на iOS Simulator и macOS.

---

### M1 — Браузер-оболочка (2 дня)

**Что делаем:**
- `LumenShell/AddressBar.swift` — `TextField` для URL
- `LumenShell/WebTabView.swift` — обёртка над `WKWebView`
- `LumenShell/TabModel.swift` — `@Observable` модель таба
- Простой `NavigationStack`, один таб
- Нормализация ввода: `apple.com` → `https://apple.com`

**Acceptance:** Запуск, ввод `https://news.ycombinator.com`, прокрутка — работает как Safari. Без табов, без истории — только адрес и страница.

---

### M2 — JavaScriptCore: execution layer (2 дня)

**Что делаем:**
- `LumenRuntime/JSEngine.swift` — обёртка над `JSContext`
- Регистрируем `console.log`, `console.error`, `setTimeout`, `setInterval`
- `globalThis.lumen.platform = "ios"` для feature detection
- `LumenRuntime/JSEngine+Bytecode.swift` — `JSScript.cacheBytecode(at:)` для предкомпиляции
- Inspectable flag: `JSContext._isInspectable = true` в debug

**Acceptance:**
- Hidden screen "JS Playground": multiline TextEditor + Run. `for (let i = 0; i < 1e6; i++) {}` за <50ms.
- Safari → Develop → Simulator показывает JSContext, breakpoints работают.

---

### M3 — Yoga layout (2 дня)

**Что делаем:**
- `LumenLayout/YogaNode.swift` — Swift-обёртка над YGNode
- API: `node.flexDirection`, `padding`, `width`, `height`, `child(at:)`, `addChild`, `calculateLayout(width:height:)`
- Юнит-тесты: row из 3 квадратов с правильными координатами

**Acceptance:** `XCTAssertEqual(node.layout.frame, CGRect(...))` для 5 базовых раскладок (row, column, flex:1, padding, justify-content).

---

### M4 — Renderer: узел `View` (3 дня)

**Что делаем:**
- `LumenRuntime/Node.swift` — enum `NodeType { case view, text, image, scroll, pressable }` (пока только view)
- `LumenRuntime/RenderNode.swift` — Swift-структура с layout-нодом, стилями (`backgroundColor`, `borderRadius`, `opacity`)
- `LumenRuntime/Renderer.swift` — `mount(node:in:) -> CALayer`, `update(layer:from:to:)`
- Корневой `CALayer` живёт внутри `UIView`-контейнера на FastTab
- JS API: `lumen.render(tree)` где `tree = {type: 'view', style: {...}, children: [...]}`

**Acceptance:** JS-код создаёт 100 цветных квадратов в row+wrap, рисуется корректно, layout считается Yoga.

---

### M5 — Text node (2 дня)

**Что делаем:**
- `CATextLayer` с `contentsScale = UIScreen.main.scale` (иначе замыленный текст)
- Измерение через `CTFramesetterSuggestFrameSizeWithConstraints` → measure-callback в Yoga
- Поддержка: `fontSize`, `fontWeight`, `color`, `numberOfLines`, `textAlign`

**Acceptance:** Lorem ipsum c `numberOfLines: 3` показывает правильное усечение, измерение работает в Yoga.

---

### M6 — Reconciler (3 дня)

**Что делаем:**
- `LumenRuntime/Reconciler.swift` — keyed diff между prev/next view-tree
- Алгоритм: одноуровневое сопоставление по `key`, рекурсивно
- Список патчей: `Patch.insert/remove/move/updateProps`
- JS API: `lumen.render(tree)` теперь diff'ает, а не пересоздаёт
- Простейшая реактивность: `lumen.signal(initialValue)` + автоматический re-render при изменении

**Acceptance:** Бенч 1000 узлов, insert в середину, замер времени diff+apply. Цель <2ms.

---

### M7 — ScrollView + Pressable + Image (2 дня)

**Что делаем:**
- `ScrollView` обёртка `UIScrollView`, content size из Yoga
- `Pressable` — `UITapGestureRecognizer` через ассоциированную ссылку на CALayer, callback в JS
- `Image` — `CGImageSource` с downsampling на background queue, потом `layer.contents`
- JS API: `onTap`, `source: {uri: "..."}`

**Acceptance:** Скролл с 50 элементами, каждый с image + text + tap-handler, console.log при тапе.

---

### M8 — Виртуализация списка (2 дня) — КРИТИЧЕСКИЙ ШАГ

Без этого 10k items не вытянем.

**Что делаем:**
- `VirtualList` компонент: рендерит только видимые + buffer
- В JS: `lumen.virtualList({items, itemHeight, renderItem})`
- Под капотом: `UICollectionView` с `UICollectionViewCompositionalLayout`, cells оборачивают CALayer-tree
- Recycling: при scroll переиспользуем CALayer вместо пересоздания

**Acceptance:** 10k items, «бросание» скролла. Instruments Time Profiler: main thread <8ms на кадр.

---

### M9 — Bundle loader (1 день)

**Что делаем:**
- `LumenRuntime/BundleLoader.swift` — URLSession качает `.js`, передаёт в JSEngine
- Манифест: `https://<host>/.well-known/lumen.json` → `{entry: "https://.../app.js"}`
- В `WebTabView`: при загрузке URL параллельно дёргаем манифест; если есть → переключаемся на FastTab
- Кэш bundle в `URLCache` + ETag

**Acceptance:** Локальный сервер (`bun --cors src/`) отдаёт `manifest.json` + `app.js`. Ввод `http://localhost:8080` → fast mode.

---

### M10 — Demo + benchmark gate (2 дня)

**Что делаем:**
- `Examples/BasicList/src/index.js` — Twitter-подобная лента: virtual list 10k карточек (аватар + текст + like)
- `tools/lumen-cli/src/build.ts` на Bun — минимальный бандлер: esbuild → один JS-файл
- Замеры на iPhone 15 Pro (или Simulator + Instruments):
  - **Cold start** до first paint
  - **FPS в скролле** (Instruments Core Animation)
  - **RSS** через `task_info`

**Acceptance — гейт:**

| Метрика | Цель | Что делаем, если не вышли |
|---|---|---|
| FPS scroll, p95 | ≥110 на ProMotion | Time Profiler. Если упёрлись в JS — больше виртуализации в Swift. Если в CA — слишком много слоёв, нужно слияние |
| Cold start (cached) | <200ms | Bytecode не применился? Проверить `cacheBytecode` |
| Memory RSS | <80MB | Retain cycles, image cache |
| Bridge call p99 | <50μs | Если хуже — `JSExport` → C-API |

Все четыре зелёные → Phase 0 пройдена, идём в Phase 1. Хотя бы одна красная и непонятно как чинить → стоп, обсуждение.

---

## Срок и риск

**Phase 0 ≈ 20 рабочих дней (4 недели)** одного разработчика, умеющего в Swift и не пугающегося C++ interop.

Самые рискованные шаги:
- **M4–M5** — много мелочей CALayer (contentsScale, geometryFlipped, anchorPoint)
- **M8** — здесь либо доказываем гипотезу, либо нет

---

## Точка выбора перед стартом

Два варианта зайти в Phase 0:

1. **Полный пайплайн M0 → M10.** Чистая архитектура с нуля, всё нормально устроено. Через 4 недели имеем POC + понимание, что хорошо/плохо.
2. **Spike M8 в отрыве.** Пропускаем M0–M7, делаем тонкую вертикаль: захардкоженный JS, 10k items в `UICollectionView`, замер. Экономит 1–2 недели, если хотим максимально быстро проверить главную гипотезу до построения архитектуры.

**Текущая рекомендация: (2).** До похода в полноценную архитектуру нужно знать, что числа сходятся. M0 никуда не денется через несколько дней.

---

## Phase 1+ (после успешной Phase 0)

Заметки на будущее, чтобы не забыть. Подробно не расписаны.

**Phase 1 — MVP runtime (3 месяца)**
- Полный набор узлов (~15 типов)
- Signals + hooks + router
- `fetch`, `localStorage`, `crypto`, `WebSocket`
- Bytecode pipeline
- CLI `lumen init/dev/build`
- 3–5 demo-сайтов
- Manifest + discovery
- Safari Inspector интеграция

**Phase 2 — Browser product (3 месяца)**
- Tabs, история, закладки, sync
- Permissions UI
- Settings, downloads, find-in-page
- Beta для разработчиков

**Phase 3 — Android & расширение (6 месяцев)**
- Android-порт: Kotlin + Hermes + Yoga + Android View
- Camera, notifications, deep links, share extension
- Marketplace fast-сайтов

**Phase 4 — Эволюция**
- Web-fallback (тот же bundle рендерится в DOM на десктопах без Lumen)
- AI-агенты как first-class клиенты (отдельный URL-формат для машинного рендера)
