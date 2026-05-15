// Bottom tab-bar in iOS 26 Liquid Glass style. Icons are text glyphs,
// label below. Active state — accent-tinted pill behind the icon.

import { colors, radius, space } from '../lib/colors'
import { activeTab, TAB_BAR_HEIGHT, type TabKey } from '../state/ui'

interface TabDef {
  key: TabKey
  label: string
  icon: string
}

const TABS: TabDef[] = [
  { key: 'home',    label: 'Главная',  icon: '⌂' },
  { key: 'history', label: 'История',  icon: '≡' },
  { key: 'cards',   label: 'Платежи',  icon: '▭' },
  { key: 'profile', label: 'Ещё',      icon: '◉' },
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
    // Pill (visible only for the active tab) — a sibling of Text, not its parent.
    // Renderer bug: a thunk on the container's `backgroundColor` breaks
    // rendering of child Texts; bypass via an opacity-thunk on a separate View
    // positioned under the text.
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
