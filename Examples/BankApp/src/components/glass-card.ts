// GlassCard — surface-обёртка для секций (баланс, action grid, list group).
// Не Liquid Glass — простой rounded-rect с subtle border. Liquid Glass
// (`Glass({intensity:'glass'})`) приберегаем для тех мест, где есть фон-картинка
// под пилюлей; на flat-dark surface'е разницы не видно, а fillrate дороже.

import { colors, radius, space } from '../lib/colors'

interface GlassCardProps {
  children?: never  // children приходят через варарги, не prop
  padding?: number
  gap?: number
}

export function GlassCard(props: GlassCardProps, ...children: Child[]): RenderNode {
  return View(
    {
      backgroundColor: colors.surface,
      borderRadius: radius.card,
      borderColor: colors.border,
      borderWidth: 1,
      padding: props.padding ?? space.lg,
      gap: props.gap ?? space.md,
    },
    ...children,
  )
}
