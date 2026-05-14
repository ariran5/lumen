// Transactions list. Filter chips (all/income/spending) + полный scroll-список.

import { Header } from '../components/header'
import { TxRow } from '../components/tx-row'
import { colors, radius, space } from '../lib/colors'
import { filter, visibleTransactions, type TxFilter } from '../state/transactions'
import { TAB_BAR_HEIGHT } from '../state/ui'

export function transactionsPage() {
  return {
    render: renderTransactions,
  }
}

function renderTransactions(): RenderNode {
  // ВАЖНО: общая форма всех tab-pages: View(Top, ScrollView(...)). Если
  // index'ы детей расходятся между табами (Home: View+ScrollView;
  // History раньше: View+View+ScrollView), reconcile видит kind-diff на
  // том же индексе и пересоздаёт ScrollView UIView. Каждое такое
  // пересоздание ставит свежий UIView поверх tab-bar'а и ломает
  // z-порядок до следующего relayout'а. Filter-chips переехали ВНУТРЬ
  // ScrollView'а как первая «строка».
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
      // Filter chip row (теперь sticky-less заголовок в скролле)
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
