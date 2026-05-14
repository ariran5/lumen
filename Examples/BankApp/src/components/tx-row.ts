// TxRow — один ряд в списке транзакций. Pressable, открывает detail-страницу.

import type { Tx } from '../state/transactions'
import { Amount } from './amount'
import { colors, radius, space } from '../lib/colors'
import { dateLabel } from '../lib/format'
import { open } from '../lib/router'

export function TxRow(tx: Tx): RenderNode {
  return Pressable(
    {
      key: 'tx-' + tx.id,
      onTap: () => open('transactionDetail', { id: tx.id }),
      flexDirection: 'row',
      alignItems: 'center',
      gap: space.md,
      paddingTop: space.md,
      paddingBottom: space.md,
      paddingLeft: space.md,
      paddingRight: space.md,
      borderRadius: radius.control,
    },
    // icon bubble
    View(
      {
        width: 40, height: 40,
        borderRadius: radius.pill,
        backgroundColor: colors.surfaceElevated,
        alignItems: 'center',
        justifyContent: 'center',
      },
      Text({ fontSize: 20 }, tx.icon),
    ),
    // name + category column
    View(
      { flex: 1, gap: 2 },
      Text({ fontSize: 15, fontWeight: '600', color: colors.textPrimary, numberOfLines: 1 }, tx.name),
      Text({ fontSize: 12, color: colors.textTertiary }, tx.category + ' · ' + dateLabel(tx.at)),
    ),
    // amount
    Amount({ cents: tx.amountCents, size: 15, weight: '600' }),
  )
}
