// Центральный registry route'ов. Решает две задачи:
//
// 1. Избегаем circular import'ов. Если бы `lib/router.ts` сам импортил все
//    pages/*, а pages импортили `router.ts` (для перехода с дашборда на
//    список транзакций) — получился бы цикл. Здесь `routes.ts` — одно
//    место, где все pages регистрируются, и страницы общаются с router'ом
//    только через `open(name)`.
//
// 2. Типизация params: `RouteParams[name]` даёт IDE автокомплит сразу
//    после вызова `open('transactionDetail', { id: 5 })`.
//
// Добавить новую страницу = добавить ключ в `routes` ниже + тип в
// `RouteParams`. Page-файл при этом ничего знать о роутинге не должен —
// он экспортирует функцию `(params) => { render, onPop? }`.

import { homePage } from './pages/home'
import { transactionsPage } from './pages/transactions'
import { transactionDetailPage } from './pages/transaction-detail'
import { transferPage } from './pages/transfer'
import { profilePage } from './pages/profile'

interface PageInstance {
  render: () => RenderNode
  onPop?: () => void
}

interface RouteEntry<P> {
  title: string
  build: (params: P) => PageInstance
}

export interface RouteParams {
  home: void
  transactions: void
  transactionDetail: { id: number }
  transfer: void
  profile: void
}

export type RouteName = keyof RouteParams

// Каждая запись — title + factory, который принимает params и
// возвращает page instance. `as RouteEntry<unknown>` нужно чтобы
// `routes[name]` имел общий тип; type-safe вход — через `open<N>`.
export const routes: { [N in RouteName]: RouteEntry<RouteParams[N]> } = {
  home: {
    title: 'Lumen Bank',
    build: () => homePage(),
  },
  transactions: {
    title: 'Transactions',
    build: () => transactionsPage(),
  },
  transactionDetail: {
    title: 'Transaction',
    build: (p) => transactionDetailPage(p.id),
  },
  transfer: {
    title: 'Send',
    build: () => transferPage(),
  },
  profile: {
    title: 'Profile',
    build: () => profilePage(),
  },
}
