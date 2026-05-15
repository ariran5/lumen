// Typed router on top of native `lumen.router.push`.
//
// Why this instead of calling `lumen.router.push` directly:
//   • One typed list of routes — the IDE suggests page names
//     and params, typos are caught at compile-time.
//   • Pages register in a registry (see `routes.ts`) instead of being imported
//     everywhere — this breaks circular imports between pages:
//     home → openTransactions → transactions.ts; transactions → openHome
//     would otherwise loop.
//   • One `open(name, params)` helper — a central point for analytics,
//     guards (auth), and navigation logging when needed.

import { routes, type RouteName, type RouteParams } from '../routes'

export function open<N extends RouteName>(
  name: N,
  params?: RouteParams[N],
): void {
  const route = routes[name]
  if (!route) {
    console.warn('router.open: unknown route', name)
    return
  }
  const page = route.build(params as never)
  lumen.router.push({
    title: route.title,
    render: page.render,
    onPop: page.onPop,
  })
}

export function back(): void {
  lumen.router.pop()
}

export function home(): void {
  lumen.router.popToRoot()
}
