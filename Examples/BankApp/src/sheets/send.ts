// Transfer. Bottom-sheet in T-Bank style: large amount in the hero,
// SheetRows to pick "To" and "From", presets, sticky CTA at the bottom.
// Amount entry goes through the banking Keypad, not the system keyboard —
// that's what users expect from a banking app.

import { PillButton } from '../components/pill-button'
import { SheetShell } from '../components/sheet-shell'
import { SheetRow } from '../components/sheet-row'
import { AmountDisplay, rawToCents } from '../components/amount-display'
import { Keypad, applyKey, applyBackspace } from '../components/keypad'
import { colors, radius, space } from '../lib/colors'
import { money, moneyShort } from '../lib/format'
import { makeTransfer, BankAPIError } from '../services/bank-api'
import { balanceCents } from '../state/account'
import { sheetOpen } from '../state/ui'

const PRESETS: number[] = [1000_00, 5000_00, 10_000_00]

interface Recipient {
  name: string
  hint: string  // last 4 digits or a mask
}

const DEFAULT_RECIPIENT: Recipient = {
  name: 'Михаил К.',
  hint: '+7 ··· ··· 42-19',
}

export function openSendSheet(): void {
  // Local state lives as long as the sheet is open.
  const raw = signal('')
  const recipient = signal<Recipient>(DEFAULT_RECIPIENT)
  const note = signal('')
  const submitting = signal(false)
  const error = signal<string | null>(null)

  const cents = computed<number>(() => rawToCents(raw.value))

  const canSubmit = computed<boolean>(() =>
    !submitting.value &&
    cents.value > 0 &&
    cents.value <= balanceCents.value,
  )

  async function submit() {
    error.value = null
    submitting.value = true
    try {
      // Biometric guard on large transfers (>1 000 ₽).
      if (cents.peek() > 1000_00 && lumen.biometrics.available() !== 'none') {
        const ok = await lumen.biometrics.authenticate('Подтвердите перевод')
        if (!ok) { error.value = 'Подтверждение отменено'; return }
      }
      await makeTransfer({
        toIBAN: 'RU82 4040 5552 ' + (recipient.peek().hint.match(/\d{2}-\d{2}/)?.[0] ?? '00-00'),
        recipientName: recipient.peek().name,
        amountCents: cents.peek(),
        note: note.peek().trim() || undefined,
      })
      lumen.haptics('success')
      lumen.alert({
        title: 'Готово',
        message: `${money(cents.peek())} отправлены ${recipient.peek().name}.\nСмахните вниз, чтобы закрыть.`,
      })
    } catch (e) {
      const msg = e instanceof BankAPIError ? e.message : (e as Error).message ?? String(e)
      error.value = msg
      lumen.haptics('error')
    } finally {
      submitting.value = false
    }
  }

  sheetOpen.value = true
  lumen.bottomSheet({
    height: 'large',
    onClose: () => { sheetOpen.value = false },
    content: SheetShell(
      {
        title: 'Перевод',
        subtitle: 'С Tinkoff Black ·· 4422',
        footer: PillButton({
          label: 'Перевести',
          disabled: () => !canSubmit.value,
          onTap: submit,
        }),
      },

      // Big amount
      AmountDisplay({
        raw,
        accent: true,
        caption: () => {
          const c = cents.value
          if (c === 0) return 'Доступно ' + moneyShort(balanceCents.value)
          if (c > balanceCents.value) return 'Превышает доступный баланс'
          return 'Доступно ' + moneyShort(balanceCents.value - c)
        },
      }),

      // Presets
      View(
        { flexDirection: 'row', gap: space.sm },
        ...PRESETS.map(c => presetChip(c, raw)),
        allChip(raw, balanceCents),
      ),

      // Recipient + message — selectable rows
      View(
        { gap: space.sm },
        Slot({}, () => SheetRow({
          icon: '👤',
          iconTint: colors.tileMobile,
          label: recipient.value.name,
          sublabel: recipient.value.hint,
          onTap: () => openRecipientPicker(recipient),
        })),
        SheetRow({
          icon: '💳',
          iconTint: colors.cardBlack,
          label: 'Tinkoff Black',
          sublabel: () => '·· 4422 · ' + moneyShort(balanceCents.value),
          onTap: () => lumen.alert({
            title: 'Источник перевода',
            message: 'Выбор другого счёта — в разработке.',
          }),
        }),
        Slot({}, () => SheetRow({
          icon: '✏️',
          iconTint: colors.tilePay,
          label: 'Сообщение',
          sublabel: note.value ? note.value : 'Необязательно',
          onTap: () => openNoteEditor(note),
        })),
      ),

      // Error block
      Slot({}, () => error.value
        ? errorBlock(error.value)
        : null,
      ),

      // Keypad — fixed 4 rows at the bottom of the scroll area.
      Keypad({
        onKey: k => { raw.value = applyKey(raw.peek(), k) },
        onBackspace: () => { raw.value = applyBackspace(raw.peek()) },
      }),
    ),
  })
}

