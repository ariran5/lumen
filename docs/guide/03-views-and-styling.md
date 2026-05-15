# 03 — Views & styling

## Базовые примитивы

| Функция | Render | Когда юзать |
|---|---|---|
| `View(props?, ...children)` | `CALayer` | Контейнер. Flex-родитель. |
| `Text(props?, ...content)` или `Text(string)` | `CATextLayer` | Любой текст. Однострочный или multi-line. |
| `Pressable(props, ...children)` | `CALayer` + `UITapGestureRecognizer` | Кнопка / тап-цель. `onTap` обязателен. |
| `Image(props, ...children?)` | `CALayer` с `contents` | Картинка по URL. Дети могут лежать ПОВЕРХ изображения. |
| `ScrollView(props?, ...children)` | `UIScrollView` + CALayer | Вертикальный скролл. |
| `VirtualList(props)` | `UICollectionView` | Длинные списки (10k+ items). |
| `TextInput(props)` | `UITextField`/`UITextView` | Ввод текста. |
| `Blur(props?, ...children)` | `UIVisualEffectView` | Размытый фон, system materials. |
| `Glass(props?, ...children)` | `UIGlassEffect` (iOS 26) | Liquid Glass, fallback к material на iOS<26. |
| `MapView(props)` | `MKMapView` | Карты, пины, регион. |
| `Slot(props, thunk)` | `CALayer` + локальный effect | Реактивный контейнер. Только этот subtree пересобирается. |

Полные типы props см. в `packages/lumen-types/index.d.ts` или в файле
`lumen-types.d.ts`, который CLI кладёт в твой проект.

---

## Минимальный пример каждого

### View

```ts
View({ flex: 1, padding: 16, gap: 12, backgroundColor: '#0F0F12' },
  Text('Hello'),
  Text('World'),
)
```

### Text

```ts
Text('Short')

Text({ fontSize: 17, fontWeight: '600', color: '#FFFFFF' }, 'Bold heading')

// Multi-line с обрезкой
Text(
  { fontSize: 13, color: '#9CA3AF', numberOfLines: 3, lineHeight: 18 },
  'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor.',
)
```

### Pressable

```ts
Pressable({
    onTap: () => lumen.haptics('light'),
    padding: 14, backgroundColor: '#6366F1', borderRadius: 12,
  },
  Text({ color: '#FFFFFF' }, 'Tap me'),
)
```

### Image

```ts
Image({
  source: 'https://example.com/avatar.png',
  width: 44, height: 44, borderRadius: 22,
  contentMode: 'cover',
})
```

`source` — обычная HTTP/HTTPS URL **или** локальный `file://` URI
(из `imagePicker` / `documentPicker`). Картинки декодируются
на background queue и кэшируются.

---

## Стиль-система

Стили **inline**, никакого CSS. Каждый prop — это сразу свойство
CALayer / Yoga-ноды. Стилей нет в отдельных объектах — есть props
самой ноды.

### FlexProps — layout

Layout считается через собственный Flexbox-движок на чистом Swift
(см. `Sources/LumenLayout/FlexLayout.swift`). Подмножество CSS Flexbox.

```ts
interface FlexProps {
  flex?: number
  flexDirection?: 'row' | 'column'
  justifyContent?: 'flex-start' | 'flex-end' | 'center' |
                   'space-between' | 'space-around' | 'space-evenly'
  alignItems?: 'flex-start' | 'flex-end' | 'center' | 'stretch'
  width?: number | `${number}%` | 'auto'
  height?: number | `${number}%` | 'auto'
  minWidth?, maxWidth?, minHeight?, maxHeight?: number
  padding?, paddingTop?, paddingRight?, paddingBottom?, paddingLeft?: number
  gap?: number

  // Абсолютная позиция — вырывает из flow.
  position?: 'relative' | 'absolute'
  top?, right?, bottom?, left?: number
}
```

#### Row с тремя кнопками поровну

```ts
View({ flexDirection: 'row', gap: 12 },
  button('A'), button('B'), button('C'),
)

function button(label: string) {
  return Pressable({ flex: 1, padding: 14, backgroundColor: '#27272F' },
    Text({ color: '#FFFFFF', textAlign: 'center' }, label),
  )
}
```

#### Column с гэпом и паддингом

```ts
View({ flex: 1, padding: 20, gap: 12 },
  Text('a'),
  Text('b'),
  Text('c'),
)
```

`flexDirection` по умолчанию `'column'` (как в React Native, в отличие от
веба).

#### Абсолютная позиция — оверлей

```ts
View({ flex: 1 },
  ScrollView({ flex: 1 }, /* контент */),

  // Floating FAB поверх скролла
  Pressable({
    position: 'absolute',
    right: 20, bottom: 20,
    width: 56, height: 56, borderRadius: 28,
    backgroundColor: '#6366F1',
    alignItems: 'center', justifyContent: 'center',
    onTap: () => {},
  },
    Text({ color: '#FFFFFF', fontSize: 28 }, '+'),
  ),
)
```

> Z-order по declaration order: абсолютные дети — последними, чтобы
> лежали поверх flow-сиблингов.

---

### VisualProps — внешний вид

```ts
interface VisualProps {
  backgroundColor?: Color    // '#RRGGBB', '#RRGGBBAA', 'red', 'transparent'
  opacity?: number           // 0..1
  borderRadius?: number
  borderColor?: Color
  borderWidth?: number
  transform?: TransformProps // translateX/Y, scale, scaleX/Y, rotate (рад)
}
```

