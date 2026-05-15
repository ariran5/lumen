# 08 — Advanced components

## ScrollView

Вертикальный скролл. Под капотом — `UIScrollView` с native momentum,
bounce, scroll indicator.

```ts
ScrollView({ flex: 1, padding: 16, gap: 12 },
  Text('A'),
  Text('B'),
  Text('C'),
  // ... много детей
)
```

Дети раскладываются top-to-bottom как column, content size считается
автоматически из intrinsic heights.

### onScroll

```ts
ScrollView({
  flex: 1,
  onScroll: (e) => {
    // e.offset, e.viewportHeight, e.contentHeight
    if (e.offset > 100) headerCollapsed.value = true
    else headerCollapsed.value = false
  },
}, ...children)
```

Фаерится на каждом scroll-tick (до 120 Hz на ProMotion). Дешёвый bridge,
но если handler тяжёлый — троттлируй сам.

### Pull-to-refresh

```ts
ScrollView({
  flex: 1,
  onRefresh: async () => {
    await reload()
    // спиннер скроется когда промис разрезолвится
  },
}, ...children)
```

Sync-handler (без Promise) — спиннер скрывается на следующем runloop-tick.

---

## VirtualList — для 10k+ items

Когда у тебя сотни/тысячи одинаковых строк, ScrollView с массивом
не справится: каждый узел — это CALayer, и iOS не любит 10k слоёв.

VirtualList рендерит **только видимые + buffer**, переиспользует CALayer
при скролле (recycling).

```ts
VirtualList({
  count: 10_000,
  itemHeight: 64,
  render: (index) => View(
    {
      key: 'item-' + index,
      flexDirection: 'row',
      padding: 12, gap: 12,
      height: 64,
      backgroundColor: '#16161D',
    },
    View({ width: 40, height: 40, borderRadius: 20, backgroundColor: '#7B6CFF' }),
    View({ flex: 1, gap: 4 },
      Text({ fontSize: 15, fontWeight: '600', color: '#FFFFFF' }, `Item ${index}`),
      Text({ fontSize: 12, color: '#9CA3AF' }, 'Subtitle'),
    ),
  ),
})
```

### Ограничения

- **`itemHeight` фиксированный.** Это нужно для cell pre-sizing. Если
  высоты разные — нужен variable-height VirtualList (не реализован).
- **`count` — число элементов**, не массив. Сами items держи в state'е
  отдельно, в `render(index)` доставай по индексу.
- **Внутри `render` нельзя завести signal, который вызовет re-render
  всего списка.** Используй keyed identity (`key: 'item-' + index`)
  и реактивность через thunks внутри узла.

### Когда брать VirtualList vs ScrollView+Slot

| Items | Что использовать |
|---|---|
| <50 | ScrollView с детьми или Slot |
| 50–500 | ScrollView если статичные, Slot если динамика |
| 500+ | VirtualList |

> 100 слоёв CALayer iOS жуёт легко. 10k — нет. VirtualList — это
> recycling-pool, обычно 20–40 живых слоёв одновременно.

---

## TextInput

```ts
const text = signal('')

TextInput({
  value: text.value,
  placeholder: 'Type something',
  onChange: (e) => text.value = e.value,
  onSubmit: (e) => console.log('submitted:', e.value),

  // Стили
  fontSize: 16, color: '#FFFFFF',
  backgroundColor: '#16161D',
  borderRadius: 12,
  paddingTop: 12, paddingBottom: 12,
  paddingLeft: 14, paddingRight: 14,
})
```

### Keyboard types

```ts
TextInput({
  keyboardType: 'email',  // 'default' | 'url' | 'email' | 'number' | 'decimal' | 'phone' | 'search'
  returnKey: 'go',        // 'default' | 'go' | 'next' | 'done' | 'search' | 'send' | 'continue'
  autocapitalize: 'none', // 'none' | 'sentences' | 'words' | 'characters'
  autocorrect: false,
  secure: false,          // password input
  // ...
})
```

### Controlled только через `value`

