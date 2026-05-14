// Home / dashboard. Hero card с балансом, quick-action row, top-5 транзакций.

import { Header } from '../components/header'
import { GlassCard } from '../components/glass-card'
import { TxRow } from '../components/tx-row'
import { Amount } from '../components/amount'
import { colors, radius, space } from '../lib/colors'
import { money } from '../lib/format'
import { open } from '../lib/router'
import { account, balanceCents } from '../state/account'
import { monthIncome, monthSpending, transactions } from '../state/transactions'

export function homePage() {
  return {
    render: renderHome,
  }
}

function renderHome(): RenderNode {
  return View(
    { flex: 1, backgroundColor: colors.bg },

    Header({ title: 'Lumen Bank', rightLabel: 'Profile', onRight: () => open('profile') }),

    ScrollView(
      {
        flex: 1,
        paddingTop: space.sm,
        paddingBottom: Math.max(lumen.safeArea.bottom, space.lg) + space.xxl,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.lg,
      },
      heroCard(),
      actionGrid(),
      monthSummary(),
      recentSection(),
    ),
  )
}

function heroCard(): RenderNode {
  return View(
    {
      backgroundColor: colors.accent,
      borderRadius: radius.card,
      padding: space.xl,
      gap: space.md,
    },
    Text({ fontSize: 13, fontWeight: '500', color: '#FFFFFFB0' }, () => 'CARD · •••• ' + account.value.cardLast4),
    Text(
      { fontSize: 34, fontWeight: '800', color: colors.textPrimary },
      () => money(balanceCents.value),
    ),
    Text({ fontSize: 13, color: '#FFFFFFB0' }, () => account.value.holderName),
  )
}

function actionGrid(): RenderNode {
  return View(
    { flexDirection: 'row', gap: space.md },
    actionTile('↗', 'Send', () => open('transfer')),
    actionTile('≡', 'History', () => open('transactions')),
    actionTile('⚙', 'Settings', () => open('profile')),
  )
}

function actionTile(icon: string, label: string, onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap,
      flex: 1,
      paddingTop: space.lg,
      paddingBottom: space.lg,
      borderRadius: radius.card,
      backgroundColor: colors.surface,
      alignItems: 'center',
      gap: space.sm,
    },
    Text({ fontSize: 22, color: colors.textPrimary }, icon),
    Text({ fontSize: 13, fontWeight: '600', color: colors.textPrimary }, label),
  )
}

function monthSummary(): RenderNode {
  return GlassCard(
    {},
    Text({ fontSize: 12, color: colors.textTertiary, fontWeight: '600' }, 'THIS MONTH'),
    View(
      { flexDirection: 'row', gap: space.lg },
      summaryColumn('Income', () => monthIncome.value),
      summaryColumn('Spending', () => monthSpending.value),
    ),
  )
}

function summaryColumn(label: string, cents: Thunk<number>): RenderNode {
  return View(
    { flex: 1, gap: space.xs },
    Text({ fontSize: 13, color: colors.textSecondary }, label),
    Amount({ cents, size: 20, weight: '700' }),
  )
}

function recentSection(): RenderNode {
  return GlassCard(
    { padding: space.md, gap: space.xs },
    View(
      { flexDirection: 'row', alignItems: 'center', paddingLeft: space.md, paddingRight: space.md, paddingTop: space.sm },
      Text({ flex: 1, fontSize: 12, color: colors.textTertiary, fontWeight: '600' }, 'RECENT'),
      Pressable(
        { onTap: () => open('transactions'), paddingTop: space.xs, paddingBottom: space.xs },
        Text({ fontSize: 13, color: colors.accentHi, fontWeight: '600' }, 'See all →'),
      ),
    ),
    // Slot — реактивный subtree: при изменении transactions.value
    // ребилдится только этот список, не весь дашборд.
    Slot({ gap: 0 }, () => transactions.value.slice(0, 5).map(TxRow)),
  )
}
