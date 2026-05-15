// Numeric keypad for banking sheets. 3×4: 1-9, ".", 0, ⌫.
//
// Works with a raw string via append/backspace callbacks — the component
// doesn't know about signals, the owner page holds them itself. This gives
// flexibility: the same keypad can be wired to amount input, PIN entry, etc.

import { colors, radius, space } from '../lib/colors'

interface KeypadProps {
  /** Called with the typed character: '0'-'9' or '.'. */
  onKey: (key: string) => void
  /** Called on ⌫. */
  onBackspace: () => void
  /** Hides "." (for PIN / integer-only values). */
  noDecimal?: boolean
}

const KEYS_ROW1 = ['1', '2', '3'] as const
const KEYS_ROW2 = ['4', '5', '6'] as const
const KEYS_ROW3 = ['7', '8', '9'] as const

export function Keypad(p: KeypadProps): RenderNode {
  return View(
    { gap: space.sm, paddingTop: space.sm },
    keyRow(KEYS_ROW1, p),
    keyRow(KEYS_ROW2, p),
    keyRow(KEYS_ROW3, p),
    View(
      { flexDirection: 'row', gap: space.sm },
      p.noDecimal
        ? View({ flex: 1 })
        : keyButton('.', () => p.onKey('.')),
      keyButton('0', () => p.onKey('0')),
      keyButton('⌫', () => p.onBackspace(), 'backspace'),
    ),
  )
}

function keyRow(keys: readonly string[], p: KeypadProps): RenderNode {
  return View(
    { flexDirection: 'row', gap: space.sm },
    ...keys.map(k => keyButton(k, () => p.onKey(k))),
  )
}

type KeyVariant = 'digit' | 'backspace'

function keyButton(label: string, onTap: () => void, variant: KeyVariant = 'digit'): RenderNode {
  return Pressable(
    {
      onTap: () => {
        lumen.haptics(variant === 'backspace' ? 'soft' : 'light')
        onTap()
      },
      flex: 1,
      height: 56,
      borderRadius: radius.control,
      backgroundColor: variant === 'backspace' ? 'transparent' : colors.surface,
      alignItems: 'center',
      justifyContent: 'center',
    },
    Text(
      {
        fontSize: variant === 'backspace' ? 22 : 26,
        fontWeight: '600',
        color: colors.textPrimary,
      },
      label,
    ),
  )
}

/** Reducer-helper: applies a key press to the raw string.
 *  Used in send/deposit sheets as:
 *    onKey: k => raw.value = applyKey(raw.peek(), k) */
export function applyKey(raw: string, key: string): string {
  if (key === '.') {
    if (raw.includes('.')) return raw       // at most one dot
    if (raw === '') return '0.'             // ".5" → "0.5"
    return raw + '.'
  }
  // Digit
  if (raw === '0') return key === '0' ? '0' : key  // leading zeros
  const [intPart, fracPart] = raw.split('.')
  if (fracPart != null && fracPart.length >= 2) return raw  // max 2 decimal places
  if ((intPart ?? '').length >= 9 && fracPart == null) return raw  // max 999 999 999 ₽
  return raw + key
}

export function applyBackspace(raw: string): string {
  return raw.slice(0, -1)
}
