// Account state. Module-level signal = shared state across all pages.
// Importing `balance` anywhere — it's the same reactive signal everywhere,
// and updates land in every page the moment it changes.
//
// Pattern: the module exports readonly references (Signal<T> for reads,
// the `value` setter is allowed — but we mutate via action functions for
// observability and a clearer call-graph.

interface AccountInfo {
  holderName: string
  iban: string
  cardLast4: string
}

export const account = signal<AccountInfo>({
  holderName: 'Ариан Алленсон',
  iban: 'RU82 4044 5552 5000 1234 5678 9012',
  cardLast4: '4422',
})

/** In kopecks. This is the balance of the MAIN account (Tinkoff Black) —
 *  also the one updated when transactions are added via `applyDelta`. */
export const balanceCents = signal<number>(241_850_00)

export function applyDelta(deltaCents: number): void {
  balanceCents.value = balanceCents.peek() + deltaCents
}
