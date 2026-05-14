// Mock bank API. В реальном приложении этот слой делал бы `fetch()`
// к backend'у через sandbox network policy (см. manifest.connect).
// Здесь — fake-latency + immediate resolve, чтобы показать pattern:
//
//   • API возвращает Promise — UI ждёт `loading` signal и показывает spinner,
//   • ошибки бросаются как throw — page ловит в try/catch,
//   • схема входа/выхода типизирована — TypeScript ловит drift между
//     service'ом и call-site'ом.
//
// `lumen.connect: []` в manifest'е значит, что fetch к чужим хостам пока
// запрещён — для подключения live API сюда добавится host.

import { addTransaction, type Tx } from '../state/transactions'

export interface TransferRequest {
  toIBAN: string
  recipientName: string
  amountCents: number
  note?: string
}

/** Симулирует latency (200-400ms) для демонстрации loading-state'ов. */
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

/** Translate-выписка. Mock validate'ит IBAN формат и положительную сумму. */
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

/** Mock-receive. На странице profile есть demo-кнопка для теста. */
export async function receiveDeposit(amountCents: number, source: string): Promise<Tx> {
  await simulateLatency()
  return addTransaction({
    icon: '⬇️',
    name: source,
    category: 'Deposit',
    amountCents,
  })
}
