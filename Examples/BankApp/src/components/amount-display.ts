// AmountDisplay — large amount input in a banking-sheet style.
//
// Not a TextInput: it's a display that reads a signal with a numeric string
// and formats groups (1 234 567,89 ₽). Input itself comes from a Keypad
// next to it — typical banking UX (no system numeric keyboard).
//
// The "│" caret blinks via a CSS-equivalent: animated opacity. Too lazy
// to set up a JS timer — we have no CSS keyframes; for now we show
// a static "│" or hide it when the field is empty.

import { colors, space } from '../lib/colors'

interface AmountDisplayProps {
  /** String of digits and one "." — what the keypad types. */
  raw: Signal<string>
  /** Caption below — usually "Доступно: 241 850 ₽" or "Комиссия 0 ₽". */
  caption?: string | Thunk<string>
  /** Override amount color. Default — yellow accent for emphasis,
   *  switches to textPrimary when the user hasn't typed anything. */
  accent?: boolean
}

export function AmountDisplay(p: AmountDisplayProps): RenderNode {
  const display: Thunk<string> = () => formatRaw(p.raw.value)
  const isEmpty: Thunk<boolean> = () => p.raw.value === '' || p.raw.value === '0'

  return View(
    {
      paddingTop: space.lg,
      paddingBottom: space.md,
      alignItems: 'center',
      gap: space.xs,
    },
    Text(
      {
        fontSize: 44,
        fontWeight: '800',
        color: () => p.accent && !isEmpty() ? colors.accent : colors.textPrimary,
        textAlign: 'center',
      },
      display,
    ),
    p.caption != null
      ? (typeof p.caption === 'function'
          ? Text({ fontSize: 12, color: colors.textTertiary, textAlign: 'center' }, p.caption as Thunk<string>)
          : Text({ fontSize: 12, color: colors.textTertiary, textAlign: 'center' }, p.caption))
      : null,
  )
}

/** Raw "12345.6" → "12 345,6 ₽"; empty string → "0 ₽". */
export function formatRaw(raw: string): string {
  if (!raw) return '0 ₽'
  const [intPart, fracPart] = raw.split('.')
  const withSpaces = (intPart || '0').replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
  const tail = fracPart != null ? ',' + fracPart : ''
  return withSpaces + tail + ' ₽'
}

/** "12345.6" → kopecks 1 234 560 (rounded to whole kopecks).
 *  Empty / invalid string — 0. */
export function rawToCents(raw: string): number {
  if (!raw) return 0
  const [intPart, fracPart] = raw.split('.')
  const rubles = parseInt(intPart || '0', 10) || 0
  const fracDigits = (fracPart ?? '').slice(0, 2).padEnd(2, '0')
  const fracCents = parseInt(fracDigits, 10) || 0
  return rubles * 100 + fracCents
}
