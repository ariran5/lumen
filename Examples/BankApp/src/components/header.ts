// Header — единая верхняя плашка для всех страниц (lumen shell скрывает
// свой nav bar, и каждый fast-app рисует header сам). Слева — title,
// справа — опциональная action-кнопка.

import { colors, radius, space } from '../lib/colors'

interface HeaderProps {
  title: string
  leftIcon?: string
  onLeft?: () => void
  rightLabel?: string
  onRight?: () => void
}

export function Header(p: HeaderProps): RenderNode {
  return View(
    {
      flexDirection: 'row',
      alignItems: 'center',
      paddingTop: lumen.safeArea.top + space.sm,
      paddingBottom: space.md,
      paddingLeft: space.lg,
      paddingRight: space.lg,
      gap: space.md,
      backgroundColor: colors.bg,
    },
    p.leftIcon
      ? Pressable(
          {
            onTap: p.onLeft ?? (() => {}),
            width: 36, height: 36, borderRadius: radius.pill,
            backgroundColor: colors.surface,
            alignItems: 'center', justifyContent: 'center',
          },
          Text({ fontSize: 17, color: colors.textPrimary }, p.leftIcon),
        )
      : null,

    Text(
      { flex: 1, fontSize: 20, fontWeight: '700', color: colors.textPrimary },
      p.title,
    ),

    p.rightLabel
      ? Pressable(
          {
            onTap: p.onRight ?? (() => {}),
            paddingTop: space.sm, paddingBottom: space.sm,
            paddingLeft: space.md, paddingRight: space.md,
            borderRadius: radius.pill,
            backgroundColor: colors.surface,
          },
          Text({ fontSize: 14, fontWeight: '600', color: colors.textPrimary }, p.rightLabel),
        )
      : null,
  )
}
