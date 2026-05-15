// SheetRow — selection row in a bottom-sheet. Left: round tinted icon;
// center: title/sublabel; right: value-text and/or
// chevron `›`. Used in send (source, recipient), deposit
// (top-up source), card-actions (settings).
//
// IMPORTANT: Pressable's children sit **directly** (flex-row), no wrapping
// View with `flex: 1`. A flex:1 wrapper child in a Pressable-column context
// collapses the row to zero height — already caught that one.

import { colors, radius, space } from '../lib/colors'

interface SheetRowProps {
  icon?: string
  iconTint?: Color
  label: string
  sublabel?: string | Thunk<string>
  /** Text to the right of the title (instead of chevron). */
  value?: string | Thunk<string>
  /** Color of the right-side value. Default textSecondary. */
  valueColor?: Color
  /** Show chevron `›` on the right. Default true if onTap is set. */
  chevron?: boolean
  /** Destructive — red text. */
  destructive?: boolean
  /** Highlight as selected (border accent + soft fill). */
  selected?: boolean
  onTap?: () => void
}

export function SheetRow(p: SheetRowProps): RenderNode {
  const labelColor: Color = p.destructive ? colors.negative : colors.textPrimary
  const showChevron = p.chevron ?? !!p.onTap

  const props = {
    flexDirection: 'row' as const,
    alignItems: 'center' as const,
    gap: space.md,
    paddingTop: space.md,
    paddingBottom: space.md,
    paddingLeft: space.md,
    paddingRight: space.md,
    borderRadius: radius.control,
    backgroundColor: p.selected ? colors.accentSoft : colors.surface,
    borderWidth: 1,
    borderColor: p.selected ? colors.accent : colors.border,
  }

  const iconNode: RenderNode | null = p.icon
    ? View(
        {
          width: 40, height: 40, borderRadius: 20,
          backgroundColor: p.iconTint ?? colors.surfaceElevated,
          alignItems: 'center', justifyContent: 'center',
        },
        Text({ fontSize: 20, color: labelColor }, p.icon),
      )
    : null

  const titleNode: RenderNode = View(
    { flex: 1, gap: 2 },
    Text({ fontSize: 15, fontWeight: '600', color: labelColor, numberOfLines: 1 }, p.label),
    p.sublabel != null
      ? (typeof p.sublabel === 'function'
          ? Text({ fontSize: 12, color: colors.textTertiary, numberOfLines: 1 }, p.sublabel as Thunk<string>)
          : Text({ fontSize: 12, color: colors.textTertiary, numberOfLines: 1 }, p.sublabel))
      : null,
  )

  const valueNode: RenderNode | null = p.value != null
    ? (typeof p.value === 'function'
        ? Text({ fontSize: 14, fontWeight: '600', color: p.valueColor ?? colors.textSecondary }, p.value as Thunk<string>)
        : Text({ fontSize: 14, fontWeight: '600', color: p.valueColor ?? colors.textSecondary }, p.value))
    : null

  const chevronNode: RenderNode | null = showChevron
    ? Text({ fontSize: 18, color: colors.textTertiary }, '›')
    : null

  if (p.onTap) {
    return Pressable(
      { ...props, onTap: () => { lumen.haptics('soft'); p.onTap!() } },
      iconNode, titleNode, valueNode, chevronNode,
    )
  }
  return View(props, iconNode, titleNode, valueNode, chevronNode)
}
