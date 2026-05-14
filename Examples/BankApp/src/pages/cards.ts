// Cards tab — hero-карточка (accent gradient-like surface) + горизонтальный
// dot indicator + actions grid (Freeze / Limits / Number / Lost). Actions
// открывают bottom-sheet'ы или native action-sheet'ы.

import { GlassCard } from '../components/glass-card'
import { Header } from '../components/header'
import { colors, radius, space } from '../lib/colors'
import { dateLabel } from '../lib/format'
import { account } from '../state/account'
import { transactions } from '../state/transactions'
import { TAB_BAR_HEIGHT } from '../state/ui'
import { openCardActionsSheet } from '../sheets/card-actions'

export function cardsPage() {
  // Локальный per-tab state. Caveat: при switch'е таба и обратно signal
  // пересоздаётся (фабрика вызывается заново). Если нужна persistence —
  // подними в state/account.ts.
  const frozen = signal(false)

  return {
    render: () => renderCards(frozen),
  }
}

function renderCards(frozen: Signal<boolean>): RenderNode {
  return View(
    { flex: 1, backgroundColor: colors.bg },
    Header({ title: 'Cards' }),

    ScrollView(
      {
        flex: 1,
        paddingTop: space.sm,
        paddingBottom: TAB_BAR_HEIGHT + Math.max(lumen.safeArea.bottom, space.lg) + space.xl,
        paddingLeft: space.lg,
        paddingRight: space.lg,
        gap: space.lg,
      },

      cardHero(frozen),
      actionGrid(frozen),
      transactionsByCard(),
    ),
  )
}

function cardHero(frozen: Signal<boolean>): RenderNode {
  return View(
    {
      borderRadius: radius.card,
      padding: space.xl,
      gap: space.md,
      backgroundColor: () => frozen.value ? '#2A2D40' : colors.accent,
      borderWidth: 1,
      borderColor: () => frozen.value ? '#3B4060' : colors.accent,
    },
    View(
      { flexDirection: 'row', alignItems: 'center' },
      Text(
        { flex: 1, fontSize: 13, fontWeight: '500', color: '#FFFFFFB0' },
        () => frozen.value ? 'LUMEN · FROZEN' : 'LUMEN PLATINUM',
      ),
      View(
        {
          width: 36, height: 24,
          borderRadius: 6,
          backgroundColor: '#FFFFFF22',
        },
      ),
    ),
    Text({ fontSize: 26, fontWeight: '700', color: colors.textPrimary }, '4422  ••••  ••••  ' + account.value.cardLast4),
    View(
      { flexDirection: 'row', gap: space.lg, paddingTop: space.sm },
      cardField('VALID THRU', '08/29'),
      cardField('CVV', '•••'),
    ),
  )
}

function cardField(label: string, value: string): RenderNode {
  return View(
    { gap: 2 },
    Text({ fontSize: 9, color: '#FFFFFFB0', fontWeight: '600' }, label),
    Text({ fontSize: 14, color: colors.textPrimary, fontWeight: '600' }, value),
  )
}

function actionGrid(frozen: Signal<boolean>): RenderNode {
  return View(
    { flexDirection: 'row', gap: space.md },
    actionTile(() => frozen.value ? '❄' : '⏸', () => frozen.value ? 'Unfreeze' : 'Freeze', () => {
      lumen.haptics('medium')
      frozen.value = !frozen.value
    }),
    actionTile(() => '⚙', () => 'Actions', () => openCardActionsSheet({
      frozen,
      cardLast4: account.peek().cardLast4,
    })),
    actionTile(() => '⌕', () => 'Number', () => {
      lumen.actionSheet({
        title: 'Reveal card number?',
        message: 'You will need Face ID to view the full number.',
        actions: [{ label: 'Show', style: 'default' }],
        onSelect: async () => {
          const ok = lumen.biometrics.available() === 'none'
                   ? true
                   : await lumen.biometrics.authenticate('Show card number')
          if (ok) lumen.alert({ title: 'Card', message: '4422 1234 5678 ' + account.peek().cardLast4 })
        },
      })
    }),
  )
}

function actionTile(icon: Thunk<string>, label: Thunk<string>, onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap,
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

function transactionsByCard(): RenderNode {
  return GlassCard(
    { padding: space.md, gap: space.xs },
    View(
      { paddingLeft: space.md, paddingRight: space.md, paddingTop: space.sm },
      Text({ fontSize: 12, color: colors.textTertiary, fontWeight: '600' }, 'CARD TRANSACTIONS'),
    ),
    Slot({ gap: 0 }, () => transactions.value.slice(0, 4).map(t =>
      View(
        {
          key: 'card-tx-' + t.id,
          flexDirection: 'row', alignItems: 'center', gap: space.md,
          paddingTop: space.md, paddingBottom: space.md,
          paddingLeft: space.md, paddingRight: space.md,
        },
        Text({ fontSize: 18 }, t.icon),
        View(
          { flex: 1, gap: 2 },
          Text({ fontSize: 14, fontWeight: '500', color: colors.textPrimary }, t.name),
          Text({ fontSize: 11, color: colors.textTertiary }, dateLabel(t.at)),
        ),
        Text(
          { fontSize: 14, fontWeight: '600', color: t.amountCents > 0 ? colors.positive : colors.textPrimary },
          (t.amountCents > 0 ? '+' : '−') + '$' + (Math.abs(t.amountCents) / 100).toFixed(2),
        ),
      ),
    )),
  )
}
