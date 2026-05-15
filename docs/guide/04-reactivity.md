# 04 — Reactivity

Реактивность в Lumen — это **fine-grained signals + reconciler**. Нет
VDOM-diff на каждый чих, нет хуков, нет dependency arrays. Базовая
модель — три примитива:

```ts
const x = signal(0)               // ячейка с .value
const doubled = computed(() => x.value * 2)
effect(() => console.log(doubled.value))  // запускается при x.value++
```

---

## Signal

```ts
const count = signal(0)

count.value          // 0  — записывает зависимость в текущий effect
count.value = 1      // нотифай всем зависящим effect'ам
count.value++        // == count.value = count.value + 1

count.peek()         // прочитать БЕЗ записи зависимости — нужно редко
```

Signals **module-level** — это нормально. Импортишь — получаешь тот же
signal во всех файлах:

```ts
// state/counter.ts
export const count = signal(0)

// pages/home.ts
import { count } from '../state/counter'
Text(() => `Home: ${count.value}`)

// pages/profile.ts
import { count } from '../state/counter'
Text(() => `Profile: ${count.value}`)
```

Оба места перерендерятся при `count.value++`.

---

## Computed

Derived signal:

```ts
const items = signal<Item[]>([])
const onlyDone = computed(() => items.value.filter(i => i.done))
const doneCount = computed(() => onlyDone.value.length)
```

Computed кэширует. `onlyDone.value` пересчитается только если изменится
`items.value`, не на каждое чтение.

`computed` — readonly: можно прочитать `.value` и `.peek()`, но **нельзя**
писать.

---

## Effect

Произвольный side-effect, который перезапускается при изменении любого
прочитанного signal'а:

```ts
effect(() => {
  console.log('count is now', count.value)
})

// Отписаться:
const handle = effect(() => { ... })
handle.dispose()
```

`mount(App)` под капотом это и есть один большой effect, который при
каждом запуске даёт reconciler'у новое дерево.

---

## Mount

```ts
mount(() => View({ ... }, ...))
```

Component-function пере-запускается ВСЯ при изменении любого signal'а,
прочитанного в ней. Под капотом — `effect`, который зовёт reconciler.

**Это работает быстро**, потому что:

1. Создание `RenderNode`-объектов ~1µs/узел (без аллокаций тяжёлых,
   immutable structs).
2. Reconciler делает keyed-diff: same-id node → переиспользуется CALayer,
   меняются только различающиеся props.
3. Стили не "переписываются" если узел остался тем же — см.
   `applyGeometryOnly` в `Renderer.swift`.

Но если у тебя дерево из 10k узлов и signal меняется 60 раз/сек — ребилд
будет тратить ~5ms на каждый. **Изолируй реактивность.**

---

## Изоляция реактивности — два инструмента

### 1. Thunk в style-слоте (Vapor-style)

Любой стиль-prop принимает **функцию** вместо значения:

```ts
const opacity = signal(1)

View({
  backgroundColor: '#7B6CFF',
  opacity: () => opacity.value,    // ← thunk
  width: 100, height: 100,
})
```

Что происходит:
- Lumen видит функцию в style-слоте.
- Заводит **per-prop effect** — отдельный мелкий effect ТОЛЬКО для
  `opacity`.
- При изменении `opacity.value` патчится свойство CALayer напрямую
  через `lumen._patchProp(layer, 'opacity', v)`.
- **Дерево не пересобирается.** `mount(App)`-effect не сработает.

Это самая дешёвая форма реактивности — никаких аллокаций RenderNode'ов,
никакого reconcile.

Какие props поддерживают thunk:

- Visual: `backgroundColor`, `opacity`, `borderColor`
- Text style: `color`, content (через `Text(props, () => string)`)
- Transform: `translateX/Y`, `scale`, `scaleX/Y`, `rotate`

#### Reactive Text content

```ts
Text({ fontSize: 24, color: '#FFFFFF' },
  () => `${count.value}`,  // ← thunk, per-text effect
)
```

Будет per-text effect, который записывает в `CATextLayer.string`.
Component-функция вокруг **не реран**.

---

### 2. Slot — реактивный subtree-контейнер

