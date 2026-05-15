# 12 — Debugging

## Safari Web Inspector

JSContext в Lumen видим в Safari Developer Tools — так же, как Web в
обычном Safari.

### Включить

1. На устройстве/симуляторе: **Settings → Safari → Advanced → Web Inspector → ON**.
2. На Mac: **Safari → Settings → Advanced → Show Develop menu in menu bar**.
3. Подключи устройство (или открой симулятор).
4. **Develop → <твоё устройство> → Lumen → JSContext**.

В debug-сборках Lumen ставит `JSContext._isInspectable = true`
автоматически.

### Что доступно

- **Console:** `console.log`/`error` из fast-app'а попадают сюда. Можно
  запускать произвольный JS, тоже выполняется в JSContext.
- **Breakpoints:** поставь брейк в любой строке твоего bundle.js —
  выполнение остановится, можно step-by-step.
- **Network:** **не работает** для `fetch` из JSContext (это не WKWebView).
  Используй `console.log` или прокси через `Bun --hot serve` с логами.
- **Sources:** видны все импортированные модули (в dev) или весь bundle (в production).

---

## FPS HUD

В рантайме встроен performance HUD:

```ts
lumen.bench.showFPS(true)
// floating overlay в key window
```

Показывает текущий FPS (EMA), минимум, p5. Полезно для:
- Проверки 120 fps на ProMotion при scroll'е.
- Поиска frame drops в анимациях.
- Замера cold-start (`resetStats()` сразу после mount, `snapshot()` после
  первого кадра).

```ts
lumen.bench.resetStats()
mount(() => ...)

setTimeout(() => {
  console.log(lumen.bench.snapshot())
  // { avg: 119.4, min: 88, p5: 105, max: 120, count: 240 }
}, 2000)
```

> **Внимание:** HUD меряет CADisplayLink callback rate, не render rate.
> Если main thread свободен, CADisplayLink стабильно тикает 120 раз/сек
> на ProMotion — но это не доказывает что узлы рисуются на 120 fps.
> Для render-rate смотри **Instruments → Core Animation**.

---

## Instruments — детальный профайл

Подключи устройство, открой **Xcode → Open Developer Tool → Instruments**.

| Шаблон | Что меряет |
|---|---|
| Time Profiler | Где main thread тратит время. Если JS — увидишь `JSObject::call` / `JIT compiled`. Если CA — `CA::Layer::commit`. |
| Core Animation | Frame rate, что заставляет коммит. Подсветит «too many layers», offscreen rendering. |
| Allocations | Memory pressure. JSC heap растёт неконтролируемо? Layer-leak? |
| System Trace | Holistic — main thread, GPU, IO. Для cold-start measurement. |

### Часто видимые patterns

- **Main thread tight loop в `JIT compiled` >5ms/frame** — слишком тяжёлый
  компонент-функция, перерисовывается часто. Изолируй через Slot/thunk.
- **`applyAll` в Renderer >2ms/frame** — слишком большое дерево
  перестраивается. Тот же fix.
- **Offscreen rendering вспышка** — borderRadius + не-opaque background
  на больших layer'ах. Сделай background opaque или вынеси в отдельный layer.

---

## Типичные грабли

### Текст обрезается

```ts
// плохо — текст не помещается, без явной высоты CATextLayer обрежется
View({ flexDirection: 'row' },
  Text({ fontSize: 16 }, 'Some text'),
)

// хорошо — flex родителя или явная ширина у текста
View({ flexDirection: 'row' },
  Text({ flex: 1, fontSize: 16 }, 'Some text'),
)
```

CATextLayer не умеет в intrinsic height сам по себе — Lumen меряет
текст через CoreText и кладёт в Yoga. Но если ширина не зафиксирована
родителем — Yoga даст текст в столько строк, в сколько надо.

### Text не виден / мыло

- `contentsScale` ставится автоматически. Если текст выглядит мыльно —
  это бага.
- Без `fontSize` — default 16. Без `color` — default `'#000000'` (на
  тёмном фоне будет невидим).

### Signals не обновляют UI

```ts
const items = signal<string[]>([])

// плохо — push мутирует массив, signal не нотифицируется
items.value.push('new')

// хорошо — новая ссылка
items.value = [...items.value, 'new']
```

Signals сравнивают по identity (`Object.is`). Если ты вернул тот же
массив/объект — слушатели не сработают.

### Mount пересобирает весь экран при каждом изменении

Скорее всего ты читаешь signal в component-функции:

```ts
function App() {
  return View({},
    Text(`Count: ${count.value}`),   // ← читает count.value в App
  )
}

mount(App)
// каждое count++ ребилдит App() целиком
```

Fix: thunk:

```ts
function App() {
  return View({},
    Text({ ... }, () => `Count: ${count.value}`),   // ← thunk
  )
}
```

Теперь `count.value` читается в **per-text effect**, не в App.

### Slot пересобирает subtree без причины

Проверь, что `key` стабильный:

```ts
// плохо — key зависит от индекса, переставил элементы — все ребилднутся
Slot({}, () => items.value.map((item, i) =>
  View({ key: 'item-' + i }, ...)
))

// хорошо — key из стабильного id
Slot({}, () => items.value.map(item =>
  View({ key: 'item-' + item.id }, ...)
))
```

### Fetch reject'ится с NetworkPolicyError

Хост не в `connect`. Проверь манифест, добавь host. Не забудь, что
схема обязательна (`https://`) и default-port игнорируется.

### Bottom sheet скачет / disappears halo

iOS 26 baseline-behavior на `.large` detent. **Не Lumen.** Воспроизводится
в чистом UIKit-проекте без участия рендера. Используй `'medium'` если
критично.

### Tab-bar торчит из-под sheet'а

Floating tab-bar (position: absolute, bottom: X) видно поверх sheet'а на
medium detent. Прячь на время открытия:

```ts
const sheetOpen = signal(false)

// в root:
Slot({}, () => sheetOpen.value ? null : TabBar())

// при открытии sheet'а:
sheetOpen.value = true
lumen.bottomSheet({ ..., onClose: () => sheetOpen.value = false })
```

---

## Логирование на устройстве

`console.log` в Safari Inspector — основной канал. Альтернативы:

### Write-to-file + copy

```ts
// (нет прямого API в fast-app sandbox'е, но через сервер можно:)
fetch(`${API}/log`, { method: 'POST', body: JSON.stringify({ event, data }) })
```

Или дёргай `lumen.alert({ message: JSON.stringify(thing) })` для
quick-and-dirty debug.

### Системный log на устройстве (для Swift-разработки Lumen самого)

```sh
/usr/bin/log stream --device <devicectl-id> --predicate 'process == "Lumen"'
```

Note: используй `/usr/bin/log`, не zsh builtin `log`.

---

## Тесты

В репо есть Swift XCTests для самого рантайма:

```sh
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Конкретный класс:
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:LumenTests/ReactivityTests
```

Покрытие:
- `ReactivityTests` — signal → thunk → `lumen._patchProp` → CALayer end-to-end.
- `ReconcilerTests` — mount/diff/append/remove.
- `FlexLayoutTests` — все layout-кейсы.
- `NetworkPolicyTests` — sandbox/connect.

Это тесты **рантайма**, не твоего fast-app'а. Для своего приложения
пиши unit-тесты на `lib/` и `services/` через `bun test` (CLI создаёт
скелет).

---

## Дальше

→ [13 — Cheatsheet](13-cheatsheet.md): шпаргалка по API.
