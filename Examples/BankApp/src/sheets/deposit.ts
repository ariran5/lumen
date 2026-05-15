// Deposit. Analog of T-Bank's "Add money": AmountDisplay on top,
// pick a deposit source (SBP / card from another bank / cash at an
// ATM / bank transfer), presets + Keypad, sticky CTA.

import { PillButton } from '../components/pill-button'
import { SheetShell } from '../components/sheet-shell'
import { SheetRow } from '../components/sheet-row'
import { AmountDisplay, rawToCents } from '../components/amount-display'
import { Keypad, applyKey, applyBackspace } from '../components/keypad'
import { colors, radius, space } from '../lib/colors'
import { money, moneyShort } from '../lib/format'
import { receiveDeposit } from '../services/bank-api'
import { sheetOpen } from '../state/ui'

interface Source {
  id: string
  icon: string
  tint: Color
  label: string
  sublabel: string
  /** Fee in kopecks. 0 — no fee. */
  feeCents: number
}

const SOURCES: Source[] = [
  {
    id: 'sbp',
    icon: '⚡',
    tint: colors.tileTransfer,
    label: 'Через СБП',
    sublabel: 'Из другого банка по номеру телефона',
    feeCents: 0,
  },
  {
    id: 'cardin',
    icon: '💳',
    tint: colors.cardBlack,
    label: 'С карты другого банка',
    sublabel: 'До 150 000 ₽ в месяц без комиссии',
    feeCents: 0,
  },
  {
    id: 'cash',
    icon: '🏧',
    tint: colors.tileQR,
    label: 'Наличными в банкомате',
    sublabel: '3 200+ банкоматов партнёров',
    feeCents: 0,
  },
  {
    id: 'transfer',
    icon: '🏛️',
    tint: colors.tileGov,
    label: 'Банковским переводом',
    sublabel: 'Реквизиты для зачисления',
    feeCents: 0,
  },
]

const PRESETS: number[] = [1000_00, 5000_00, 25_000_00]

export function openDepositSheet(): void {
  const raw = signal('5000')
  const source = signal<Source>(SOURCES[0]!)
  const submitting = signal(false)
  const error = signal<string | null>(null)

  const cents = computed<number>(() => rawToCents(raw.value))
  const canSubmit = computed<boolean>(() => !submitting.value && cents.value > 0)

  async function confirm() {
    error.value = null
    submitting.value = true
    try {
      await receiveDeposit(cents.peek(), source.peek().label)
      lumen.haptics('success')
      lumen.alert({
        title: 'Зачислено',
        message: `${money(cents.peek())} поступили на Tinkoff Black.`,
      })
    } catch (e) {
      error.value = (e as Error).message ?? 'Не удалось пополнить'
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
        title: 'Пополнить',
        subtitle: 'На Tinkoff Black ·· 4422',
        footer: PillButton({
          label: 'Пополнить',
          disabled: () => !canSubmit.value,
          onTap: confirm,
        }),
      },

      AmountDisplay({
        raw,
        accent: true,
        caption: () => {
          const c = cents.value
          if (c === 0) return 'Введите сумму пополнения'
          return source.value.feeCents === 0
            ? 'Без комиссии'
            : 'Комиссия ' + moneyShort(source.value.feeCents)
        },
      }),

      // Presets
      View(
        { flexDirection: 'row', gap: space.sm },
        ...PRESETS.map(c => presetChip(c, raw)),
      ),

      // Source
      View(
        { gap: space.sm },
        Text(
          {
            fontSize: 11, fontWeight: '700',
            color: colors.textTertiary,
            paddingLeft: space.xs, paddingTop: space.xs,
          },
          'СПОСОБ ПОПОЛНЕНИЯ',
        ),
        Slot({}, () => SheetRow({
          icon: source.value.icon,
          iconTint: source.value.tint,
          label: source.value.label,
          sublabel: source.value.sublabel,
          onTap: () => openSourcePicker(source),
        })),
      ),

      Slot({}, () => error.value
        ? errorBlock(error.value)
        : null,
      ),

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
      width: 108, height: 44, borderRadius: 22,
      backgroundColor: colors.surface,
      borderWidth: 1, borderColor: colors.border,
      alignItems: 'center', justifyContent: 'center',
    },
    Text({ fontSize: 14, fontWeight: '600', color: colors.textSecondary }, moneyShort(c)),
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

function openSourcePicker(bind: Signal<Source>): void {
  lumen.bottomSheet({
    height: 'medium',
    content: SheetShell(
      { title: 'Откуда', subtitle: 'Выберите способ' },
      View(
        { gap: space.sm },
        ...SOURCES.map(s => SheetRow({
          icon: s.icon,
          iconTint: s.tint,
          label: s.label,
          sublabel: s.sublabel,
          selected: s.id === bind.peek().id,
          onTap: () => {
            bind.value = s
            lumen.haptics('soft')
          },
        })),
      ),
    ),
  })
}
