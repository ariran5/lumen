# 10 — Project structure

Для приложений размером больше "Hello world" — нужен план директорий.
Эта глава — рекомендуемый layout, который используется в
`Examples/BankApp` (10+ экранов, signals, async services, biometric guard).

---

## Рекомендуемая структура

```
my-app/
├── manifest.json
├── tsconfig.json
├── lumen-types.d.ts
└── src/
    ├── index.ts               # entry: mount(root)
    ├── routes.ts              # registry для router.push
    │
    ├── lib/                   # фундамент, без UI и реактивности
    │   ├── colors.ts          # дизайн-токены (палитра, radius, space)
    │   ├── format.ts          # money / date / number форматирование
    │   └── router.ts          # типизированная обёртка над lumen.router
    │
    ├── state/                 # shared state — module-level signals
    │   ├── account.ts
    │   ├── transactions.ts
    │   └── ui.ts              # activeTab, sheetOpen, etc.
    │
    ├── services/              # async I/O (HTTP, WS, storage)
    │   └── bank-api.ts
    │
    ├── components/            # reusable UI primitives
    │   ├── header.ts
    │   ├── glass-card.ts
    │   ├── amount.ts
    │   ├── tab-bar.ts
    │   └── pill-button.ts
    │
    ├── sheets/                # bottom-sheet open-функции
    │   ├── send.ts
    │   ├── deposit.ts
    │   └── tx-preview.ts
    │
    └── pages/                 # роутед-экраны
        ├── home.ts
        ├── transactions.ts
        ├── transaction-detail.ts
        ├── cards.ts
        └── profile.ts
```

---

## Разделение ответственностей

### `lib/` — чистая логика

- Нет `View(...)` / `Text(...)` — нет UI.
- Нет `signal(...)` на module-level — это не shared state.
- Только функции и константы.

Пример: `lib/format.ts`

```ts
export function money(cents: number): string {
  const sign = cents < 0 ? '-' : ''
  const abs = Math.abs(cents)
  const dollars = Math.floor(abs / 100)
  const c = abs % 100
  return `${sign}$${dollars}.${c.toString().padStart(2, '0')}`
}

export function shortDate(unixMs: number): string {
  const d = new Date(unixMs)
  return `${d.getMonth() + 1}/${d.getDate()}`
}
```

### `state/` — shared state

- Module-level `signal(...)` / `computed(...)`.
- Action-функции для мутаций (не пиши `.value` напрямую снаружи).
- Никакого UI.

```ts
// state/account.ts
export const balanceCents = signal<number>(241_85_00)

export function applyDelta(deltaCents: number): void {
  balanceCents.value = balanceCents.peek() + deltaCents
}
```

```ts
// state/transactions.ts
export const transactions = signal<Tx[]>([])
export const visibleTransactions = computed<Tx[]>(() => {
  return transactions.value.filter(...)
})

export function addTransaction(input: Omit<Tx, 'id' | 'at'>): Tx {
  const tx = { ...input, id: nextID++, at: Date.now() }
  transactions.value = [tx, ...transactions.value]
  applyDelta(tx.amountCents)
  return tx
}
```

**Зачем action-функции:** единая точка для каждого изменения. Хочешь
залогировать все мутации? Один edit. Хочешь добавить optimistic update?
Один edit. Если страницы пишут в `transactions.value` напрямую — каждое
изменение нужно искать через grep.

### `services/` — async I/O

- HTTP, WebSocket, storage access, любые `await`.
- Бросают типизированные ошибки (`BankAPIError`).
- Возвращают чистые data-объекты.

```ts
// services/bank-api.ts
export class BankAPIError extends Error {
  constructor(public code: string, message: string) { super(message) }
}

export async function makeTransfer(req: TransferRequest): Promise<TransferResult> {
  const r = await fetch(...)
  if (!r.ok) throw new BankAPIError('SERVER', ...)
  return await r.json()
}
```

### `components/` — UI без бизнес-логики

- Принимают props, возвращают `RenderNode`.
- Можно использовать signals/computed из `state/`.
- Не делают `fetch`, не знают про конкретные страницы.

