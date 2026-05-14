// Transaction preview sheet. Tap по tx row на Home таб → этот sheet
// (`height: 'medium'`). Внутри — meta + кнопка «View details» которая
// закрывает sheet и пушит full detail-страницу через router.
//
// Зачем preview отдельно от полного detail'а: показывает Pattern A/B —
// quick glance в sheet'е (без leaving контекста) vs full page (где можно
// что-то сделать дальше: dispute, repeat, …).

import { Amount } from '../components/amount'
import { colors, radius, space } from '../lib/colors'
import { dateLabel } from '../lib/format'
import { open } from '../lib/router'
import { findTransaction } from '../state/transactions'

export function openTxPreviewSheet(txID: number): void {
  const tx = findTransaction(txID)
  if (!tx) return

  lumen.bottomSheet({
    height: 'medium',
    content: View(
      {
        flex: 1,
        // backgroundColor: colors.bg,
        paddingTop: space.md,
        paddingBottom: Math.max(lumen.safeArea.bottom, space.lg),
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.md,
      },
      View({ alignItems: 'center', paddingBottom: space.sm },
        View({ width: 36, height: 4, borderRadius: 2, backgroundColor: colors.border })),

      // Hero
      View(
        { flexDirection: 'row', alignItems: 'center', gap: space.md },
        View(
          {
            width: 52, height: 52, borderRadius: radius.pill,
            backgroundColor: colors.surfaceElevated,
            alignItems: 'center', justifyContent: 'center',
          },
          Text({ fontSize: 26 }, tx.icon),
        ),
        View(
          { flex: 1, gap: 2 },
          Text({ fontSize: 17, fontWeight: '700', color: colors.textPrimary }, tx.name),
          Text({ fontSize: 12, color: colors.textTertiary }, tx.category + ' · ' + dateLabel(tx.at)),
        ),
        Amount({ cents: tx.amountCents, size: 18, weight: '700' }),
      ),

      View({ height: 1, backgroundColor: colors.border }),

      tx.note
        ? Text({ fontSize: 14, color: colors.textSecondary }, tx.note)
        : Text({ fontSize: 13, color: colors.textTertiary, fontWeight: '500' }, 'No notes for this transaction.'),

      View({ flex: 1 }),

      // Action row
      Pressable(
        {
          onTap: () => {
            // TODO: programmatic sheet dismiss — пока полагаемся на то, что
            // router.push поднимется поверх sheet'а; sheet'ом юзер смахнёт.
            open('transactionDetail', { id: tx.id })
          },
          paddingTop: space.md, paddingBottom: space.md,
          borderRadius: radius.control,
          backgroundColor: colors.surface,
          borderWidth: 1, borderColor: colors.border,
          alignItems: 'center',
        },
        Text({ fontSize: 15, fontWeight: '600', color: colors.accentHi }, 'View full details →'),
      ),
    ),
  })
}
