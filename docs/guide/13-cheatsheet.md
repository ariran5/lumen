# 13 — Cheatsheet

Краткая шпаргалка по всему API. Полные типы — в
[lumen-types.d.ts](../../packages/lumen-types/index.d.ts).

---

## Создание проекта

```sh
bunx @lumen/cli init my-app
cd my-app
lumen dev               # http://localhost:8080
lumen build             # → dist/
```

---

## Базовые узлы

```ts
View(props?, ...children)
Text(string)
Text(props, ...content)
Text(props, () => string)               // thunk-text
Pressable({ onTap, ...props }, ...children)
Image({ source, ...props }, ...children?)
ScrollView({ onScroll?, onRefresh?, ...props }, ...children)
VirtualList({ count, itemHeight, render })
TextInput({ value, onChange, ...props })
Blur({ intensity, ...props }, ...children)
Glass({ variant?, ...props }, ...children)
MapView({ region, pins, ...props })
Slot({ ...flexProps }, thunk)            // реактивный контейнер
```

---

## FlexProps

```ts
flex, flexDirection: 'row' | 'column',
justifyContent, alignItems,
width, height, minWidth, maxWidth, minHeight, maxHeight,
padding, paddingTop|Right|Bottom|Left,
gap,
position: 'relative' | 'absolute', top, right, bottom, left
```

## VisualProps

```ts
backgroundColor, opacity, borderRadius, borderColor, borderWidth,
transform: { translateX, translateY, scale, scaleX, scaleY, rotate }
```

## TextStyleProps

```ts
fontSize, fontWeight, fontFamily, color,
textAlign, numberOfLines, lineHeight
```

---

## Reactivity

```ts
const s = signal(initial)
s.value          // прочитать + подписаться
s.value = v      // установить + нотифай
s.peek()         // прочитать БЕЗ подписки

const c = computed(() => s.value * 2)

const h = effect(() => console.log(s.value))
h.dispose()

mount(() => View(...))    // root effect

// Per-prop thunk (Vapor-style)
View({ opacity: () => s.value })
Text({ color: () => myColor.value }, () => myText.value)

// Reactive subtree
Slot({}, () => items.value.map(item => View({ key: item.id }, ...)))
```

---

## Animation (off-main)

```ts
const x = animated(0)

View({ transform: { translateX: x } })

x.set(10)                                 // immediate
x.animateTo(100, { duration: 300 })       // ease (default easeOut)
x.animateTo(0,   { easing: 'spring' })    // physics
x.stop()                                  // freeze visual, capture as model
x.current()                               // js-side mirror
```

Поддерживают AnimatedValue: `translateX/Y`, `scale`, `scaleX/Y`, `rotate`, `opacity`.

---

## Native APIs (`lumen.*`)

```ts
lumen.haptics('light' | 'medium' | 'heavy' | 'soft' | 'rigid' |
              'success' | 'warning' | 'error')

lumen.alert({ title?, message?, onOK? })
lumen.actionSheet({ title?, actions: [{ label, style? }], onSelect, onCancel? })

lumen.bottomSheet({
  height?: 'small' | 'medium' | 'large' | 'full',
  content: RenderNode,
  onClose?: () => void,
})

lumen.share({ text?, url?, onDone? })

lumen.storage.get(key)             // string | undefined
lumen.storage.set(key, value)
lumen.storage.remove(key)
lumen.storage.keys()
lumen.storage.clear()

lumen.secureStorage.get/set/remove(key, value?)
lumen.clipboard.copy(text) / paste() / has()

lumen.linking.open(url)            // http, mailto, tel, custom schemes
lumen.linking.canOpen(url)
lumen.linking.onIncoming.subscribe(fn)

lumen.biometrics.available()        // 'faceID' | 'touchID' | 'none'
await lumen.biometrics.authenticate('Reason shown to user')

await lumen.notifications.requestPermission()
const id = await lumen.notifications.schedule({ title, body?, at?, id? })
lumen.notifications.cancel(id) / cancelAll()
lumen.notifications.onTap.subscribe(fn)

lumen.statusBar.style({ theme: 'dark' | 'light' | 'auto', hidden? })

await lumen.imagePicker.pick({ limit })
await lumen.documentPicker.pick({ types: ['pdf'|'image'|...], multiple? })

lumen.tabs.list() / current() / own() / open(url?) / close(id?) / switch(id)

const ws = lumen.ws(url, { onOpen, onMessage, onClose, onError })
ws?.send(text); ws?.close()

lumen.router.push({ title, render: () => RenderNode, onPop? })
lumen.router.pop() / popToRoot() / setTitle(t)

lumen.bench.showFPS(visible) / resetStats() / snapshot()
```

### Reactive system state

```ts
lumen.safeArea.top | bottom | left | right
lumen.appState                     // 'active' | 'inactive' | 'background'
lumen.appearance.theme             // 'dark' | 'light'
lumen.network.online | type
```

---

## fetch

```ts
const r = await fetch(url, {
  method, headers, body,   // body: string | ArrayBuffer | TypedArray
})
r.ok, r.status
await r.text()
await r.json()
await r.arrayBuffer()       // для binary
```

⚠️ Хосты не из own-origin требуют `connect` в манифесте.

---

## Manifest

```json
{
  "name": "My App",
  "version": "0.1.0",
  "entry": "/bundle.js",
  "min_runtime": "0.1",
  "dev": true,
  "permissions": ["biometric", "notifications"],
  "connect": [
    "https://api.example.com",
    "https://*.cdn.example.com"
  ]
}
```

`dev: true` — только локально. `connect` — только https/wss, wildcard
только на subdomain.

---

## Gesture events

```ts
onTap, onDoubleTap, onLongPress: (e: { x, y }) => void

onPan: (e: {
  state: 'start' | 'changed' | 'ended' | 'cancelled',
  x, y, dx, dy, vx, vy,
}) => void

onSwipe: (e: { direction: 'left'|'right'|'up'|'down', x, y }) => void

onPinch:  (e: { state, scale, velocity }) => void
onRotate: (e: { state, rotation, velocity }) => void
```

---

## Project layout (recommended)

```
src/
├── index.ts          # mount(root)
├── routes.ts         # push-route registry
├── lib/              # pure logic, design tokens
├── state/            # module-level signals
├── services/         # async I/O
├── components/       # reusable UI
├── sheets/           # bottom-sheet flows
└── pages/            # router-pushed screens
```

См. [10-project-structure.md](10-project-structure.md) и
`Examples/BankApp` как reference.

---

## Не поддерживается (специально)

- DOM API (`document`, `window`, `localStorage`)
- CSS, classNames, селекторы
- React / hooks / VDOM (своя реактивность через signals)
- Synchronous network (всё через `fetch` или `lumen.ws`)
- Background mode JS (приостанавливается на `appState === 'background'`)

---

## Полезные ссылки

- [Examples/HelloApp](../../Examples/HelloApp) — однофайловый minimal
- [Examples/BankApp](../../Examples/BankApp) — multi-file template
- [Examples/HN](../../Examples/HN) — Hacker News reader
- [packages/lumen-types/index.d.ts](../../packages/lumen-types/index.d.ts) — полные типы
- [sessions/](../../sessions/) — журнал решений по дням
- [docs/IDEA.md](../IDEA.md), [docs/PLAN.md](../PLAN.md), [docs/ROADMAP.md](../ROADMAP.md) — устройство рантайма