```ts
// components/amount.ts
import { colors } from '../lib/colors'
import { money } from '../lib/format'

interface AmountProps {
  cents: number | Thunk<number>
  size?: number
  weight?: '600' | '700'
}

export function Amount(p: AmountProps): RenderNode {
  const size = p.size ?? 16
  const weight = p.weight ?? '600'

  // Цвет реактивен от знака суммы
  const color: Thunk<string> = () => {
    const c = typeof p.cents === 'function' ? p.cents() : p.cents
    return c < 0 ? colors.negative : colors.positive
  }
  const text: Thunk<string> = () => {
    const c = typeof p.cents === 'function' ? p.cents() : p.cents
    return money(c)
  }

  return Text({ fontSize: size, fontWeight: weight, color }, text)
}
```

### `pages/` — экраны

- Знают о бизнес-state.
- Импортят `services/` и `state/`.
- Экспортируют page-factory.

```ts
// pages/home.ts
import { balanceCents } from '../state/account'
import { Amount } from '../components/amount'

export function homePage() {
  return {
    render: () => View({ flex: 1, padding: 16 },
      Text({ fontSize: 13 }, 'Balance'),
      Amount({ cents: () => balanceCents.value, size: 32, weight: '700' }),
    ),
  }
}
```

Если на странице есть локальный state (форма, scroll position) —
объяви его внутри factory:

```ts
export function transferPage() {
  // local state — свежий на каждый push
  const amount = signal('')
  const submitting = signal(false)

  return {
    render: () => ...,
    onPop: () => saveDraft(amount.peek()),
  }
}
```

### `sheets/` — bottom-sheet flows

Bottom-sheet ≠ страница. Это модальное действие. Удобно держать
"open-функции" в отдельной папке:

```ts
// sheets/send.ts
export function openSendSheet(): void {
  const amount = signal('')

  lumen.bottomSheet({
    height: 'medium',
    content: View({ flex: 1, padding: 24, gap: 12 },
      Text({ fontSize: 24, fontWeight: '700' }, 'Send money'),
      TextInput({
        value: amount.value,
        onChange: e => amount.value = e.value,
        keyboardType: 'decimal',
      }),
      Pressable({ onTap: () => submit() }, ...),
    ),
    onClose: () => {},
  })
}
```

---

## Реактивные границы

### Один root mount

```ts
mount(() => View({ flex: 1 },
  Slot({ flex: 1 }, () => tabFactories[activeTab.value]().render()),
  TabBar(),
))
```

**Только один** `mount` на весь app. Остальная реактивность — через
signal'ы и `Slot`'ы внутри.

### Tab — pages пересоздаются на switch

`Slot({}, () => factories[active.value]().render())` — при смене tab'а
page-factory вызывается заново. Локальный state страницы (формы,
scroll position) теряется. Если он нужен — поднимай в `state/`.

### Push — отдельный mount

`lumen.router.push({ render })` создаёт **новый ViewController** с
**своим** mount-effect'ом. От текущей страницы изолирован.

### Sheet — отдельный nested Renderer

`lumen.bottomSheet({ content })` тоже изолирован. Внутри sheet'а
можно делать свой реактивный subtree.

---

## Что класть в circular-import-разорвущий слой

Если `pages/transactions.ts` импортит `pages/home.ts` (потому что
"see all" возвращает на home), и `home.ts` импортит `transactions.ts`
(чтобы открыть детали) — будет cycle.

Решение — `routes.ts` как посредник:

```ts
// routes.ts знает о всех страницах
import { homePage } from './pages/home'
import { transactionsPage } from './pages/transactions'

// home.ts и transactions.ts НЕ импортят друг друга
// они импортят { open } from '../lib/router'
// который читает routes.ts
```

---

## TypeScript settings

`tsconfig.json` из шаблона `lumen init`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2020"],
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "types": []
  },
  "files": [
    "lumen-types.d.ts",
    "index.ts"
  ]
}
```

Важно:
- **`"lib": ["ES2020"]`** — без `"DOM"`. `Text` и `Image` глобальны как
  фабрики Lumen, не как DOM-классы — DOM lib бы их перекрыл.
- **`"strict": true`** — Lumen API типизирован полностью, strict
  ловит реальные ошибки.

Для multi-file проекта добавь `"include": ["src/**/*.ts"]` вместо `files`:

```json
{
  ...
  "include": ["src/**/*.ts", "lumen-types.d.ts"]
}
```

---

## Дальше

→ [11 — Build & deploy](11-build-and-deploy.md): production-сборка,
манифест на хостинге.
