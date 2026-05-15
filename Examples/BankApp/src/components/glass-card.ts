// GlassCard — surface wrapper for sections (balance, action grid, list group).
// Not Liquid Glass — a simple rounded-rect with a subtle border. Liquid Glass
// (`Glass({intensity:'glass'})`) is reserved for places with a background image
// under the pill; on a flat-dark surface the difference isn't visible and fillrate is more expensive.

import { colors, radius, space } from '../lib/colors'

interface GlassCardProps {
  children?: never  // children come via varargs, not as a prop
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
