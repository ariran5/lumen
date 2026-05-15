// App root. Mount-effect renders the active tab + tab-bar.
//
// Top-level navigation architecture:
//   • 4 tabs — switching via `activeTab.value = ...` (signal,
//     module-level in state/ui.ts), root re-renders via the selected
//     page-factory.
//   • Sub-pages are pushed via `lumen.router.push` (see lib/router.ts +
//     routes.ts) — on iOS they visually hide the tab-bar, and swipe-from-edge
//     returns back.
//   • Action flows (Send / Deposit / Tx preview / Card actions) are bottom-sheets,
//     not pushed onto the stack.

import { TabBar } from './components/tab-bar'
import { colors } from './lib/colors'
import { activeTab, type TabKey } from './state/ui'
import { homePage } from './pages/home'
import { transactionsPage } from './pages/transactions'
import { cardsPage } from './pages/cards'
import { profilePage } from './pages/profile'

// Mapping tab → page-factory. Each key recreates the page on switch —
// cheap, nothing is lost except per-tab local state (if any —
// lift it into state/* modules like account/transactions does).
const tabFactories: { [K in TabKey]: () => { render: () => RenderNode } } = {
  home: homePage,
  history: transactionsPage,
  cards: cardsPage,
  profile: profilePage,
}

import { sheetOpen } from './state/ui'

mount(() => View(
  { flex: 1, backgroundColor: colors.bg },

  // Slot wraps the tab content — when activeTab changes only THIS subtree
  // rebuilds, the root-mount-effect (`mount(...)`) doesn't re-run.
  Slot({ flex: 1 }, () => tabFactories[activeTab.value]().render()),

  // Glass tab-bar over the content. Position 'absolute' inside the bar
  // itself — gradient/translucency show over the scroll. Hide when
  // a sheet is open — otherwise on iOS 26 (floating sheet at medium detent)
  // the tab-bar pokes out from under the sheet in the bottom margin.
  Slot({}, () => sheetOpen.value ? null : TabBar()),
))
