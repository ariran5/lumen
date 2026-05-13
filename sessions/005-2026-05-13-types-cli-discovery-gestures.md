# Session 005 — 2026-05-13: types, CLI, discovery, gestures

> Большая сессия. Несколько фич закрыты подряд. Главное достижение — Lumen стал **настоящим браузером с двумя движками** (P4.1) + комплектным toolchain'ом для внешних разработчиков (P3.2 + P3.4) + полноценным gesture API после серьёзного debug на real device.

---

## TL;DR

| ID | Фича |
|---|---|
| P3.2 | `@lumen/types` (.d.ts) + Bun.Transpiler в dev-server |
| P3.4 | `@lumen/cli` (init/dev/build) с counter-template |
| P4.1 | Manifest discovery в AddressBar — parallel WebView + probe + per-host cache TTL 24h |
| P4.2.a | Gestures: tap/longPress/pan/swipe/pinch/rotate (low-level) |
| P4.2.b | `transform: {translateX/Y, scale, rotate}` в style через CATransform3D |

Плюс крупное обсуждение **animation API design** — выбран подход **D (AnimatedValue)** с `.set/.animateTo/.stop` (как RN Animated) вместо declarative SwiftUI-style. Реализация в следующей сессии.

---

## P3.2 — `@lumen/types`

[packages/lumen-types/index.d.ts](../packages/lumen-types/index.d.ts) — global ambient типы для всех runtime-API:
- Components: `View/Text/Pressable/Image/VirtualList`
- Reactivity: `signal<T>/computed<T>/effect/mount`
- Gestures: `TapEvent/PanEvent/SwipeEvent/PinchEvent/RotateEvent/GestureProps`
- `TransformProps`, `FlexProps`, `VisualProps`, `TextStyleProps`
- `lumen.*`: `storage/router/bench/bottomSheet/alert/haptics`
- Std: `console/setTimeout/fetch`

Используется через `tsconfig.files`:
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020"],         // ← КРИТИЧНО: без DOM,
    "types": [],               //    иначе Text/Image конфликтуют
    "moduleResolution": "bundler",
    "strict": true, "noEmit": true
  },
  "files": [
    "../../packages/lumen-types/index.d.ts",
    "index.ts"
  ]
}
```

`.ts/.tsx` файлы транспилируются на лету dev-server'ом через `new Bun.Transpiler({loader}).transformSync(src)`. Production-серверы используют тот же подход (или AOT через `lumen build`).

[Examples/HN/index.ts](../Examples/HN/index.ts) — HN переписан с типами (`interface Story`, `signal<Story[]>`). `tsc --noEmit` clean.

Дополнительно: **пример `lumen.bottomSheet`** в HN — тап на "Open article" выезжает sheet с "Open in Safari" / "Save for later".

---

## P3.4 — `@lumen/cli`

[packages/lumen-cli/](../packages/lumen-cli/) с тремя командами:

| Команда | Что делает |
|---|---|
| `lumen init <name>` | Копирует [templates/default/](../packages/lumen-cli/templates/default/) → манифест, index.ts (counter demo), tsconfig, lumen-types.d.ts. Подставляет name в manifest. |
| `lumen dev [path] [port]` | Запускает `startDevServer()` из [packages/lumen-cli/src/dev-server.ts](../packages/lumen-cli/src/dev-server.ts) (HTTP + WS HMR + on-the-fly TS transpile) |
| `lumen build [path]` | `Bun.build` минифицирует entry → `dist/bundle.js`. Counter-демо: **0.6 KB за 6ms**. Пишет production `dist/manifest.json` без `dev:true`. |

[tools/dev-server.ts](../tools/dev-server.ts) теперь shim над общим CLI пакетом — один исходник.

E2E подтверждено: `lumen init demo` → `tsc --noEmit` clean → `lumen build` → `lumen dev` → симулятор открыл counter с Tap me / Reset.

---

## P4.1 — Manifest discovery (browser UX)

[TabModel.commit()](../Sources/LumenShell/TabModel.swift):
1. **Cache check** ([BundleProbeCache](../Sources/LumenRuntime/BundleLoader.swift)) — per-host, TTL 24h. Hit → мгновенно открыть в нужном режиме.
2. **Cache miss** — оптимистично `mode = .web(url)` (WKWebView грузит сразу), параллельно `BundleLoader.probe()` в фоне.
3. **Probe = .fastApp** → если пользователь ещё на том же URL → swap `mode = .fastApp(url)`.
4. Результат **сохраняется в cache** — повторный visit мгновенный.

Это и есть **«браузер с двумя движками»** из IDEA.md §1:
- `localhost:8080` → fast-app (HN на @lumen/core)
- `https://news.ycombinator.com` → WKWebView (нативный HN сайт)

**Продуктовая story теперь полная.** Можно показывать кому угодно.

---

## P4.2 — Gestures (низкий уровень)

