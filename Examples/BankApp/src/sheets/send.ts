// Send-flow в bottom-sheet'е (UISheetPresentationController, height='large').
// Это альтернатива push-странице: модальная форма поверх tab-bar'а, swipe-down
// чтобы закрыть, без необходимости разрушать стек навигации. Хорошо ложится
// под action — юзер видит контекст под sheet'ом, и cancel = смахнуть вниз.

import { PillButton } from '../components/pill-button'
import { colors, radius, space } from '../lib/colors'
import { makeTransfer, BankAPIError } from '../services/bank-api'
import { balanceCents } from '../state/account'

export function openSendSheet(): void {
  // Local form state, живёт пока sheet открыт. Каждый показ — новая копия.
  const recipient = signal('')
  const iban = signal('')
  const amountStr = signal('')
  const note = signal('')
  const isSubmitting = signal(false)
  const errorMessage = signal<string | null>(null)

  const amountCents = computed(() => {
    const raw = parseFloat(amountStr.value.replace(/,/g, '.'))
    if (!isFinite(raw) || raw <= 0) return 0
    return Math.round(raw * 100)
  })

  const canSubmit = computed(() =>
    !isSubmitting.value &&
    recipient.value.trim().length > 0 &&
    iban.value.trim().length > 0 &&
    amountCents.value > 0 &&
    amountCents.value <= balanceCents.value)

  async function submit() {
    errorMessage.value = null
    isSubmitting.value = true
    try {
      if (amountCents.peek() > 100_00 && lumen.biometrics.available() !== 'none') {
        const ok = await lumen.biometrics.authenticate('Confirm transfer')
        if (!ok) { errorMessage.value = 'Authentication cancelled'; return }
      }
      await makeTransfer({
        toIBAN: iban.peek().trim(),
        recipientName: recipient.peek().trim(),
        amountCents: amountCents.peek(),
        note: note.peek().trim() || undefined,
      })
      lumen.haptics('success')
      // Sheet закрываем через alert dismiss — простейший способ; в реальной
      // UI лучше иметь programmatic dismiss API. Sheet примет swipe-down.
      lumen.alert({ title: 'Sent', message: 'Transfer queued. Swipe down to close.' })
    } catch (e) {
      const msg = e instanceof BankAPIError ? e.message : (e as Error).message ?? String(e)
      errorMessage.value = msg
      lumen.haptics('error')
    } finally {
      isSubmitting.value = false
    }
  }

  lumen.bottomSheet({
    height: 'large',
    content: View(
      {
        flex: 1,
        backgroundColor: colors.bg,
        paddingTop: space.lg,
        paddingBottom: Math.max(lumen.safeArea.bottom, space.lg),
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.lg,
      },
      grabber(),
      Text({ fontSize: 22, fontWeight: '800', color: colors.textPrimary }, 'Send money'),
      formField('Recipient', recipient, 'Full name', 'words'),
      formField('IBAN', iban, 'IL21 0040 5000 1234 5678 9012', 'characters'),
      formField('Amount (USD)', amountStr, '0.00', 'none', 'decimal'),
      formField('Note (optional)', note, 'Coffee, rent, …', 'sentences'),
      Slot({}, () => errorMessage.value
        ? View(
            {
              backgroundColor: '#3A1F1F', borderColor: colors.negative, borderWidth: 1,
              borderRadius: radius.control, padding: space.md,
            },
            Text({ color: colors.negative, fontSize: 13 }, errorMessage.value!),
          )
        : null),
      PillButton({ label: 'Send', disabled: () => !canSubmit.value, onTap: submit }),
    ),
  })
}

function grabber(): RenderNode {
  return View(
    { alignItems: 'center', paddingBottom: space.sm },
    View({ width: 36, height: 4, borderRadius: 2, backgroundColor: colors.border }),
  )
}

function formField(
  label: string,
  bind: Signal<string>,
  placeholder: string,
  caps: Autocapitalize = 'none',
  kb: KeyboardType = 'default',
): RenderNode {
  return View(
    { gap: space.xs },
    Text({ fontSize: 12, color: colors.textTertiary, fontWeight: '600' }, label.toUpperCase()),
    TextInput({
      value: bind.value,
      placeholder,
      keyboardType: kb,
      autocapitalize: caps,
      autocorrect: caps === 'sentences' || caps === 'words',
      onChange: e => { bind.value = e.value },
      height: 44,
      fontSize: 15,
      color: colors.textPrimary,
      backgroundColor: colors.surfaceElevated,
      borderRadius: radius.control,
      paddingLeft: space.md,
      paddingRight: space.md,
    }),
  )
}
