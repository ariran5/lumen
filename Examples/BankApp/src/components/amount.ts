// Amount — money-display с цветом по знаку (income → green, spend → red).
// Принимает либо числовой `cents`, либо thunk `() => cents` — thunk
// автоматом включает per-prop реактивность (Vapor-style).

import { colors } from '../lib/colors'
import { moneyWithSign } from '../lib/format'

interface AmountProps {
  cents: number | Thunk<number>
  size?: number
  weight?: '500' | '600' | '700' | '800'
  /** Force-цвет, игнорирует знак. */
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
