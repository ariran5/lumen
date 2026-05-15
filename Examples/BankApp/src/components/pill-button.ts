// PillButton — primary CTA in T-Bank style: chunky yellow pill
// with black type, 56pt tall (compact = 44pt). Banking standard:
// primary action is prominent and easy to tap, not a "web button".
//
// HEADS UP — core bug: a thunk on the parent View's `backgroundColor`
// breaks rendering of child Texts. So backgroundColor is STATIC,
// and the disabled visual uses `opacity` (patchProp works for that).

import { colors } from '../lib/colors'

interface PillButtonProps {
  label: string
  onTap: () => void
  /** Disabled — muted fill, onTap is ignored. */
  disabled?: boolean | Thunk<boolean>
  /** Compact = 44pt instead of 56pt (for inline actions in rows). */
  compact?: boolean
}

export function PillButton(p: PillButtonProps): RenderNode {
  const isDisabledThunk = typeof p.disabled === 'function'
  const h = p.compact ? 44 : 56

  return Pressable(
    {
      onTap: () => {
        const d = typeof p.disabled === 'function' ? p.disabled() : p.disabled
        if (!d) {
          lumen.haptics('light')
          p.onTap()
        }
      },
      height: h,
      paddingLeft: 24,
      paddingRight: 24,
      // Pill = exactly height/2; Lumen/iOS 26 doesn't clamp larger radii.
      borderRadius: h / 2,
      backgroundColor: colors.accent,
      opacity: isDisabledThunk
        ? () => ((p.disabled as Thunk<boolean>)() ? 0.4 : 1)
        : (p.disabled ? 0.4 : 1),
      alignItems: 'center',
      justifyContent: 'center',
    },
    Text(
      {
        fontSize: p.compact ? 15 : 17,
        fontWeight: '700',
        color: colors.textOnAccent,
      },
      p.label,
    ),
  )
}
