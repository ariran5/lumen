# Session 007 — 2026-05-13: TextInput, ScrollView, SafeArea

> Phase 5 стартовала. Direction — переписать browser-shell на самом Lumen (dogfood). Эта сессия закрывает первые три блокера: TextInput для AddressBar, ScrollView для длинных страниц, SafeArea для корректного layout под notch/home-indicator.

---

## TL;DR

| ID | Фича |
|---|---|
| P5.1 | `TextInput` — native UITextField как overlay через `kind: 'textInput'` |
| P5.2 | `ScrollView` — UIScrollView с nested Renderer внутри, intrinsic content height |
| P5.3 | `lumen.safeArea.{top,bottom,left,right}` reactive через signals |

JS-API:
```ts
TextInput({
  value: name.value,
  placeholder: 'Your name',
  keyboardType: 'url',
  returnKey: 'go',
  secure: false,
  onChange: (e) => { name.value = e.value },
  onSubmit: (e) => { /* keyboard auto-dismisses */ },
})

ScrollView({flex: 1, paddingBottom: 16 + lumen.safeArea.bottom, gap: 12},
  ...items.map(Card)
)

// SafeArea — реактивный, читай где угодно:
View({paddingTop: lumen.safeArea.top}, /* ... */)
```

Все три валидированы на iPhone 15 Pro Max — пользователь подтвердил «всё работает».

---

## P5.1 — TextInput

[Sources/LumenRuntime/TextInputView.swift](../Sources/LumenRuntime/TextInputView.swift) — `LumenTextField: UITextField` с padding-overrides + `TextInputController: NSObject, UITextFieldDelegate`. Паттерн overlay тот же что у VirtualList: native UIView сидит как subview hostView с absolute frame из flex.

### Props

```ts
interface TextInputProps {
  value: string                          // controlled
  placeholder?: string
  keyboardType?: 'default' | 'url' | 'email' | 'number' | 'decimal' | 'phone' | 'search'
  returnKey?: 'default' | 'go' | 'next' | 'done' | 'search' | 'send' | 'continue'
  autocapitalize?: 'none' | 'sentences' | 'words' | 'characters'
  autocorrect?: boolean                   // false для url-style
  secure?: boolean                        // password
  onChange?: (e: {value: string}) => void
  onSubmit?: (e: {value: string}) => void // Return → keyboard auto-dismiss
  onFocus?: () => void
  onBlur?: () => void
  // + FlexProps, VisualProps, TextStyleProps
}
```

### Controlled-value

