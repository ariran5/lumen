// Bottom tab-bar в стиле iOS 26 Liquid Glass.
//
// Иконки рисуем не через Text/CATextLayer, а из примитивных View — некоторые
// Unicode-glyph'ы не имеют надёжного покрытия в системном font'е и в
// CATextLayer уходят в .notdef (квадратики либо пустота). Прямоугольники
// с borderRadius всегда отрисуются.

import { colors, radius, space } from '../lib/colors'
import { activeTab, TAB_BAR_HEIGHT, type TabKey } from '../state/ui'

interface TabDef {
  key: TabKey
  label: string
  icon: (active: Thunk<boolean>) => RenderNode
}

const TABS: TabDef[] = [
  { key: 'home',    label: 'Home',    icon: homeIcon },
  { key: 'history', label: 'History', icon: historyIcon },
  { key: 'cards',   label: 'Cards',   icon: cardsIcon },
  { key: 'profile', label: 'Profile', icon: profileIcon },
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
      paddingTop: space.xs,
      paddingBottom: space.xs,
      gap: 2,
    },
    // Active pill за иконкой
    View(
      {
        width: 44, height: 30, borderRadius: radius.pill,
        alignItems: 'center', justifyContent: 'center',
        backgroundColor: () => isActive() ? colors.accent + '55' : '#00000000',
      },
      t.icon(isActive),
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

// ─── Геометрические иконки. Все 20×20 bounding box, центрируются flex'ом. ───

function homeIcon(active: Thunk<boolean>): RenderNode {
  const fg: Thunk<Color> = () => active() ? colors.textPrimary : colors.textSecondary
  // «Домик»: треугольная крыша (square rotated 45°) + квадрат основания.
  return View(
    { width: 22, height: 18, alignItems: 'center' },
    // Roof — повёрнутый квадрат
    View({
      width: 12, height: 12,
      backgroundColor: fg,
      transform: { rotate: Math.PI / 4 },
      position: 'absolute',
      top: 0,
    }),
    // Body — прямоугольник внизу, перекрывает нижнюю часть крыши
    View({
      position: 'absolute',
      bottom: 0,
      width: 14, height: 9,
      backgroundColor: fg,
      borderRadius: 1,
    }),
  )
}

function historyIcon(active: Thunk<boolean>): RenderNode {
  const fg: Thunk<Color> = () => active() ? colors.textPrimary : colors.textSecondary
  // Три горизонтальные полоски — символ списка.
  return View(
    { width: 22, height: 18, justifyContent: 'center', gap: 3 },
    View({ height: 2.5, backgroundColor: fg, borderRadius: 1.5 }),
    View({ height: 2.5, backgroundColor: fg, borderRadius: 1.5 }),
    View({ height: 2.5, backgroundColor: fg, borderRadius: 1.5 }),
  )
}

function cardsIcon(active: Thunk<boolean>): RenderNode {
  const fg: Thunk<Color> = () => active() ? colors.textPrimary : colors.textSecondary
  // Карточка: rounded rect + горизонтальная полоска как «магнитная лента».
  return View(
    { width: 22, height: 18, justifyContent: 'center' },
    View({
      width: 22, height: 15,
      backgroundColor: fg,
      borderRadius: 3,
    }),
    // Полоска (контрастный bg)
    View({
      position: 'absolute',
      top: 5,
      left: 0, right: 0,
      height: 3,
      backgroundColor: colors.surface,
    }),
  )
}

function profileIcon(active: Thunk<boolean>): RenderNode {
  const fg: Thunk<Color> = () => active() ? colors.textPrimary : colors.textSecondary
  // Голова (круг) + плечи (полукруг сверху-обрезанный).
  return View(
    { width: 22, height: 18, alignItems: 'center' },
    // Head
    View({
      width: 8, height: 8, borderRadius: 999,
      backgroundColor: fg,
      position: 'absolute',
      top: 0,
    }),
    // Shoulders — широкий пилл, который частично выходит за низ
    View({
      width: 16, height: 10, borderRadius: 999,
      backgroundColor: fg,
      position: 'absolute',
      bottom: -3,
    }),
  )
}
