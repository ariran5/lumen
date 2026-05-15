// UI-state. The active tab lives here — it determines which page-factory
// renders in the main area. Module-level signal => `index.ts` subscribes
// via `mount`, switching happens without a router.

export type TabKey = 'home' | 'history' | 'cards' | 'profile'

export const activeTab = signal<TabKey>('home')

/** Height of the bottom tab-bar WITHOUT safe-area (added separately). */
export const TAB_BAR_HEIGHT = 64

/** Hides the TabBar when a bottom-sheet is open — otherwise the tab-bar's Glass blur
 *  shows the sheet passing through its area + on iOS 26 at the .medium detent
 *  the sheet floats with margins and the TabBar pokes out from under it. */
export const sheetOpen = signal<boolean>(false)
