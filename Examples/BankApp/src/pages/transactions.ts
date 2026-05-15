// Transactions list. Filter chips (all/income/spending) + full scroll list.

import { Header } from '../components/header'
import { TxRow } from '../components/tx-row'
import { colors, space } from '../lib/colors'
import { filter, visibleTransactions, type TxFilter } from '../state/transactions'
import { TAB_BAR_HEIGHT } from '../state/ui'

export function transactionsPage() {
  return {
    render: renderTransactions,
  }
}

function renderTransactions(): RenderNode {
  // IMPORTANT: shared shape across all tab-pages: View(Top, ScrollView(...)). If
  // child indices diverge between tabs (Home: View+ScrollView;
  // History previously: View+View+ScrollView), reconcile sees a kind-diff at
  // the same index and recreates the ScrollView UIView. Each such
  // recreation puts a fresh UIView over the tab-bar and breaks
  // z-order until the next relayout. Filter-chips moved INSIDE
  // the ScrollView as the first "row".
  return View(
    { flex: 1, backgroundColor: colors.bg },

    Header({ title: 'Transactions' }),

    ScrollView(
      {
        flex: 1,
        paddingLeft: space.md,
        paddingRight: space.md,
        paddingBottom: TAB_BAR_HEIGHT + Math.max(lumen.safeArea.bottom, space.lg) + space.lg,
      },
      // Filter chip row (now a sticky-less header inside the scroll)
      View(
        {
          flexDirection: 'row',
          gap: space.sm,
          paddingLeft: space.sm,
          paddingRight: space.sm,
          paddingBottom: space.md,
        },
        filterChip('all', 'All'),
        filterChip('income', 'Income'),
        filterChip('spending', 'Spending'),
      ),
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
      borderRadius: 16,
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
