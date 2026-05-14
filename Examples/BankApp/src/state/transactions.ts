// Transactions store. Список + фильтр + computed-агрегаты.
// applyDelta из account.ts перенесён сюда же как side-effect добавления
// транзакции — единый entry-point для мутаций.

import { applyDelta } from './account'

export interface Tx {
  id: number
  icon: string
  name: string
  category: string
  /** Negative = spend, positive = income. */
  amountCents: number
  /** Unix ms. */
  at: number
  /** Long-form notes — показываются на detail-странице. */
  note?: string
}

export type TxFilter = 'all' | 'income' | 'spending'

const seed: Tx[] = [
  { id: 1,  icon: '☕',  name: 'Blue Bottle',     category: 'Coffee',        amountCents:    -485, at: hoursAgo(2),   note: 'Cortado + croissant' },
  { id: 2,  icon: '🛒',  name: 'Whole Foods',     category: 'Groceries',     amountCents:   -8240, at: hoursAgo(5) },
  { id: 3,  icon: '💰',  name: 'Acme Inc',        category: 'Salary',        amountCents:  320000, at: daysAgo(1), note: 'May salary' },
  { id: 4,  icon: '🎬',  name: 'Netflix',         category: 'Subscriptions', amountCents:   -1299, at: daysAgo(1) },
  { id: 5,  icon: '🚇',  name: 'Metro',           category: 'Transit',       amountCents:    -275, at: daysAgo(2) },
  { id: 6,  icon: '🍔',  name: 'Shake Shack',     category: 'Restaurants',   amountCents:   -1840, at: daysAgo(2) },
  { id: 7,  icon: '⛽',  name: 'Shell Station',   category: 'Fuel',          amountCents:   -6230, at: daysAgo(3) },
  { id: 8,  icon: '📱',  name: 'AT&T',            category: 'Phone',         amountCents:   -4500, at: daysAgo(4) },
  { id: 9,  icon: '✈️',  name: 'United Airlines', category: 'Travel',        amountCents:  -42800, at: daysAgo(5), note: 'SFO → JFK, economy' },
  { id: 10, icon: '🏋️',  name: 'Gym membership',  category: 'Health',        amountCents:   -3900, at: daysAgo(6) },
]

export const transactions = signal<Tx[]>(seed)
export const filter = signal<TxFilter>('all')

let nextID = seed.length + 1

export const visibleTransactions = computed<Tx[]>(() => {
  const all = transactions.value
  const f = filter.value
  if (f === 'all') return all
  return all.filter(t =>
    f === 'income' ? t.amountCents > 0 : t.amountCents < 0)
})

export const monthSpending = computed<number>(() => {
  let sum = 0
  for (const t of transactions.value) if (t.amountCents < 0) sum += t.amountCents
  return sum
})

export const monthIncome = computed<number>(() => {
  let sum = 0
  for (const t of transactions.value) if (t.amountCents > 0) sum += t.amountCents
  return sum
})

/**
 * Добавить транзакцию. Side-effect: обновляет balance через account.ts.
 * Это единый entry-point — page'и НЕ мутируют список напрямую.
 */
export function addTransaction(input: Omit<Tx, 'id' | 'at'> & { at?: number }): Tx {
  const tx: Tx = {
    id: nextID++,
    at: input.at ?? Date.now(),
    icon: input.icon,
    name: input.name,
    category: input.category,
    amountCents: input.amountCents,
    note: input.note,
  }
  transactions.value = [tx, ...transactions.value]
  applyDelta(tx.amountCents)
  return tx
}

export function findTransaction(id: number): Tx | undefined {
  return transactions.peek().find(t => t.id === id)
}

function hoursAgo(h: number): number { return Date.now() - h * 3_600_000 }
function daysAgo(d: number): number { return Date.now() - d * 86_400_000 }