function presetChip(c: number, raw: Signal<string>): RenderNode {
  return Pressable(
    {
      onTap: () => {
        lumen.haptics('light')
        raw.value = String(Math.floor(c / 100))
      },
      // 92×44 → radius strictly height/2 = 22 (Lumen/iOS 26 doesn't clamp).
      width: 92, height: 44, borderRadius: 22,
      backgroundColor: colors.surface,
      borderWidth: 1, borderColor: colors.border,
      alignItems: 'center', justifyContent: 'center',
    },
    Text({ fontSize: 14, fontWeight: '600', color: colors.textSecondary }, moneyShort(c)),
  )
}

function allChip(raw: Signal<string>, src: Signal<number>): RenderNode {
  return Pressable(
    {
      onTap: () => {
        lumen.haptics('light')
        raw.value = String(Math.floor(src.peek() / 100))
      },
      width: 60, height: 44, borderRadius: 22,
      backgroundColor: colors.accentSoft,
      borderWidth: 1, borderColor: colors.accent,
      alignItems: 'center', justifyContent: 'center',
    },
    Text({ fontSize: 14, fontWeight: '700', color: colors.accent }, 'Все'),
  )
}

function errorBlock(message: string): RenderNode {
  return View(
    {
      flexDirection: 'row', alignItems: 'center', gap: space.md,
      backgroundColor: '#2A1518',
      borderColor: colors.negative,
      borderWidth: 1,
      borderRadius: radius.control,
      paddingTop: space.md, paddingBottom: space.md,
      paddingLeft: space.md, paddingRight: space.md,
    },
    Text({ fontSize: 18 }, '⚠'),
    Text({ flex: 1, color: colors.negative, fontSize: 13, fontWeight: '600' }, message),
  )
}

// ── Sub-sheets ─────────────────────────────────────────────────

const QUICK_RECIPIENTS: Recipient[] = [
  { name: 'Михаил К.',  hint: '+7 ··· ··· 42-19' },
  { name: 'Анна П.',    hint: '+7 ··· ··· 88-04' },
  { name: 'Семья',      hint: 'Анна и Лев · 2 чел.' },
  { name: 'Иван Сидор', hint: 'СБП · Сбер ·· 2210' },
]

function openRecipientPicker(bind: Signal<Recipient>): void {
  lumen.bottomSheet({
    height: 'medium',
    content: SheetShell(
      { title: 'Кому', subtitle: 'Недавние получатели' },
      View(
        { gap: space.sm },
        ...QUICK_RECIPIENTS.map(r => SheetRow({
          icon: '👤',
          iconTint: colors.tileMobile,
          label: r.name,
          sublabel: r.hint,
          selected: r.name === bind.peek().name,
          onTap: () => {
            bind.value = r
            lumen.haptics('soft')
          },
        })),
      ),
    ),
  })
}

function openNoteEditor(bind: Signal<string>): void {
  const local = signal(bind.peek())

  lumen.bottomSheet({
    height: 'medium',
    content: SheetShell(
      {
        title: 'Сообщение',
        subtitle: 'Видит только получатель',
        footer: PillButton({
          label: 'Сохранить',
          onTap: () => {
            bind.value = local.peek().trim()
            lumen.haptics('soft')
          },
        }),
      },
      TextInput({
        value: local.value,
        placeholder: 'Например, «За кофе»',
        onChange: e => { local.value = e.value },
        height: 100,
        fontSize: 15,
        color: colors.textPrimary,
        backgroundColor: colors.surface,
        borderRadius: radius.control,
        paddingTop: space.md, paddingBottom: space.md,
        paddingLeft: space.md, paddingRight: space.md,
      }),
    ),
  })
}