#### Карточка с тенью-аналогом через layered fills

```ts
View({
  backgroundColor: '#16161D',
  borderRadius: 18,
  borderWidth: 1,
  borderColor: '#262633',
  padding: 16,
})
```

> Box-shadow пока не реализован отдельным prop'ом — используй
> `borderColor` + `borderWidth` или layered View для имитации.

---

### TextStyleProps

```ts
interface TextStyleProps {
  fontSize?: number          // points
  fontWeight?: '300'..'900' | 'normal' | 'bold' | 'thin' | ...
  fontFamily?: string        // 'SF Pro', 'Menlo', и т.д.
  color?: Color
  textAlign?: 'left' | 'right' | 'center' | 'justify'
  numberOfLines?: number     // 0 = без лимита
  lineHeight?: number
}
```

#### Многострочный текст

```ts
Text(
  { fontSize: 13, color: '#9CA3AF', numberOfLines: 3, lineHeight: 18 },
  veryLongString,
)
```

Если `numberOfLines` опущен — текст рендерится в одну строку, обрезается
шириной контейнера. `lineHeight` — это абсолютный лидинг, не множитель.

---

### TransformProps

```ts
View({
  width: 100, height: 100,
  backgroundColor: '#7B6CFF',
  transform: {
    translateX: 20,
    rotate: Math.PI / 8,    // ~22.5°
    scale: 1.1,
  },
})
```

Transform-поля принимают `number`, `() => number` (thunk) или
`AnimatedValue`. См. [09-animations.md](09-animations.md).

---

## Жесты

Все жест-pop'ы принимаются на `View`, `Pressable`, `Image`. Для скролла
есть `onScroll` на `ScrollView`. Жест-обработчики:

```ts
interface GestureProps {
  onTap?: (e: TapEvent) => void
  onDoubleTap?: (e: TapEvent) => void
  onLongPress?: (e: TapEvent) => void
  onPan?: (e: PanEvent) => void        // drag с x/y/dx/dy/vx/vy + state
  onSwipe?: (e: SwipeEvent) => void    // 'left' | 'right' | 'up' | 'down'
  onPinch?: (e: PinchEvent) => void    // scale + state
  onRotate?: (e: RotateEvent) => void  // rotation (рад) + state
}
```

Пример drag-карты:

```ts
const x = signal(0)
const y = signal(0)

View({
  width: 120, height: 120,
  backgroundColor: '#7B6CFF',
  borderRadius: 16,
  transform: {
    translateX: () => x.value,
    translateY: () => y.value,
  },
  onPan: (e) => {
    if (e.state === 'changed' || e.state === 'start') {
      x.value = e.dx
      y.value = e.dy
    } else if (e.state === 'ended') {
      // snap back
      x.value = 0
      y.value = 0
    }
  },
})
```

> Жест-обработчики **синхронные** на JS thread. Lumen вызывает
> их через JSContext без message-queue — задержка <100µs.

---

## Размеры

| Поле | Тип | Значение |
|---|---|---|
| `width`, `height` | `number` | Пиксели (логические points) |
| `width: '50%'` | `string` | Процент от родителя |
| `width: 'auto'` | `string` | По intrinsic content (default для большинства) |
| `minWidth`, `maxWidth` и пр. | `number` | Только пиксели |

**Text intrinsic size:** Lumen измеряет текст через `CTFramesetter…` и
кладёт в Yoga measure-callback. Не нужно явно ставить `height` для
текста — он сам померяется. Но если знаешь высоту заранее (например,
для virtualized списка) — поставь, это сэкономит измерение.

---

## Дизайн-токены

Lumen не навязывает theme system. Рекомендуемый паттерн (см.
`Examples/BankApp/src/lib/colors.ts`):

```ts
// lib/colors.ts
export const colors = {
  bg: '#0B0B0F',
  surface: '#16161D',
  accent: '#7B6CFF',
  positive: '#3CD18E',
  negative: '#FF6B6B',
  textPrimary: '#FFFFFF',
  textSecondary: '#A8A8B8',
} as const

export const radius = {
  card: 18,
  pill: 999,
  control: 14,
} as const

export const space = {
  xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32,
} as const
```

Потом везде:

```ts
import { colors, space, radius } from './lib/colors'

View({ padding: space.lg, backgroundColor: colors.surface, borderRadius: radius.card })
```

Никакой магии — просто константы. Меняешь палитру → меняется во всём
приложении.

---

## Safe area

Реактивные insets лежат в `lumen.safeArea`:

```ts
View({
  paddingTop: lumen.safeArea.top + 16,
  paddingBottom: lumen.safeArea.bottom + 16,
})
```

При повороте устройства, открытии клавиатуры, изменении статус-бара —
эти значения меняются, и узлы, читавшие их, перерендериваются.

---

## Темная / светлая тема

`lumen.appearance.theme` — `'dark' | 'light'`, реактивно:

```ts
const bg = computed(() => lumen.appearance.theme === 'dark' ? '#0B0B0F' : '#FFFFFF')

View({ flex: 1, backgroundColor: () => bg.value })
```

---

## Дальше

→ [04 — Reactivity](04-reactivity.md): signals, computed, effect,
Slot, thunks — как делать обновления эффективно.
