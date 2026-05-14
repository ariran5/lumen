// Transactions list. Filter chips (all/income/spending) + полный scroll-список.

import { Header } from '../components/header'
import { TxRow } from '../components/tx-row'
import { colors, radius, space } from '../lib/colors'
import { back } from '../lib/router'
import { filter, visibleTransactions, type TxFilter } from '../state/transactions'

export function transactionsPage() {
  return {
    render: renderTransactions,
  }
}

function renderTransactions(): RenderNode {
  return View(
    { flex: 1, backgroundColor: colors.bg },

    Header({ title: 'Transactions', leftIcon: '‹', onLeft: back }),

    // Filter chip row
    View(
      {
        flexDirection: 'row',
        gap: space.sm,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        paddingBottom: space.md,
      },
      filterChip('all', 'All'),
      filterChip('income', 'Income'),
      filterChip('spending', 'Spending'),
    ),

    // Scroll-список. Slot — реактивный, при смене filter ребилдится только он.
    ScrollView(
      {
        flex: 1,
        paddingLeft: space.md,
        paddingRight: space.md,
        paddingBottom: Math.max(lumen.safeArea.bottom, space.lg),
      },
      Slot({ gap: 0 }, () => visibleTransactions.value.map(TxRow)),
    ),
  )
}

function filterChip(value: TxFilter, label: string): RenderNode {
  return Pressable(
    {
      onTap: () => { filter.value = value },
      paddingTop: space.sm,
      paddingBottom: space.sm,
      paddingLeft: space.md,
      paddingRight: space.md,
      borderRadius: radius.pill,
      borderWidth: 1,
      backgroundColor: () => filter.value === value ? colors.accent : colors.surface,
      borderColor: () => filter.value === value ? colors.accent : colors.border,
    },
    Text(
      {
        fontSize: 13,
        fontWeight: '600',
        color: () => filter.value === value ? colors.textPrimary : colors.textSecondary,
      },
      label,
    ),
  )
}