Когда меняются **дети** (список добавился/убрался, conditional rendering),
а не только props — нужен `Slot`. Это flex-контейнер, чьи дети приходят
из thunk'а:

```ts
const items = signal<string[]>(['a', 'b', 'c'])

mount(() => View({ flex: 1, padding: 16, gap: 12 },
  Text('Header'),

  Slot({ gap: 8 }, () => items.value.map(label =>
    View({ key: label, padding: 12, backgroundColor: '#16161D' },
      Text(label),
    ),
  )),

  Text('Footer'),
))
```

Когда `items.value = [...]`:
- **Только subtree внутри `Slot`** пересобирается.
- `mount` root-effect не реран.
- Header/Footer не трогаются вовсе.

Thunk может вернуть:
- `RenderNode` — один child
- `RenderNode[]` — массив flex-children
- `null` / `undefined` / `false` — пусто (conditional rendering)

#### Conditional rendering через Slot

```ts
const showDetails = signal(false)

Slot({}, () => showDetails.value
  ? View({ padding: 16 }, Text('Details visible'))
  : null,
)
```

---

## Когда использовать что

| Что меняется | Инструмент |
|---|---|
| Один цвет / opacity / число | Thunk в style-слоте |
| Текст внутри одного `Text` | `Text(props, () => str)` |
| Длинный список из массива | `Slot({}, () => arr.map(...))` |
| Conditional UI (показать/скрыть блок) | `Slot({}, () => cond ? ... : null)` |
| Сложное дерево с многими взаимосвязанными signal'ами | Может быть нормально перерисовывать в `mount` |

**Правило:** если signal меняется часто (drag, скролл, анимация) —
изолируй в thunk/Slot. Если редко (загрузка страницы, кнопка submit) —
не оптимизируй заранее, пусть mount-effect пересоберёт дерево.

---

## Keys — для list-reconcile

Когда внутри `Slot` массив одинаковых узлов — ставь `key`:

```ts
Slot({}, () => transactions.value.map(t =>
  View({ key: 'tx-' + t.id, padding: 12 },
    Text(t.name),
  ),
))
```

Без key reconciler будет матчить по позиции. С key — по identity, что
сохраняет per-node state (внутренние signal'ы внутри ноды) при
переупорядочивании.

---

## Per-page state pattern

Если страница имеет локальный state (форма, scroll position, loading flag),
создавай его внутри page-factory:

```ts
// pages/transfer.ts
export function transferPage() {
  // Эти signal'ы — локальные к этому открытию страницы.
  const amount = signal('')
  const submitting = signal(false)
  const error = signal<string | null>(null)

  return {
    render: () => View({ ... },
      TextInput({ value: () => amount.value, onChange: e => amount.value = e.value }),
      Slot({}, () => error.value
        ? Text({ color: 'red' }, () => error.value!)
        : null,
      ),
      Pressable({
        onTap: async () => {
          submitting.value = true
          try { await api.transfer(amount.peek()) }
          catch (e) { error.value = (e as Error).message }
          finally { submitting.value = false }
        },
        ...
      }),
    ),
  }
}
```

Каждое открытие страницы получает свежую копию state'а — никаких
дополнительных абстракций.

---

## Что НЕ делать

- ❌ Не читай `signal.value` в hot loop'ах. Используй `peek()` если
  не нужна реактивность:

  ```ts
  // плохо — каждый раз пишет зависимость
  for (let i = 0; i < 1000; i++) { sum += list.value[i] }

  // хорошо — снимок без подписки
  const snap = list.peek()
  for (let i = 0; i < snap.length; i++) { sum += snap[i] }
  ```

- ❌ Не вызывай `mount` несколько раз. Один root mount, остальная
  реактивность — через signals и Slot.

- ❌ Не мутируй массив/объект внутри `signal.value`:

  ```ts
  // плохо — signal не нотифицируется
  items.value.push(x)

  // хорошо
  items.value = [...items.value, x]
  ```

  Signal сравнивает по identity, не по содержимому.

---

## Дальше

→ [05 — Native APIs](05-native-apis.md): bottomSheet, alert, haptics,
biometrics, notifications.
