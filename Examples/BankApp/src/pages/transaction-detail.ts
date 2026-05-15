// Transaction detail. Takes an id, hits the store via findTransaction.
// Demonstrates a params-driven page.

import { Header } from '../components/header'
import { GlassCard } from '../components/glass-card'
import { Amount } from '../components/amount'
import { colors, space } from '../lib/colors'
import { dateLabel } from '../lib/format'
import { back } from '../lib/router'
import { findTransaction } from '../state/transactions'

export function transactionDetailPage(id: number) {
  const tx = findTransaction(id)
  return {
    render: () => renderDetail(tx, id),
  }
}

function renderDetail(tx: ReturnType<typeof findTransaction>, requestedID: number): RenderNode {
  if (!tx) {
    return View(
      { flex: 1, backgroundColor: colors.bg },
      Header({ title: 'Transaction', leftIcon: '‹', onLeft: back }),
      View(
        { flex: 1, alignItems: 'center', justifyContent: 'center', padding: space.xl },
        Text({ fontSize: 16, color: colors.textSecondary }, 'Transaction #' + requestedID + ' not found'),
      ),
    )
  }

  return View(
    { flex: 1, backgroundColor: colors.bg },

    Header({ title: 'Transaction', leftIcon: '‹', onLeft: back }),

    View(
      {
        paddingTop: space.xl,
        paddingBottom: space.xl,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.xl,
      },
      // Hero — large icon + amount
      View(
        { alignItems: 'center', gap: space.md },
        View(
          {
            width: 64, height: 64, borderRadius: 32,
            backgroundColor: colors.surface,
            alignItems: 'center', justifyContent: 'center',
          },
          Text({ fontSize: 32 }, tx.icon),
        ),
        Amount({ cents: tx.amountCents, size: 32, weight: '800' }),
        Text({ fontSize: 14, color: colors.textSecondary }, tx.name),
      ),

      // Meta card
      GlassCard(
        {},
        metaRow('Category', tx.category),
        metaRow('Date', dateLabel(tx.at)),
        metaRow('Reference', '#' + String(tx.id).padStart(8, '0')),
        tx.note ? metaRow('Note', tx.note) : null,
      ),
    ),
  )
}

function metaRow(label: string, value: string): RenderNode {
  return View(
    { flexDirection: 'row', alignItems: 'center', gap: space.md },
    Text({ flex: 1, fontSize: 13, color: colors.textTertiary }, label),
    Text({ fontSize: 14, color: colors.textPrimary, fontWeight: '500' }, value),
  )
}
