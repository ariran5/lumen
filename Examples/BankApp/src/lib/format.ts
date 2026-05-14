// Money / date форматирование. Изолировано в одном модуле, чтобы:
//   • легко поменять локаль/валюту в одном месте,
//   • не таскать `Intl` mock-логику в каждом компоненте,
//   • тесты на этот слой (когда они появятся) — без UI dependencies.

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']

/** Centавы → `$1,234.56` со знаком для отрицательных. */
export function money(cents: number): string {
  const negative = cents < 0
  const abs = Math.abs(cents)
  const dollars = Math.floor(abs / 100)
  const fraction = (abs % 100).toString().padStart(2, '0')
  const withCommas = String(dollars).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return (negative ? '−' : '') + '$' + withCommas + '.' + fraction
}

/** То же, но всегда со знаком (для income/expense рядов). */
export function moneyWithSign(cents: number): string {
  if (cents > 0) return '+' + money(cents)
  return money(cents)
}

/** ISO timestamp → `Jan 14, 09:14`. Возвращает `''` для null/invalid. */
export function dateLabel(ms: number | null | undefined): string {
  if (ms == null) return ''
  const d = new Date(ms)
  const day = d.getDate()
  const month = MONTHS[d.getMonth()]
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  return month + ' ' + day + ', ' + hh + ':' + mm
}

/** `1234` → `1,234`. Для счётчиков, NOT для денег. */
export function thousands(n: number): string {
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
}
