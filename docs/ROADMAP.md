# Lumen — roadmap (живой документ)

> Этот файл фиксирует **текущее состояние** и **что дальше**, чтобы между сессиями ничего не терялось. Концептуальная основа в [IDEA.md](IDEA.md), оригинальный Phase 0 план в [PLAN.md](PLAN.md). Обновляется по мере прогресса.

---

## Где мы сейчас (snapshot)

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

### Архитектурные решения, зафиксированные по дороге

- **Yoga отвергнут в пользу своего Flexbox** на Swift. Yoga = C++20 пакет, SPM-импорт в Swift через C++ headers нетривиален. Свой ~250 LOC покрыл наши кейсы. Свапнуть на Yoga можно когда понадобятся фичи которых нет (flex-wrap, shrink, basis, position absolute).
- **Один JSContext = один поток** (пока main). JSC thread affinity ограничивает свободу. См. P2.2 как план выноса.
- **CALayer напрямую, не UIView.** UIView'ы только на границах (host containers, cells). Внутри — голые CALayer'ы для эффективности.
- **Bundle = URL + manifest**, не упакованный архив. Простая структура `/.well-known/lumen.json` + entry-скрипт. Архив (`.lumen` файлы) — будущая оптимизация.

---

## Phase 1 — Interactive apps (текущий)

Цель: можно написать настоящее приложение, которое реагирует на пользователя и показывает реальные данные.

### P1.1 — Pressable + onTap (СЛЕДУЮЩИЙ ШАГ)

- Добавить `pressable` kind в `RenderNode`
- `onTap: JSValue?` — сохраняется при парсинге
- `Renderer` хранит мапу `CALayer → JSValue` для тап-хендлеров
- `UITapGestureRecognizer` на host UIView, hit-test через `rootLayer.hitTest(point)`, walk superlayers до ближайшего Pressable
- Демо в HelloApp: тап по ряду → открывает bottom sheet с деталями

**Acceptance:** ряд в HelloApp реагирует на тап, фидбэк с haptic, открывает sheet с правильными данными.

### P1.2 — Image node

- `image` kind с props `source: {uri, width, height}` или `source: 'asset://name'`
- `CGImageSource` с downsampling на background queue
- LRU-кеш в `URLCache` для удалённых картинок
- `layer.contents = decodedImage` на main после декода

**Acceptance:** загрузить 20 картинок 1024×1024, scroll плавно, кэш переиспользуется.

### P1.3 — fetch global

- `fetch(url, options)` возвращает Promise
- Под капотом — `URLSession.shared.data(for:)` на background
- Resolve в main thread JS-Promise
- Поддержка GET / POST / headers / body / json
- Базовый `Response` объект с `.json()`, `.text()`, `.status`

**Acceptance:** `fetch('https://api.github.com/repos/...')` возвращает данные, JS их рендерит.

### P1.4 — Real demo: Hacker News reader

- Один экран: `lumen.virtualList` со списком top stories из HN API
- Тап по item → bottom sheet с деталями + комменты
- Картинки favicon доменов
- Pull-to-refresh

Это smoke test для всего стека. Гарантированно вылезут гэпы — фиксим по ходу.

---

## Phase 2 — Reconciler & off-main

### P2.1 — M6 Reconciler

- Keyed diff между prev/next `RenderNode`-tree
- Список патчей: `Patch.insert(layer, at) / remove(layer) / move(from, to) / updateProps(layer, oldProps, newProps)`
- На update: применить только нужные мутации к существующему CALayer-tree
- React/Preact-style алгоритм: одноуровневое сопоставление по `key`, рекурсивно

**Acceptance:** бенч 1000 нодов, insert в середину, diff+apply < 2ms. Анимация background-color не флэшит при update.

### P2.2 — Off-main thread computation

- Build flex tree + calculateLayout + measure text + image decode → background queue
- Diff (M6) → background queue
- На main приезжает только список patches
- Profiling: ожидаем падение main-time с 1.5ms до < 0.3ms на типичный render

**Acceptance:** на M8-демо c CADisplayLink scroll увидеть main thread утилизацию < 20%.

---

## Phase 3 — Developer Experience

### P3.1 — `@lumen/core` JS framework

API:
```js
import { signal, View, Text, Pressable, render } from '@lumen/core'

const count = signal(0)
function Counter() {
  return (
    <View>
      <Text>Count: {count.value}</Text>
      <Pressable onTap={() => count.value++}>
        <Text>Increment</Text>
      </Pressable>
    </View>
  )
}
render(<Counter />)
```

- Signals (@preact/signals-подобные)
- `h()` или JSX-runtime
- Hooks: `useState`, `useEffect`, `useMemo`, `useCallback`
- Layout-стили через объект-проп
- Авто-перерендер на изменение сигнала, использующий M6 diff

### P3.2 — `lumen-cli`

- `lumen init <name>` — scaffold нового приложения
- `lumen dev` — dev-server c HMR
- `lumen build` — esbuild → один `.js` + `manifest.json` (потом `.lumen` архив)
- Distributable как `npm i -g @lumen/cli` или `bun add -g @lumen/cli`

### P3.3 — Hot reload в dev-server

- WebSocket в `tools/dev-server.ts` — broadcast on file change
- App (через injected runtime stub) — subscribe; на сообщение перевыполняет entry
- Сохранение state между перезагрузками опционально (через signals serialization)

---

## Phase 4 — Production polish

### P4.1 — Manifest discovery в AddressBar (full M9)

- Пользователь вводит обычный URL в адресной строке
- Параллельно: WKWebView начинает load + дёргается `<url>/.well-known/lumen.json`
- Если манифест валиден → отменить WebView, открыть в FastTab
- Иначе → WebView продолжает
- Это **тот самый «браузер с двумя движками»** из IDEA.md

### P4.2 — Animations

- JS API: `lumen.animate(layerRef, { from, to, duration, easing })`
- Под капотом: `CABasicAnimation` или `CAKeyframeAnimation`
- Анимации крутятся на render server (off-main), даже если JS залип
- Поддержка transforms, opacity, frame, backgroundColor

### P4.3 — Bytecode caching

- `JSScript.cacheBytecode(at:)` — преcompile JS на устройстве после первой загрузки
- На последующие старты грузим bytecode напрямую → cold start < 50ms
- Хранение в URL-cached directory с invalidation по ETag манифеста

### P4.4 — Real-device benchmark (M10)

Тестировать на iPhone 15 Pro / 17 Pro с ProMotion. Цель — те самые **120fps** на M8-нагрузке. Симулятор закроет нам только глаза 60Hz cap.

Если на железе < 100fps p95 на 10k-list — стоп, разбираем профайлером.

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
