// Lumen Bank — entry point.
//
// `mount(component)` запускает root effect: каждый раз когда component-fn
// читает signal и тот меняется — Lumen reconciler перерисует delta.
// На большом приложении мы НЕ хотим, чтобы root rerun'ился на любой
// signal-change — для этого:
//   • Page'и используют Slot/thunk для локально-реактивных подвыборок,
//   • root rerender'ится только на смену top-level page state (которого
//     здесь нет — навигация идёт через native router.push, каждая страница
//     mount'ится в свой view controller отдельно).
//
// Здесь root просто рендерит home-страницу. Дальше переходы идут через
// `lumen.router.push` — каждая открытая page получает свой engine-effect
// внутри своего LumenPageViewController'а.

import { homePage } from './pages/home'

mount(() => homePage().render())
