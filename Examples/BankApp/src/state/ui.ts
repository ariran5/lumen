// UI-state. Здесь сидит активный таб — он определяет, какая page-фабрика
// рендерится в main area. Модуль-уровневый signal => `index.ts` подписан
// через `mount`, переключение происходит без router'а.

export type TabKey = 'home' | 'history' | 'cards' | 'profile'

export const activeTab = signal<TabKey>('home')

/** Высота bottom tab-bar'а БЕЗ safe-area (она добавляется отдельно). */
export const TAB_BAR_HEIGHT = 64

/** Прячет TabBar когда открыт bottom-sheet — иначе Glass blur tab-bar'а
 *  показывает sheet проезжающий через его область + sheet на iOS 26 при
 *  .medium detent'е плавает с margins и TabBar торчит снизу из-под sheet'а. */
export const sheetOpen = signal<boolean>(false)
