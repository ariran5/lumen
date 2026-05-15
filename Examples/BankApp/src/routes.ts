// Push-route registry. Contains ONLY pages that are opened via
// `lumen.router.push` on top of the tab-bar (transaction details, deep flow).
// Top-level pages (Home / History / Cards / Profile) are switched via
// `state/ui.ts → activeTab` and are not registered here.

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
