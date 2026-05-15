// Amount — money-display colored by sign (income → green, spend → red).
// Accepts either a numeric `cents` or a thunk `() => cents` — a thunk
// automatically enables per-prop reactivity (Vapor-style).

import { colors } from '../lib/colors'
import { moneyWithSign } from '../lib/format'

interface AmountProps {
  cents: number | Thunk<number>
  size?: number
  weight?: '500' | '600' | '700' | '800'
  /** Force color, ignores sign. */
  color?: Color
}

export function Amount(p: AmountProps): RenderNode {
  const isThunk = typeof p.cents === 'function'
  const size = p.size ?? 17
  const weight = p.weight ?? '600'

  if (isThunk) {
    const fn = p.cents as Thunk<number>
    return Text(
      {
        fontSize: size,
        fontWeight: weight,
        color: p.color ?? (() => colorFor(fn())),
      },
      () => moneyWithSign(fn()),
    )
  }

  const cents = p.cents as number
  return Text(
    {
      fontSize: size,
      fontWeight: weight,
      color: p.color ?? colorFor(cents),
    },
    moneyWithSign(cents),
  )
}

function colorFor(cents: number): Color {
  if (cents > 0) return colors.positive
  if (cents < 0) return colors.negative
  return colors.textSecondary
}
