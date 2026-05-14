// App root. Mount-effect рендерит активный таб + tab-bar.
//
// Архитектура top-level навигации:
//   • 4 tab'а — переключение через `activeTab.value = ...` (signal,
//     module-level в state/ui.ts), root перерендеривает выбранный
//     page-factory'ем.
//   • Sub-страницы пушатся через `lumen.router.push` (см. lib/router.ts +
//     routes.ts) — на iOS они закрывают tab-bar visually, и swipe-from-edge
//     возвращает обратно.
//   • Action flows (Send / Deposit / Tx preview / Card actions) — bottom-sheet'ы,
//     не пушатся в стек.

import { TabBar } from './components/tab-bar'
import { colors } from './lib/colors'
import { activeTab, type TabKey } from './state/ui'
import { homePage } from './pages/home'
import { transactionsPage } from './pages/transactions'
import { cardsPage } from './pages/cards'
import { profilePage } from './pages/profile'

// Mapping таб → page-factory. Каждый key пересоздаёт page при свитче —
// дешёво, ничего не теряется кроме per-tab локального state'а (если он
// есть, поднимай в state/* модули как делает account/transactions).
const tabFactories: { [K in TabKey]: () => { render: () => RenderNode } } = {
  home: homePage,
  history: transactionsPage,
  cards: cardsPage,
  profile: profilePage,
}

mount(() => View(
  { flex: 1, backgroundColor: colors.bg },

  // Slot оборачивает tab content — при смене activeTab ребилдится ТОЛЬКО
  // этот subtree, root-mount-effect (`mount(...)`) сам не реран.
  Slot({ flex: 1 }, () => tabFactories[activeTab.value]().render()),

  // Glass tab-bar поверх контента. Position 'absolute' внутри bar'а
  // самого — gradient/translucency видны над scroll'ом.
  TabBar(),
))
