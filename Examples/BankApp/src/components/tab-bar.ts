// Bottom tab-bar в стиле iOS 26 Liquid Glass. Иконки — text-glyph'ы,
// label под ними. Active state — accent-tinted pill за иконкой.

import { colors, radius, space } from '../lib/colors'
import { activeTab, TAB_BAR_HEIGHT, type TabKey } from '../state/ui'

interface TabDef {
  key: TabKey
  label: string
  icon: string
}

const TABS: TabDef[] = [
  { key: 'home',    label: 'Home',    icon: '⌂' },
  { key: 'history', label: 'History', icon: '≡' },
  { key: 'cards',   label: 'Cards',   icon: '▭' },
  { key: 'profile', label: 'Profile', icon: '◉' },
]

export function TabBar(): RenderNode {
  return View(
    {
      position: 'absolute',
      left: space.md,
      right: space.md,
      bottom: Math.max(lumen.safeArea.bottom, space.sm),
      borderRadius: 28,
    },
    Glass(
      {
        variant: 'regular',
        flexDirection: 'row',
        height: TAB_BAR_HEIGHT,
        borderRadius: 28,
        paddingLeft: space.xs,
        paddingRight: space.xs,
        alignItems: 'center',
      },
      ...TABS.map(tabButton),
    ),
  )
}

function tabButton(t: TabDef): RenderNode {
  const isActive: Thunk<boolean> = () => activeTab.value === t.key
  return Pressable(
    {
      key: t.key,
      flex: 1,
      onTap: () => {
        if (activeTab.peek() === t.key) return
        lumen.haptics('soft')
        activeTab.value = t.key
      },
      alignItems: 'center',
      justifyContent: 'center',
      paddingTop: 4,
      paddingBottom: 4,
      gap: 2,
    },
    // Pill (видим только для active tab) — sibling Text'у, не parent.
    // Renderer-баг: thunk на `backgroundColor` контейнера ломает рендер
    // дочерних Text'ов; obхожу через opacity-thunk на отдельном View,
    // позиционированном под текстом.
    // View(
    //   {
    //     width: 50, height: 28, borderRadius: 14,
    //     backgroundColor: colors.accent + '55',
    //     opacity: () => isActive() ? 1 : 0,
    //     position: 'absolute',
    //   },
    // ),
    Text(
      {
        fontSize: 20, fontWeight: '700',
        color: () => isActive() ? colors.textPrimary : colors.textSecondary,
      },
      t.icon,
    ),
    Text(
      {
        fontSize: 10,
        fontWeight: '600',
        color: () => isActive() ? colors.textPrimary : colors.textTertiary,
      },
      t.label,
    ),
  )
}