`TextInput` обновляет field **только когда меняется prop `value`**.
Юзер печатает → `onChange` — но текст в поле НЕ сменится сам собой.
Чтобы UI отражал signal, прокинь value-thunk:

```ts
TextInput({
  value: text.value,           // прочитывает signal сейчас, реагирует на ребилд
  onChange: e => text.value = e.value,
})
```

Если `mount` не пересоберёт компонент — поле не обновится. Если хочешь,
чтобы программная установка `text.value = 'hello'` отразилась в поле,
поле должно быть внутри реактивного скоупа (mount-функция или Slot).

---

## Image

```ts
Image({
  source: 'https://example.com/avatar.jpg',
  width: 80, height: 80,
  borderRadius: 40,
  contentMode: 'cover',  // 'cover' | 'contain' | 'stretch' | 'center'
})
```

`source` принимает:
- HTTP/HTTPS URL — должно быть в `connect` (или own-origin)
- `file://` URI (из picker'ов)

Image декодируется на background queue с downsampling — full-res
оригинал в memory не висит. Кэш по URL.

### С контентом сверху

```ts
Image({
  source: '...',
  width: '100%', height: 200,
  borderRadius: 16,
},
  // Children — overlay поверх изображения
  View({ position: 'absolute', bottom: 0, left: 0, right: 0, padding: 16 },
    Text({ fontSize: 18, fontWeight: '700', color: '#FFFFFF' }, 'Caption'),
  ),
)
```

---

## Blur

Системные UIBlurEffect-материалы. Полупрозрачный фон.

```ts
Blur({
  intensity: 'regular',
  // 'ultraThin' | 'thin' | 'regular' | 'thick' | 'chrome'
  // или 'glass' / 'glassClear' — iOS 26 Liquid Glass
  width: '100%', height: 60,
  borderRadius: 20,
},
  Text('Sticky header'),
)
```

Children рендерятся **внутри** effect view — текст и иконки идут поверх
размытия как одна "пилюля".

---

## Glass — Liquid Glass iOS 26

Сахар над `Blur` с интенсивностями `'glass'` / `'glassClear'`. Auto-fallback
к material на iOS < 26.

```ts
Glass({
  variant: 'regular',  // 'regular' | 'clear'
  borderRadius: 28,
  paddingTop: 8, paddingBottom: 8,
  paddingLeft: 16, paddingRight: 16,
},
  Text({ color: '#FFFFFF' }, 'Floating pill'),
)
```

> Используй Glass для всех floating-элементов: tab-bar, FAB, address-pill.
> Это новый design language iOS 26.

---

## MapView — нативный MKMapView

```ts
const region = signal({
  lat: 37.7749, lon: -122.4194,
  latDelta: 0.05, lonDelta: 0.05,
})

const pins = signal([
  { id: 'office', lat: 37.78, lon: -122.41, title: 'Office' },
  { id: 'cafe',   lat: 37.77, lon: -122.42, title: 'Cafe' },
])

MapView({
  flex: 1,
  region: region.value,
  pins: pins.value,
  mapType: 'standard',  // 'standard' | 'satellite' | 'hybrid'
  onRegionChange: (r) => region.value = r,
  onPinTap: (id) => console.log('tapped pin', id),
})
```

Pins diff'ятся по `id + lat + lon + title`. Если без `id` — пересоздаются
при каждом рендере (медленно).

Регион меняется → `MKMapView.setRegion(animated: true)`.

---

## Slot — реактивный контейнер

Подробно — в [04-reactivity.md](04-reactivity.md). Кратко:

```ts
Slot({ gap: 8 }, () => items.value.map(i =>
  View({ key: i.id, ... }, ...)
))
```

При изменении `items.value` ребилдится ТОЛЬКО внутренность Slot. Идеально
для:
- Списков, которые добавляются/удаляются
- Conditional rendering (`cond ? View(...) : null`)
- Switch'а вкладки в tab-bar

---

## Дальше

→ [09 — Animations](09-animations.md): off-main анимации через
`animated()` и тонкости thunk'ов в transform.
