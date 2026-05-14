// Transfer form. Демонстрирует:
//   • local-to-page signals (recipient, iban, amount, note),
//   • controlled TextInput,
//   • async service call с loading + error states,
//   • biometric guard перед submit'ом.

import { Header } from '../components/header'
import { GlassCard } from '../components/glass-card'
import { PillButton } from '../components/pill-button'
import { colors, radius, space } from '../lib/colors'
import { back } from '../lib/router'
import { makeTransfer, BankAPIError } from '../services/bank-api'
import { balanceCents } from '../state/account'

export function transferPage() {
  // Page-local state. Каждый раз когда юзер открывает страницу — фабрика
  // создаёт свежие signal'ы, форма пустая. Module-level signals (balance,
  // account) шарятся; locale-only — нет.
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
      // Biometric guard — high-value transactions требуют Face ID.
      // На simulator'е biometrics.available()==='none' → пропускаем guard.
      if (amountCents.peek() > 100_00 && lumen.biometrics.available() !== 'none') {
        const ok = await lumen.biometrics.authenticate('Confirm transfer of ' + amountStr.peek())
        if (!ok) {
          errorMessage.value = 'Authentication cancelled'
          return
        }
      }
      await makeTransfer({
        toIBAN: iban.peek().trim(),
        recipientName: recipient.peek().trim(),
        amountCents: amountCents.peek(),
        note: note.peek().trim() || undefined,
      })
      lumen.haptics('success')
      back()
    } catch (e) {
      const msg = e instanceof BankAPIError ? e.message
                : e instanceof Error ? e.message
                : String(e)
      errorMessage.value = msg
      lumen.haptics('error')
    } finally {
      isSubmitting.value = false
    }
  }

  return {
    render: () => render({
      recipient, iban, amountStr, note,
      errorMessage, canSubmit, submit,
    }),
  }
}

interface RenderProps {
  recipient: Signal<string>
  iban: Signal<string>
  amountStr: Signal<string>
  note: Signal<string>
  errorMessage: ReadonlySignal<string | null>
  canSubmit: ReadonlySignal<boolean>
  submit: () => void
}

function render(p: RenderProps): RenderNode {
  return View(
    { flex: 1, backgroundColor: colors.bg },

    Header({ title: 'Send money', leftIcon: '‹', onLeft: back }),

    ScrollView(
      {
        flex: 1,
        paddingTop: space.md,
        paddingBottom: Math.max(lumen.safeArea.bottom, space.lg) + space.xxl,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.lg,
      },

      GlassCard(
        {},
        formField('Recipient', p.recipient, 'Full name', 'words'),
        formField('IBAN', p.iban, 'IL21 0040 5000 1234 5678 9012', 'characters'),
        formField('Amount (USD)', p.amountStr, '0.00', 'none', 'decimal'),
        formField('Note (optional)', p.note, 'Coffee, rent, …', 'sentences'),
      ),

      // Error chip
      Slot({}, () => {
        const msg = p.errorMessage.value
        if (!msg) return null
        return View(
          {
            backgroundColor: '#3A1F1F',
            borderColor: colors.negative,
            borderWidth: 1,
            borderRadius: radius.control,
            padding: space.md,
          },
          Text({ color: colors.negative, fontSize: 13 }, msg),
        )
      }),

      PillButton({
        label: 'Send',
        disabled: () => !p.canSubmit.value,
        onTap: p.submit,
      }),
    ),
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
