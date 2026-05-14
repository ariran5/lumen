// Типизированный router поверх native `lumen.router.push`.
//
// Зачем это, а не вызывать `lumen.router.push` напрямую:
//   • Один типизированный список route'ов — IDE подскажет имена страниц
//     и params, опечатка ловится в compile-time.
//   • Страницы регистрируются в registry (см. `routes.ts`), а не импортятся
//     везде — это разрывает циклические import'ы между page'ами:
//     home → openTransactions → transactions.ts; transactions → openHome
//     ушло бы в круг.
//   • Один helper `open(name, params)` — central point для аналитики,
//     guard'ов (auth), и логирования навигации, когда понадобятся.

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
