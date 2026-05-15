// Money / date formatting. Isolated in one module so that:
//   • locale/currency can be swapped in one place,
//   • we don't drag `Intl` mock-logic through every component,
//   • tests for this layer (when they appear) have no UI dependencies.

const MONTHS = ['янв','фев','мар','апр','мая','июн','июл','авг','сен','окт','ноя','дек']

/** Kopecks → `1 234,56 ₽` with a "−" sign for negatives. */
export function money(cents: number): string {
  const negative = cents < 0
  const abs = Math.abs(cents)
  const rubles = Math.floor(abs / 100)
  const fraction = (abs % 100).toString().padStart(2, '0')
  // Narrow space as thousands separator (T-Bank style).
  const withSpaces = String(rubles).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
  return (negative ? '−' : '') + withSpaces + ',' + fraction + ' ₽'
}

/** Same, but always with a sign (for income/expense rows). */
export function moneyWithSign(cents: number): string {
  if (cents > 0) return '+' + money(cents)
  return money(cents)
}

/** Short account format in lists: `241 850 ₽` without kopecks and without sign. */
export function moneyShort(cents: number): string {
  const abs = Math.abs(cents)
  const rubles = Math.floor(abs / 100)
  const withSpaces = String(rubles).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
  return withSpaces + ' ₽'
}

/** ISO timestamp → `14 мая, 09:14`. Returns `''` for null/invalid. */
export function dateLabel(ms: number | null | undefined): string {
  if (ms == null) return ''
  const d = new Date(ms)
  const day = d.getDate()
  const month = MONTHS[d.getMonth()]
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return day + ' ' + month + ', ' + hh + ':' + mm
}

/** `1234` → `1 234`. For counters, NOT for money. */
export function thousands(n: number): string {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')
}
