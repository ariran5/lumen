# 06 — Navigation

В Lumen два независимых navigation-механизма:

1. **`lumen.router`** — push/pop стек **native UINavigationController**.
   Свайп от края назад, smooth transitions, заголовок в нав-баре —
   всё нативное.
2. **Tab-switching** — это **просто signal**. Никакого специального
   API. Сам собираешь tab-bar и переключаешь `activeTab.value`.

---

## `lumen.router` — push/pop

### push

```ts
lumen.router.push({
  title: 'Details',
  render: () => View({ flex: 1, padding: 16 },
    Text({ fontSize: 24 }, 'Detail page'),
  ),
  onPop: () => console.log('user went back'),
})
```

Откроется как native push: title в нав-баре, swipe-back работает.

`render` — функция, возвращающая дерево. Mount-effect внутри новой
страницы запускается изолированно от текущей — это другой ViewController.

### pop / popToRoot / setTitle

```ts
lumen.router.pop()           // назад на один экран
lumen.router.popToRoot()     // на root
lumen.router.setTitle('New title')   // обновить title в navbar
```

---

## Типизированный routes registry (паттерн)

Прямые вызовы `lumen.router.push({ render: () => ... })` работают, но в
средне-большом приложении возникают проблемы:

- Каждая страница импортит другие — циклические import'ы.
- Имена страниц нигде не зарегистрированы — опечатки не ловятся.
- Нет одной точки для аналитики/guard'ов.

Паттерн из `Examples/BankApp` (рекомендуемый):

### `routes.ts`

```ts
import { transactionDetailPage } from './pages/transaction-detail'
import { settingsPage } from './pages/settings'

interface PageInstance {
  render: () => RenderNode
  onPop?: () => void
}

interface RouteEntry<P> {
  title: string
  build: (params: P) => PageInstance
}

export interface RouteParams {
  transactionDetail: { id: number }
  settings: void
}

export type RouteName = keyof RouteParams

export const routes: { [N in RouteName]: RouteEntry<RouteParams[N]> } = {
  transactionDetail: {
    title: 'Transaction',
    build: (p) => transactionDetailPage(p.id),
  },
  settings: {
    title: 'Settings',
    build: () => settingsPage(),
  },
}
```

### `lib/router.ts`

```ts
import { routes, type RouteName, type RouteParams } from '../routes'

export function open<N extends RouteName>(
  name: N,
  params?: RouteParams[N],
): void {
  const route = routes[name]
  const page = route.build(params as never)
  lumen.router.push({
    title: route.title,
    render: page.render,
    onPop: page.onPop,
  })
}

export function back(): void { lumen.router.pop() }
export function home(): void { lumen.router.popToRoot() }
```

### Использование

```ts
import { open } from './lib/router'

Pressable({ onTap: () => open('transactionDetail', { id: tx.id }) }, ...)
```

TypeScript подскажет имена route'ов и проверит params на compile-time.

### Зачем page-factory возвращает `{ render, onPop? }`

Page-factory может создать локальный state и вернуть functions:

```ts
// pages/transaction-detail.ts
export function transactionDetailPage(id: number) {
  const note = signal('')
  // ... другой local state ...

  return {
    render: () => View({ flex: 1 },
      Text(() => `tx ${id}`),
      TextInput({ value: () => note.value, onChange: e => note.value = e.value }),
    ),
    onPop: () => {
      // сохранить note перед закрытием
      saveNote(id, note.peek())
    },
  }
}
```

Каждое открытие — свежий state. Закрытие — `onPop` сработает.

---

## Tab-bar — это не специальный API

Tab-bar — просто компонент, который меняет signal:

### `state/ui.ts`

```ts
export type TabKey = 'home' | 'history' | 'cards' | 'profile'

export const activeTab = signal<TabKey>('home')
export const TAB_BAR_HEIGHT = 64
```

### `components/tab-bar.ts`

```ts
import { activeTab, type TabKey, TAB_BAR_HEIGHT } from '../state/ui'

export function TabBar(): RenderNode {
  return Glass({
    position: 'absolute',
    left: 16, right: 16,
    bottom: lumen.safeArea.bottom + 8,
    height: TAB_BAR_HEIGHT,
    borderRadius: 32,
    flexDirection: 'row',
  },
    tabItem('home', '⌂', 'Home'),
    tabItem('history', '≡', 'History'),
    tabItem('cards', '⊟', 'Cards'),
    tabItem('profile', '◯', 'You'),
  )
}

function tabItem(key: TabKey, icon: string, label: string): RenderNode {
  return Pressable({
    onTap: () => {
      lumen.haptics('soft')
      activeTab.value = key
    },
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
  },
    Text({ fontSize: 18, color: () => activeTab.value === key ? '#FFFFFF' : '#9CA3AF' }, icon),
    Text({ fontSize: 10, color: () => activeTab.value === key ? '#FFFFFF' : '#9CA3AF' }, label),
  )
}
```

### `index.ts` — root mount

```ts
import { homePage } from './pages/home'
import { historyPage } from './pages/history'
import { cardsPage } from './pages/cards'
import { profilePage } from './pages/profile'
import { TabBar } from './components/tab-bar'
import { activeTab } from './state/ui'

const tabFactories = {
  home: homePage,
  history: historyPage,
  cards: cardsPage,
  profile: profilePage,
}

mount(() => View({ flex: 1, backgroundColor: '#0B0B0F' },

  // Slot — при смене activeTab пересобирается ТОЛЬКО это subtree,
  // root mount-effect не реран.
  Slot({ flex: 1 }, () => tabFactories[activeTab.value]().render()),

  TabBar(),
))
```

---

## Совмещение tab + push

В банк-апе:
- Tab-bar: 4 главных раздела, переключение signal'ом.
- Push: детали транзакции, settings — открываются поверх tab'а через
  `open('transactionDetail', { id })`.
- iOS автоматически прячет tab-bar когда push'ишь страницу — это
  поведение `UINavigationController` (если tab-bar — overlay через
  `position: 'absolute'`, его придётся прятать вручную через signal).

### Прячем tab-bar когда открыт sheet

```ts
// state/ui.ts
export const sheetOpen = signal(false)

// перед открытием bottom-sheet:
sheetOpen.value = true
lumen.bottomSheet({
  content: ...,
  onClose: () => { sheetOpen.value = false },
})

// в root mount:
Slot({}, () => sheetOpen.value ? null : TabBar())
```

Иначе на iOS 26 (floating sheet at medium detent) tab-bar торчит из-под
sheet'а в нижнем margin'е.

---

## Bottom-sheet vs router.push

Какой выбрать для нового экрана:

| Сценарий | Что использовать |
|---|---|
| Список / детальный просмотр / форма с заголовком | `router.push` |
| Модальное действие (Send/Deposit, выбор опции) | `bottomSheet` |
| Confirmation / простой prompt | `alert` / `actionSheet` |
| Quick preview без полной навигации | `bottomSheet` с `height: 'small'` или `'medium'` |

Эвристика: если экран должен быть «как часть приложения, я могу пойти
ещё глубже» → push. Если «это модальное действие, я закрою и вернусь
в прошлый контекст» → sheet.

---

## Дальше

→ [07 — Data: fetch & storage](07-data-fetch-storage.md): сеть, хранение,
sandbox `connect`.