Renderer на reconcile вызывает `controller.apply(value: ...)`. Внутри:
```swift
if field.text != value {
    field.text = value
}
```
Без этой проверки iOS сбросит cursor position на end-of-text на каждый keystroke (re-render от signal'а).

### Стиль

Apply применяется напрямую к UITextField:
- `backgroundColor` → `field.backgroundColor` (CGColor → UIColor)
- `borderRadius` → `field.layer.cornerRadius` + `masksToBounds`
- `borderColor/borderWidth` → `field.layer.*`
- `fontSize/fontWeight/fontFamily` → `field.font` via `TextMeasure.font(for:)`
- `color` → `field.textColor`
- `opacity` → `field.alpha`
- `padding` из flex.padding → custom `UIEdgeInsets` через `textRect(forBounds:)` overrides

### Demo

[Examples/InputLab/](../Examples/InputLab/) — три поля: Name (autocapitalize: words), URL (keyboardType: url + returnKey: go), Password (secure). Header показывает live-значения, доказывает что controlled-value работает.

Validated on iPhone:
- Каретка не прыгает на keystroke ✓
- Return в URL-поле → onSubmit + клавиатура уезжает ✓
- Password скрывает символы ✓
- Правильные клавиатуры (URL = с `.com`/`/`, password = обычная) ✓

---

## P5.2 — ScrollView

[Sources/LumenRuntime/ScrollView.swift](../Sources/LumenRuntime/ScrollView.swift) — `LumenScrollView: UIScrollView` с **nested Renderer** внутри.

### Архитектура

```
hostView (main host)
└── LumenScrollView  (UIScrollView, frame = flex.frame of scroll-node)
    └── contentView  (UIView)
        └── contentView.layer  ← rootLayer для nested Renderer
            └── …дерево children scroll-узла…
```

Главный трюк — **nested Renderer в режиме `.scrollContent`**:

```swift
extension Renderer {
    enum ContentMode { case stretch, scrollContent }
    var contentMode: ContentMode = .stretch
}
```

В `relayout()`:
- `.stretch` (default) — layout с `(rootLayer.bounds.width, rootLayer.bounds.height)`
- `.scrollContent` — layout с `(rootLayer.bounds.width, .greatestFiniteMagnitude)`. Дети получают свои intrinsic размеры (P2.3 ready), натурально стэкаются сверху.

После layout сохраняется `lastFlexRoot`. `computedContentHeight()`:
```swift
let maxY = root.children.map { $0.frame.maxY }.max() ?? 0
return maxY + CGFloat(root.style.padding.bottom)
```

LumenScrollView получает это число, ставит `contentView.frame.height` и `scrollView.contentSize`.

### Synthetic wrapper

Scroll-узел передаёт свои children + style в LumenScrollView. Внутри мы оборачиваем в synthetic column-View чтобы padding/gap из style применились к layout:

```swift
var wrapper = RenderNode()
wrapper.kind = .view
wrapper.style = lastWrapperStyle       // padding/gap из scroll-узла
wrapper.style.flex.direction = .column
wrapper.style.flex.height = .auto
wrapper.style.flex.width = .auto
wrapper.children = lastRenderedChildren
renderer.render(wrapper)
```

### Жесты

Каждая ячейка внутри ScrollView — обычный Lumen-узел (Pressable/View с onTap и т.д.). Nested Renderer создаёт **свой GestureRouter** на contentView. Touches проходят как обычно. UIScrollView's pan-gesture работает независимо для vertical scrolling.

### Demo

[Examples/ScrollLab/](../Examples/ScrollLab/) — 40 Pressable-карточек, тап-handler меняет header. paddingBottom использует `lumen.safeArea.bottom` чтобы нижняя карточка не уехала под home-indicator.

Validated on iPhone: scroll плавный, momentum/bounce работает, тап по карточкам ловится, indicator справа виден.

### Known limitations

- Только **vertical** scroll. Horizontal — отдельная задача, потребует `direction` prop и аналогичную computedContentWidth.
- Жесты `onPan` внутри ScrollView могут конфликтовать со scroll'овским pan, если ребёнок реагирует на vertical drag. UIScrollView обычно «выигрывает» через свой gestureRecognizer.delaysTouchesBegan. Если станет проблемой — добавим конфликт-руление через `simultaneouslyWith`.
- Nested Renderer создаёт ещё один JSContext-bridge? Нет — он переиспользует тот же rootLayer-pipeline без своего JSEngine. Но имеет свой GestureRouter (1 lightweight инстанс).

---

## P5.3 — SafeArea

[Sources/LumenRuntime/JSEngine+SafeArea.swift](../Sources/LumenRuntime/JSEngine+SafeArea.swift) + [LumenPageViewController.swift](../Sources/LumenRuntime/LumenPageViewController.swift) + [CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift).

**Реактивный** API через signals внутри CoreFramework:

```js
const _saT = signal(0), _saB = signal(0), _saL = signal(0), _saR = signal(0)
Object.defineProperty(lumen, 'safeArea', {
  value: Object.freeze({
    get top()    { return _saT.value },
    get bottom() { return _saB.value },
    get left()   { return _saL.value },
    get right()  { return _saR.value },
  }),
  writable: false, configurable: false
})
lumen._updateSafeArea = function (t, b, l, r) {
  _saT.value = t; _saB.value = b; _saL.value = l; _saR.value = r
}
```

Native сторона: `LumenPageViewController.viewSafeAreaInsetsDidChange()` дёргает `onSafeAreaChange` callback, который Coordinator в [FastAppHost.swift](../Sources/LumenShell/FastAppHost.swift) хукает к `engine.updateSafeArea(insets)`. Тот зовёт `lumen._updateSafeArea(t,b,l,r)`.

Сценарий:
1. Компонент читает `lumen.safeArea.bottom` в `mount` effect.
2. Сигнал _saB субскрибит этот effect.
3. Rotation / keyboard / status-bar изменение → viewSafeAreaInsetsDidChange → push в _saB.value → microtask → effect.\_run → re-render.

Это **первый случай native → JS reactive sync** в Lumen. Та же модель будет использоваться для других системных значений (orientation, theme).

### Initial value

При setupEngine сразу дёргается `engine.updateSafeArea(rootPage.view.safeAreaInsets)` — на этот момент insets могут быть (0,0,0,0) до первой layout-проходки. `viewSafeAreaInsetsDidChange` придёт позже с реальными значениями.

---

## Renderer изменения

[Sources/LumenRuntime/Renderer.swift](../Sources/LumenRuntime/Renderer.swift):

- Добавлен `ContentMode` enum + `contentMode` property
- Сохраняется `lastFlexRoot` для `computedContentHeight()`
- В `mountFresh`: ранний return для `kind: .scroll` (как уже было для virtualList/textInput)
- В `reconcile`: kind-swap branch обнуляет `scrollView` ref; branches для `.scroll` и `.textInput`
- `removeMountTree` чистит `scrollView/textInputView/textInputController`
- В `relayout` width-check (height не блокирует в scrollContent режиме)

[Sources/LumenRuntime/RenderNode.swift](../Sources/LumenRuntime/RenderNode.swift):

- `Kind` обогащён `.textInput`
- (`scroll` уже был, но не использовался — теперь mounted)
- Поля: `inputValue/Placeholder/KeyboardType/ReturnKey/Autocapitalize/Autocorrect/Secure`, handler'ы `onInputChange/Submit/Focus/Blur`
- Парсинг этих полей в `parseValue` при `kind == .textInput`

---

## CoreFramework изменения

[Sources/LumenRuntime/CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift):

- `TextInput(props)` builder — НЕ принимает children (leaf-node)
- `ScrollView(props, ...children)` builder
- `NON_STYLE` расширен новыми input-props (`value/placeholder/keyboardType/returnKey/autocapitalize/autocorrect/secure/onChange/onSubmit/onFocus/onBlur`)
- SafeArea-блок: `_saT/B/L/R` signals + `lumen.safeArea` getters + `lumen._updateSafeArea`
- Все три builder'а доступны как `globalThis.{TextInput,ScrollView}` + namespace `lumen.core`

---

## Файлы

### Новые
- [Sources/LumenRuntime/TextInputView.swift](../Sources/LumenRuntime/TextInputView.swift) — LumenTextField + TextInputController
- [Sources/LumenRuntime/ScrollView.swift](../Sources/LumenRuntime/ScrollView.swift) — LumenScrollView с nested Renderer
- [Sources/LumenRuntime/JSEngine+SafeArea.swift](../Sources/LumenRuntime/JSEngine+SafeArea.swift) — `installSafeAreaBridge`, `updateSafeArea(insets:)`
- [Examples/InputLab/](../Examples/InputLab/) — Name/URL/Password fields demo
- [Examples/ScrollLab/](../Examples/ScrollLab/) — 40 cards in scroll demo

### Расширены
- [Sources/LumenRuntime/Renderer.swift](../Sources/LumenRuntime/Renderer.swift) — ContentMode + scroll/textInput integration
- [Sources/LumenRuntime/RenderNode.swift](../Sources/LumenRuntime/RenderNode.swift) — textInput parsing + поля
- [Sources/LumenRuntime/CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift) — TextInput/ScrollView builders + safe-area signals
- [Sources/LumenRuntime/JSEngine+Platform.swift](../Sources/LumenRuntime/JSEngine+Platform.swift) — `installSafeAreaBridge()` call
- [Sources/LumenRuntime/LumenPageViewController.swift](../Sources/LumenRuntime/LumenPageViewController.swift) — `onSafeAreaChange` callback + `viewSafeAreaInsetsDidChange` override
- [Sources/LumenShell/FastAppHost.swift](../Sources/LumenShell/FastAppHost.swift) — wire safeArea push в setupEngine
- [packages/lumen-types/index.d.ts](../packages/lumen-types/index.d.ts) — TextInputProps, ScrollViewProps, lumen.safeArea types

---

## Что осталось из плана

- ~~P4.2.a/b/c gestures + transform + animations~~ ✓
- ~~P5.1 TextInput~~ ✓
- ~~P5.2 ScrollView~~ ✓
- ~~P5.3 SafeArea~~ ✓
- **P5.4 Blur** ← следующий — UIVisualEffectView overlay для glass-pills из концептов
- **P5.5 lumen.tabs.*** API + TabsStore (multi-tab model)
- **P5.6 Shell-as-fast-app** — bundle в App resources, грузится с `lumen://shell`
- **P5.7 Home / Library / TabSwitcher** на Lumen по макетам (с дизайн-обсуждением)
- **Showcase: Lumen landing page** (после ScrollView+SafeArea+Blur)
- P4.3 — Bytecode caching (отложен)
- P4.5 — Permissions
- DevTools / Inspector (P3.5)

---

## Дальше — Blur

Следующая короткая сессия: **Blur** — UIVisualEffectView как overlay (паттерн textInput/scroll). Props: `intensity: 'thin' | 'regular' | 'chrome' | 'systemMaterial'`. Нужен для glass-эффектов в shell — date-pill, corner-pill, status overlay.

После Blur — `lumen.tabs.*` API, и далее shell-as-fast-app.
