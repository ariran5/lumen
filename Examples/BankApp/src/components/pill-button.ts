// PillButton — primary CTA. Accent fill, white label, round pill shape.
//
// ВНИМАНИЕ к багу ядра: thunk на `backgroundColor` parent View'а ломает
// рендер дочерних Text'ов. Поэтому здесь backgroundColor СТАТИЧЕН, а
// disabled-визуализация — через `opacity` (для неё patchProp работает).

import { colors, radius, space } from '../lib/colors'

interface PillButtonProps {
  label: string
  onTap: () => void
  /** Disabled — серая заливка, onTap игнорится. */
  disabled?: boolean | Thunk<boolean>
  /** Compact = меньше padding (для inline action'ов). */
  compact?: boolean
}

export function PillButton(p: PillButtonProps): RenderNode {
  const padV = p.compact ? space.sm : space.md
  const padH = p.compact ? space.lg : space.xl
  const isDisabledThunk = typeof p.disabled === 'function'

  return Pressable(
    {
      onTap: () => {
        const d = typeof p.disabled === 'function' ? p.disabled() : p.disabled
        if (!d) {
          lumen.haptics('light')
          p.onTap()
        }
      },
      paddingTop: padV,
      paddingBottom: padV,
      paddingLeft: padH,
      paddingRight: padH,
      borderRadius: radius.pill,
      backgroundColor: colors.accent,
      // Dim через opacity (этот thunk-патч работает). Disabled → 0.4.
      opacity: isDisabledThunk
        ? () => ((p.disabled as Thunk<boolean>)() ? 0.4 : 1)
        : (p.disabled ? 0.4 : 1),
      alignItems: 'center',
      justifyContent: 'center',
    },
    Text(
      {
        fontSize: 16,
        fontWeight: '700',
        color: colors.textPrimary,
      },
      p.label,
    ),
  )
}