[Sources/LumenRuntime/GestureRouter.swift](../Sources/LumenRuntime/GestureRouter.swift) — один router на rootLayer, вешает recognizer'ы на hostView. Это эффективно: N recognizer'ов, не N×K.

7 типов handler'ов (на любом узле):
- `onTap(e)` — `e = {x, y}` в локальных координатах узла
- `onLongPress(e)` — 0.45s
- `onPan(e)` — `e = {state, x, y, dx, dy, vx, vy}`, state = `start/changed/ended/cancelled`
- `onSwipe(e)` — `e = {direction: 'left'|'right'|'up'|'down', x, y}`
- `onPinch(e)` — `e = {state, scale, velocity}`
- `onRotate(e)` — `e = {state, rotation, velocity}` (радианы)

В RenderNode добавлены поля + парсинг через `gestureProps[]`. В CoreFramework — `attachGestures()` помощник в `View/Pressable/Image`.

**Transform в style** (P4.2.b):
```js
View({transform: {translateX: 50, translateY: 100, scale: 1.2, rotate: 0.3}})
```
В Swift: `CATransform3D` через `Translate → Rotate → Scale`. Это база для будущих animations через CABasicAnimation.

[Examples/DragLab/index.ts](../Examples/DragLab/index.ts) — финальное демо: pan/tap/long/swipe/pinch/rotate всё вместе на одном экране. Шарик через transform двигается за пальцем.

### Real-device debug story (важно для будущего)

Когда первый раз поставили DragLab на iPhone 15 Pro Max, **ничего не работало**. Пошагово разбирали:

