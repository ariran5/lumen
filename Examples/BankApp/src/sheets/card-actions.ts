// Card actions sheet — Freeze, Show number, Set limit, Report lost.
// Демонстрирует:
//   • locally-reactive boolean (frozen) с обновлением UI в sheet'е,
//   • native action-sheet через lumen.actionSheet для destructive flow.

import { colors, radius, space } from '../lib/colors'

interface CardActionsSheetState {
  frozen: Signal<boolean>
  cardLast4: string
}

export function openCardActionsSheet(state: CardActionsSheetState): void {
  lumen.bottomSheet({
    height: 'medium',
    content: View(
      {
        flex: 1,
        backgroundColor: colors.bg,
        paddingTop: space.md,
        paddingBottom: Math.max(lumen.safeArea.bottom, space.lg),
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.md,
      },
      View({ alignItems: 'center', paddingBottom: space.sm },
        View({ width: 36, height: 4, borderRadius: 2, backgroundColor: colors.border })),

      Text({ fontSize: 22, fontWeight: '800', color: colors.textPrimary }, 'Card actions'),
      Text({ fontSize: 13, color: colors.textTertiary }, '•••• ' + state.cardLast4),

      // Freeze toggle row
      Slot({}, () => row({
        icon: state.frozen.value ? '❄' : '⏸',
        label: state.frozen.value ? 'Unfreeze card' : 'Freeze card',
        sublabel: state.frozen.value ? 'Card is currently frozen' : 'Block new purchases',
        accent: state.frozen.value,
        onTap: () => {
          lumen.haptics('medium')
          state.frozen.value = !state.frozen.value
        },
      })),

      row({
        icon: '⊙',
        label: 'Show full number',
        sublabel: 'Reveal after Face ID',
        onTap: async () => {
          const ok = lumen.biometrics.available() === 'none'
                   ? true
                   : await lumen.biometrics.authenticate('Show card number')
          if (ok) {
            lumen.alert({ title: 'Card', message: '4422 1234 5678 ' + state.cardLast4 })
          }
        },
      }),

      row({
        icon: '⚠',
        label: 'Report lost or stolen',
        sublabel: 'Block immediately',
        destructive: true,
        onTap: () => {
          // Native action-sheet для confirm destructive action.
          lumen.actionSheet({
            title: 'Report card as lost?',
            message: 'A new card will be issued within 5 business days.',
            actions: [
              { label: 'Report and block', style: 'destructive' },
            ],
            onSelect: () => {
              state.frozen.value = true
              lumen.alert({ title: 'Card blocked', message: 'A replacement is on its way.' })
            },
          })
        },
      }),
    ),
  })
}

interface RowProps {
  icon: string
  label: string
  sublabel: string
  accent?: boolean
  destructive?: boolean
  onTap: () => void
}

function row(p: RowProps): RenderNode {
  const labelColor: Color = p.destructive ? colors.negative : colors.textPrimary
  return Pressable(
    {
      onTap: p.onTap,
      flexDirection: 'row', alignItems: 'center', gap: space.md,
      paddingTop: space.md, paddingBottom: space.md,
      paddingLeft: space.md, paddingRight: space.md,
      borderRadius: radius.control,
      backgroundColor: p.accent ? colors.accent + '22' : colors.surface,
      borderWidth: 1,
      borderColor: p.accent ? colors.accent : colors.border,
    },
    View(
      {
        width: 38, height: 38, borderRadius: radius.pill,
        alignItems: 'center', justifyContent: 'center',
        backgroundColor: colors.surfaceElevated,
      },
      Text({ fontSize: 18, color: labelColor }, p.icon),
    ),
    View(
      { flex: 1, gap: 2 },
      Text({ fontSize: 15, fontWeight: '600', color: labelColor }, p.label),
      Text({ fontSize: 12, color: colors.textTertiary }, p.sublabel),
    ),
  )
}
