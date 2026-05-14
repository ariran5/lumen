# Lumen Bank — multi-file fast-app example

Реальный шаблон того, как структурировать средне-большой Lumen fast-app:
разделение по ответственностям, типизированный роутинг, shared state
через signals, async service layer, дизайн-токены.

Если ты пишешь "Hello world" — смотри `Examples/HelloApp`. Это пример
для приложения уровня "10+ экранов".

## Структура

```
BankApp/
├── manifest.json              # имя, версия, entry, permissions, connect
├── tsconfig.json              # подключает @lumen/types
└── src/
    ├── index.ts               # entry: mount(home)
    ├── routes.ts              # route registry (имя → page-factory)
    │
    ├── lib/                   # фундамент, нерактивный, без UI
    │   ├── colors.ts          # дизайн-токены (палитра, radius, space)
    │   ├── format.ts          # money / date форматирование
    │   └── router.ts          # типизированная обёртка над lumen.router
    │
    ├── state/                 # shared state — module-level signals
    │   ├── account.ts         # balance, holder, IBAN
    │   └── transactions.ts    # список + filter + computed агрегаты
    │
    ├── services/              # async I/O (mock или live HTTP/WS)
    │   └── bank-api.ts        # makeTransfer / receiveDeposit (Promise)
    │
    ├── components/            # reusable UI primitives
    │   ├── header.ts          # верхняя плашка
    │   ├── glass-card.ts      # surface-обёртка
    │   ├── amount.ts          # money display с цветом по знаку
    │   ├── tx-row.ts          # ряд в списке транзакций
    │   └── pill-button.ts     # primary CTA
    │
    └── pages/                 # роутед-экраны
        ├── home.ts            # dashboard
        ├── transactions.ts    # список с фильтрами
        ├── transaction-detail.ts
        ├── transfer.ts        # форма перевода
        └── profile.ts         # настройки + dev tools
```

## Конвенции

**lib/ vs components/ vs pages/.**
`lib/` — чистая логика, без `View(...)` (никакого UI). `components/` —
переиспользуемые UI-блоки без бизнес-логики. `pages/` — то, что
открывает роутер; знает о бизнес-state и сервисах.

**State.** Module-level `signal(...)`. Импортишь `balanceCents` —
получаешь тот же signal во всех страницах. Мутации идут через
action-функции (`applyDelta`, `addTransaction`), а не прямым присваиванием
извне — это даёт один call-graph для всех изменений.

**Service layer.** Async-функции в `services/`. Возвращают Promise.
Бросают `BankAPIError` для ожидаемых ошибок (page ловит в try/catch),
обычный `Error` для прочих. UI ждёт через локальный `isSubmitting`
signal и блокирует submit-кнопку.

**Router.** Один typed entry-point — `open('transactions')` /
`open('transactionDetail', { id })`. Список route'ов в `routes.ts`.
Этот слой делает три вещи: типизирует имена и params, разрывает
circular import'ы между страницами, и даёт одну точку для аналитики
/ guard'ов / логирования навигации.

**Reactivity boundaries.** Root mount рендерит ОДНУ страницу — home.
Переход на другую страницу = native `router.push`, новый view controller,
новый mount-effect внутри. То есть переход НЕ перерисовывает home — он
просто над ней. Локально-реактивные списки используют `Slot(thunk)`,
чтобы при изменении list-signal'а ребилдился ТОЛЬКО subtree слота, а
не весь экран.

**Page = factory.** Каждая страница экспортирует `xxxPage(params?)`
возвращающий `{ render, onPop? }`. Локальный state (формы, scroll
position, loading-флаги) создаётся внутри фабрики через `signal(...)` —
каждое открытие страницы получает свежую копию state'а.

## Запуск

### Production build (multi-file работает гарантированно)

```bash
cd Examples/BankApp
bun run --filter @lumen/cli build .   # или: lumen build
# → dist/bundle.js + dist/manifest.json
```

Затем разверни `dist/` за любым static-сервером (например `bun --hot serve`,
`npx serve`, nginx) и открой URL в Lumen.

### Dev mode

```bash
cd Examples/BankApp
bun run --filter @lumen/cli dev .   # или: lumen dev
```

Dev-сервер бандлит entry на лету (TypeScript+ESM → IIFE для JSC), при
смене любого файла WebSocket пушит hot-reload в открытый таб.

## Что демонстрирует

| Концепт | Где смотреть |
|---|---|
| `import` между модулями | везде |
| Module-level signals (shared state) | `state/account.ts`, `state/transactions.ts` |
| `computed` (filtered / aggregated) | `state/transactions.ts` (visibleTransactions, monthIncome) |
| `Slot` для локально-реактивных списков | `pages/home.ts` recent, `pages/transactions.ts` list |
| Per-prop thunk reactivity | `components/amount.ts`, цветовые анимации в `pill-button.ts` |
| Typed router + params | `lib/router.ts`, `routes.ts`, `pages/transaction-detail.ts` |
| Page-local state factory | `pages/transfer.ts` |
| Async service + loading + error | `services/bank-api.ts` + `pages/transfer.ts` submit |
| Biometric guard | `pages/transfer.ts` |
| Native CTAs (haptics, alert) | `components/pill-button.ts`, `pages/transfer.ts` |
| Reactive safe-area | `components/header.ts` |