1. **`CALayer.hitTest` на real device глючит.** На симуляторе работало, на iPhone — touch ловится только в нижней половине layer'а. Apple's docs неоднозначны (point должен быть в superlayer's coords; на практике поведение не сходится). Решение: написать **собственный recursive walker** с явной конверсией координат `pointInLayer - sublayer.frame.minX/minY`. После этого hit-test работает идеально.

2. **DoubleTap recognizer воровал события у single tap** через `require(toFail:)`. Single tap имел 300ms delay (ждал fail double). На real device пользователь видел "тапы не работают" — на самом деле работали через 300ms. Решение: **DoubleTap убран целиком**, single tap фейрит мгновенно. Возврат через custom `touchesBegan/Ended` + time-anchor — отложен.

3. **`layer.frame = X` компенсирует transform.** Когда я ставлю layer.frame, и потом меняю layer.transform — frame setter уже скорректировал position под старый transform. Шарик визуально не двигается. Решение: **`bounds + position` раздельно**, не frame.

4. **Pan vs Tap, Swipe, LongPress конкуренция.** Сначала пробовал `pan.require(toFail: tap, long, swipe)` — это блокировало pan на 0.45s (ждал fail longPress). Шарик не ловился. Затем убрал require → pan начинался везде, ловя touches предназначенные swipe'у. Финальное правильное решение: **`gestureRecognizerShouldBegin` per recognizer type**:

   ```swift
   nonisolated func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
     // Pan активируется ТОЛЬКО на узле с onPan; swipe ТОЛЬКО с onSwipe, etc.
     return hitTest(rootLayer, point, where: predicate) != nil
   }
   ```

   Никаких `require`'ов больше нет — каждый жест работает на «своих» узлах, конфликта по площади экрана нет.

Финальное состояние: **все 6 жестов работают одновременно** в DragLab. Это foundation для будущих анимаций.

---

## Animation API дизайн (на следующую сессию)

Долгое обсуждение, варианты:
- **A** Императивный `lumen.animate(ref, ...)` — refs не вяжутся с value-object RenderNode
- **B** Declarative `animation: {duration}` в style — простое, но **нет control над interrupt** (главный critique пользователя: «шарик летит, я хватаю его рукой — animation должна остановиться **точно где он визуально**»)
- **C** Hooks `useAnimated(0, {duration})` — обёртка над B
- **D ✓ ВЫБРАН** `animated()` value с `.set/.animateTo/.stop`

```js
const ballX = animated(0)

ballX.animateTo(500, {duration: 5000})    // start animation
// через 2 секунды:
ballX.stop()                              // capture layer.presentation() value, halt anim
ballX.set(touch.x)                        // instant set, без анимации
ballX.animateTo(home.x, {easing: 'spring', velocity: lastVx})  // spring back
```

`.stop()` читает `layer.presentation()?.value` — то что **визуально сейчас** на экране — и фиксирует как новое value. Никакого рывка.

Implementation план — следующая сессия:
1. JS-side `AnimatedValue` class в CoreFramework (~80 LOC)
2. Native bridge — `lumen._animValue.{create,set,animateTo,stop}` через JSValue
3. Связка AnimatedValue ↔ layer.keyPath через MountedNode при reconcile
4. Easing: linear/easeIn/easeOut/easeInOut + spring (CASpringAnimation)

Plus high-level `draggable({snapBack: true})` helper поверх — для 80% случаев в одну строку.

---

## Что в backlog добавлено

### OpenTelemetry SDK (запрос пользователя)

Встроенный сборщик логов / трейсов / метрик в OTLP-формате. Подключение одной строкой:
```ts
lumen.telemetry.configure({endpoint: 'https://otel.example.com', service: 'hn-reader'})
```
Auto-collect: console.log/warn/error (logs), navigation/fetch/mount/exceptions (spans), renderMs/heap/network (metrics). ~500-1000 LOC, opt-in package.

### Runtime TypeScript на клиенте

Решено: сейчас server-side через `Bun.Transpiler`. Если когда-нибудь понадобится «open any .ts URL anywhere» — sucrase (~500KB) или свой stripper (~5KB / ~200 LOC).

### Gesture parsing оптимизация

`RenderNode.parse` сейчас делает 7 JSValue lookups на gesture-handlers для каждого узла. На больших деревьях (~6ms на 300 nodes). Оптимизация — итерировать ключи узла раз вместо 7 лукапов, или markers (`hasGestures: true`) от builder'ов. ~30% экономии.

---

## Файлы изменены

### Новые
- [packages/lumen-types/index.d.ts](../packages/lumen-types/index.d.ts) + [package.json](../packages/lumen-types/package.json) + [README.md](../packages/lumen-types/README.md)
- [packages/lumen-cli/](../packages/lumen-cli/) — package.json, bin/, src/{index,commands/{init,dev,build},dev-server}.ts, templates/default/{manifest,index.ts,tsconfig,lumen-types.d.ts,README}
- [Sources/LumenRuntime/GestureRouter.swift](../Sources/LumenRuntime/GestureRouter.swift) — все recognizer'ы + custom walker + shouldBegin filter
- [Examples/DragLab/](../Examples/DragLab/) — manifest, tsconfig, index.ts

### Расширены
- [Sources/LumenShell/TabModel.swift](../Sources/LumenShell/TabModel.swift) — parallel discovery + cache
- [Sources/LumenRuntime/BundleLoader.swift](../Sources/LumenRuntime/BundleLoader.swift) — добавлен `BundleProbeCache`
- [Sources/LumenRuntime/RenderNode.swift](../Sources/LumenRuntime/RenderNode.swift) — 7 gesture-полей + transform parsing
- [Sources/LumenRuntime/ViewStyle.swift](../Sources/LumenRuntime/ViewStyle.swift) — `Transform` struct
- [Sources/LumenRuntime/Renderer.swift](../Sources/LumenRuntime/Renderer.swift) — `bounds + position` вместо `frame`, GestureRouter вместо TapProxy
- [Sources/LumenRuntime/CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift) — `attachGestures()` для всех 7 типов
- [tools/dev-server.ts](../tools/dev-server.ts) — shim над CLI пакетом
- [Examples/HN/](../Examples/HN/) — `.js → .ts`, manifest `entry: '/index.ts'`, bottomSheet example
- [project.yml](../project.yml) — DEVELOPMENT_TEAM настроен, NSAllowsLocalNetworking

---

## Команды

```bash
# Сборка iOS
xcodegen generate
xcodebuild -project Lumen.xcodeproj -scheme Lumen -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Release на iPhone (нужен DEVELOPMENT_TEAM в project.yml)
DEVICE_ID="00008130-001C21593CC0001C"
xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Release \
  -destination "id=$DEVICE_ID" -allowProvisioningUpdates build
APP=$(xcodebuild ... -showBuildSettings | grep BUILT_PRODUCTS_DIR | awk -F' = ' '{print $2}')
xcrun devicectl device install app --device $DEVICE_ID "$APP/Lumen.app"
xcrun devicectl device process launch --device $DEVICE_ID com.lumen.browser \
  -- -url "http://192.168.0.108:8080"

# Dev-server с HMR
bun tools/dev-server.ts Examples/DragLab 8080
# или через CLI
bun packages/lumen-cli/bin/lumen.js dev Examples/DragLab 8080

# Создать новый fast-app
bun packages/lumen-cli/bin/lumen.js init my-app
cd my-app
bun ../packages/lumen-cli/bin/lumen.js dev
```

---

## Что осталось из плана

Из приоритетов P3 + P4:
- ~~P3.2 types~~ ✓
- ~~P3.4 cli~~ ✓
- ~~P4.1 discovery~~ ✓
- ~~P4.2.a gestures~~ ✓
- ~~P4.2.b transform~~ ✓
- **P4.2.c — Animations (AnimatedValue + draggable helper)** ← следующая сессия
- P4.3 — Bytecode caching (пользователь сказал «отложить, нужно понимать invalidation»)
- DevTools / Inspector (P3.5)
- DoubleTap return через custom touchesBegan/Ended

Phase 0 ports почти все закрыты. После animations (P4.2.c) — Lumen полностью готов как платформа для пилотного приложения.
