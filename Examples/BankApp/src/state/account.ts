// Account state. Module-level signal = shared state между всеми pages.
// Импортить `balance` где угодно — везде один и тот же реактивный signal,
// в любой page оно обновится в момент изменения.
//
// Pattern: модуль экспортирует readonly references (Signal<T> для чтения,
// `value` setter возможен — но мутируем через action-функции для
// observability и более понятного call-graph'а.

interface AccountInfo {
  holderName: string
  iban: string
  cardLast4: string
}

export const account = signal<AccountInfo>({
  holderName: 'Arian Allenson',
  iban: 'IL21 0040 5000 1234 5678 9012',
  cardLast4: '4422',
})

/** В центах. Обновляется при добавлении транзакций через `applyDelta`. */
export const balanceCents = signal<number>(241_85_00)

export function applyDelta(deltaCents: number): void {
  balanceCents.value = balanceCents.peek() + deltaCents
}
