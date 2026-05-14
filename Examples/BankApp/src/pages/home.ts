// Home / dashboard. Hero card с балансом + quick-action row (Send/Deposit
// открывают bottom-sheet'ы, не push'ат страницу — экшены модальные, чтобы
// не выбрасывать юзера из контекста). Tap по recent tx row → preview sheet
// с кнопкой «View full details» которая уже пушит full detail.

import { GlassCard } from '../components/glass-card'
import { Amount } from '../components/amount'
import { colors, radius, space } from '../lib/colors'
import { money } from '../lib/format'
import { account, balanceCents } from '../state/account'
import { monthIncome, monthSpending, transactions } from '../state/transactions'
import { TAB_BAR_HEIGHT, activeTab } from '../state/ui'
import { openSendSheet } from '../sheets/send'
import { openDepositSheet } from '../sheets/deposit'
import { openTxPreviewSheet } from '../sheets/tx-preview'

export function homePage() {
  return {
    render: renderHome,
  }
}

function renderHome(): RenderNode {
  return View(
    { flex: 1, backgroundColor: colors.bg },

    // Greeting bar — заменяет «Header» компонент, потому что top tab-page
    // не нужен title + back. Большие свободные поля сверху делают
    // визуальное «дыхание», как в современных банковских apps.
    View(
      {
        paddingTop: lumen.safeArea.top + space.md,
        paddingBottom: space.md,
        paddingLeft: space.lg, paddingRight: space.lg,
      },
      Text({ fontSize: 13, color: colors.textTertiary, fontWeight: '500' }, 'Welcome back,'),
      Text({ fontSize: 22, fontWeight: '700', color: colors.textPrimary }, () => account.value.holderName.split(' ')[0]!),
    ),

    ScrollView(
      {
        flex: 1,
        paddingBottom: TAB_BAR_HEIGHT + Math.max(lumen.safeArea.bottom, space.lg) + space.xl,
        paddingLeft: space.lg, paddingRight: space.lg,
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
    actionTile('↗', 'Send', openSendSheet),
    actionTile('⬇', 'Deposit', openDepositSheet),
    actionTile('≡', 'History', () => { activeTab.value = 'history' }),
  )
}

function actionTile(icon: string, label: string, onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap: () => { lumen.haptics('light'); onTap() },
      flex: 1,
      paddingTop: space.lg, paddingBottom: space.lg,
      borderRadius: radius.card,
      backgroundColor: colors.surface,
      borderWidth: 1, borderColor: colors.border,
      alignItems: 'center', gap: space.sm,
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
        { onTap: () => { activeTab.value = 'history' }, paddingTop: space.xs, paddingBottom: space.xs },
        Text({ fontSize: 13, color: colors.accentHi, fontWeight: '600' }, 'See all →'),
      ),
    ),
    Slot({ gap: 0 }, () => transactions.value.slice(0, 5).map(t =>
      Pressable(
        {
          key: 'home-tx-' + t.id,
          // Quick-preview sheet вместо push — для home показываем lightweight
          // прехват; в History/Cards эта же row может пушить full detail.
          onTap: () => { lumen.haptics('soft'); openTxPreviewSheet(t.id) },
          flexDirection: 'row', alignItems: 'center', gap: space.md,
          paddingTop: space.md, paddingBottom: space.md,
          paddingLeft: space.md, paddingRight: space.md,
          borderRadius: radius.control,
        },
        View(
          {
            width: 40, height: 40, borderRadius: radius.pill,
            backgroundColor: colors.surfaceElevated,
            alignItems: 'center', justifyContent: 'center',
          },
          Text({ fontSize: 20 }, t.icon),
        ),
        View(
          { flex: 1, gap: 2 },
          Text({ fontSize: 15, fontWeight: '600', color: colors.textPrimary, numberOfLines: 1 }, t.name),
          Text({ fontSize: 12, color: colors.textTertiary }, t.category),
        ),
        Amount({ cents: t.amountCents, size: 15, weight: '600' }),
      ),
    )),
  )
}
