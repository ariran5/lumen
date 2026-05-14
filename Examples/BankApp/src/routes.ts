// Push-route registry. Содержит ТОЛЬКО страницы, которые открываются
// `lumen.router.push` поверх tab-bar'а (детали транзакции, дип-флоу).
// Top-level страницы (Home / History / Cards / Profile) переключаются
// через `state/ui.ts → activeTab` и здесь не регистрируются.

import { transactionDetailPage } from './pages/transaction-detail'

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
}

export type RouteName = keyof RouteParams

export const routes: { [N in RouteName]: RouteEntry<RouteParams[N]> } = {
  transactionDetail: {
    title: 'Transaction',
    build: (p) => transactionDetailPage(p.id),
  },
}
