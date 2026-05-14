// Quick deposit sheet. Маленькая sheet (`height: 'medium'`), 3 пресета +
// «Custom». Хорошо демонстрирует pattern: chip-style выбор → confirm.

import { PillButton } from '../components/pill-button'
import { colors, radius, space } from '../lib/colors'
import { money } from '../lib/format'
import { receiveDeposit } from '../services/bank-api'

const PRESETS_CENTS = [100_00, 500_00, 1000_00]

export function openDepositSheet(): void {
  const selected = signal<number>(PRESETS_CENTS[1]!)
  const isSubmitting = signal(false)

  async function confirm() {
    isSubmitting.value = true
    try {
      await receiveDeposit(selected.peek(), 'Quick deposit')
      lumen.haptics('success')
      lumen.alert({ title: 'Deposited', message: money(selected.peek()) + ' added.' })
    } finally {
      isSubmitting.value = false
    }
  }

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
        gap: space.lg,
      },
      View({ alignItems: 'center', paddingBottom: space.sm },
        View({ width: 36, height: 4, borderRadius: 2, backgroundColor: colors.border })),

      Text({ fontSize: 22, fontWeight: '800', color: colors.textPrimary }, 'Add money'),
      Text({ fontSize: 13, color: colors.textSecondary }, 'Mock deposit — instantly credits the demo account.'),

      View(
        { flexDirection: 'row', gap: space.sm },
        ...PRESETS_CENTS.map(c => presetChip(c, selected)),
      ),

      View({ flex: 1 }),
      PillButton({ label: 'Confirm', disabled: () => isSubmitting.value, onTap: confirm }),
    ),
  })
}

function presetChip(cents: number, sel: Signal<number>): RenderNode {
  const isActive = () => sel.value === cents
  return Pressable(
    {
      flex: 1,
      onTap: () => { lumen.haptics('light'); sel.value = cents },
      paddingTop: space.md, paddingBottom: space.md,
      borderRadius: radius.control,
      borderWidth: 1,
      borderColor: () => isActive() ? colors.accent : colors.border,
      backgroundColor: () => isActive() ? colors.accent + '33' : colors.surface,
      alignItems: 'center',
    },
    Text(
      {
        fontSize: 15, fontWeight: '700',
        color: () => isActive() ? colors.textPrimary : colors.textSecondary,
      },
      money(cents),
    ),
  )
}
