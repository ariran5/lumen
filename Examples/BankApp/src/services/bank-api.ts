// Mock bank API. In a real app this layer would do `fetch()`
// to the backend via the sandbox network policy (see manifest.connect).
// Here — fake-latency + immediate resolve, to show the pattern:
//
//   • API returns a Promise — UI waits on a `loading` signal and shows a spinner,
//   • errors are thrown — the page catches them in try/catch,
//   • input/output schema is typed — TypeScript catches drift between
//     the service and the call-site.
//
// `lumen.connect: []` in the manifest means fetch to foreign hosts is currently
// forbidden — to enable a live API, add the host here.

import { addTransaction, type Tx } from '../state/transactions'

export interface TransferRequest {
  toIBAN: string
  recipientName: string
  amountCents: number
  note?: string
}

/** Simulates latency (200-400ms) to demo loading states. */
function simulateLatency(): Promise<void> {
  return new Promise(resolve => {
    setTimeout(resolve, 200 + Math.random() * 200)
  })
}

export class BankAPIError extends Error {
  constructor(message: string, public code: string) {
    super(message)
  }
}

/** Transfer call. Mock-validates IBAN format and positive amount. */
export async function makeTransfer(req: TransferRequest): Promise<Tx> {
  if (req.amountCents <= 0) {
    throw new BankAPIError('Amount must be positive', 'invalid_amount')
  }
  if (!/^[A-Z]{2}\d{2}\s/.test(req.toIBAN)) {
    throw new BankAPIError('Invalid IBAN format', 'invalid_iban')
  }
  await simulateLatency()
  return addTransaction({
    icon: '↗️',
    name: req.recipientName,
    category: 'Transfer',
    amountCents: -req.amountCents,
    note: req.note ?? `Transfer to ${req.recipientName}`,
  })
}

/** Mock-receive. The profile page has a demo button to test this. */
export async function receiveDeposit(amountCents: number, source: string): Promise<Tx> {
  await simulateLatency()
  return addTransaction({
    icon: '⬇️',
    name: source,
    category: 'Deposit',
    amountCents,
  })
}
