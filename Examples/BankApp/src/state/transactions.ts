// Transactions store. List + filter + computed aggregates.
// applyDelta from account.ts is wired in here as a side-effect of adding
// a transaction — single entry-point for mutations.

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
  /** Long-form notes — shown on the detail page. */
  note?: string
}

export type TxFilter = 'all' | 'income' | 'spending'

const seed: Tx[] = [
  { id: 1,  icon: '☕',  name: 'Skuratov Coffee', category: 'Кафе и рестораны', amountCents:    -32000, at: hoursAgo(2), note: 'Капучино + круассан' },
  { id: 2,  icon: '🛒',  name: 'Пятёрочка',       category: 'Супермаркеты',     amountCents:   -157900, at: hoursAgo(5) },
  { id: 3,  icon: '💼',  name: 'Acme LLC',        category: 'Зарплата',         amountCents:  18500000, at: daysAgo(1), note: 'Аванс за май' },
  { id: 4,  icon: '🎬',  name: 'Кинопоиск',       category: 'Подписки',         amountCents:    -29900, at: daysAgo(1) },
  { id: 5,  icon: '🚇',  name: 'Метро Москва',    category: 'Транспорт',        amountCents:     -6200, at: daysAgo(2) },
  { id: 6,  icon: '🍕',  name: 'Додо Пицца',      category: 'Кафе и рестораны', amountCents:    -89000, at: daysAgo(2) },
  { id: 7,  icon: '⛽',  name: 'Лукойл АЗС',      category: 'Топливо',          amountCents:   -315000, at: daysAgo(3) },
  { id: 8,  icon: '📱',  name: 'МТС',             category: 'Связь',            amountCents:    -69000, at: daysAgo(4) },
  { id: 9,  icon: '✈️',  name: 'Аэрофлот',        category: 'Авиабилеты',       amountCents:  -1845000, at: daysAgo(5), note: 'MOW → AER, эконом' },
  { id: 10, icon: '🏋️',  name: 'World Class',     category: 'Спорт и здоровье', amountCents:   -390000, at: daysAgo(6) },
  { id: 11, icon: '🛍️',  name: 'Wildberries',     category: 'Маркетплейсы',     amountCents:   -245000, at: daysAgo(7), note: 'Заказ #842130' },
  { id: 12, icon: '💊',  name: 'Аптека 36.6',     category: 'Аптеки',           amountCents:    -82400, at: daysAgo(8) },
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
 * Add a transaction. Side-effect: updates balance via account.ts.
 * This is the single entry-point — pages do NOT mutate the list directly.
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
