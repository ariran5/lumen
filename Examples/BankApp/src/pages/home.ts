// Home / "Главная" — analog of T-Bank's start screen.
//
// Skeleton:
//   ┌────────────────────────────────────────────────────────┐
//   │ Avatar    Name                         🔔   🔍         │  ← Header
//   │                                                        │
//   │   2 478 920 ₽                                          │  ← Total assets
//   │   All money · tap to hide                              │
//   │                                                        │
//   │  ◯ ◯ ◯ ◯ ◯                                             │  ← Stories rail
//   │  Cash Rate Gift Travel +N                              │
//   │                                                        │
//   │ ┌── Payments & transfers ─────────────────────────────┐│  ← Services grid
//   │ │ [📲] [💳] [⊞] [⬇]                                   ││
//   │ │ [📞] [🏛️] [🛫] [⋯]                                   ││
//   │ └─────────────────────────────────────────────────────┘│
//   │                                                        │
//   │ My accounts                                            │  ← Cards section
//   │ ⬛ Tinkoff Black ·· 4422             241 850 ₽         │
//   │ ◾ Platinum (credit) ·· 7781               0 ₽         │
//   │ ✈️  All Airlines ·· 0290             12 450 ₽          │
//   │ ＋ Open new card                                       │
//   │                                                        │
//   │ Savings                                                │  ← Savings section
//   │ 🏝️ Vacation             138 400 ₽ · 55%               │
//   │ 🪙 Cushion              412 300 ₽ · 16% APR            │
//   │                                                        │
//   │ Investments                                            │  ← Invest section
//   │ 📈 Brokerage           1 286 540 ₽ · +8,4% YTD         │
//   │                                                        │
//   │ ┌── 🔥 May cashback ──────────────────────────────────┐│  ← Promo banner
//   │ │ 5% restaurants, 5% taxi, 3% gas                     ││
//   │ │ Activate →                                          ││
//   │ └─────────────────────────────────────────────────────┘│
//   │                                                        │
//   │ Recent activity              All →                     │  ← Tx list
//   │ ☕ Skuratov Coffee · Cafe          −320 ₽              │
//   │ 🛒 Pyaterochka · Supermarkets    −1 579 ₽              │
//   │ ...                                                    │
//   └────────────────────────────────────────────────────────┘
//
// Reactivity: module-level signals (balanceCents / cards / savings /
// transactions) are already shared between pages. Slot wraps each
// dynamic section so that changing one array doesn't rebuild
// the whole home.

import { colors, radius, space } from '../lib/colors'
import { money, moneyShort } from '../lib/format'
import { Avatar } from '../components/avatar'
import { StoryRail } from '../components/story-rail'
import { ServicesGrid } from '../components/services-grid'
import { AccountRow } from '../components/account-row'
import { PromoBanner } from '../components/promo-banner'
import { account } from '../state/account'
import { cards, savings, investments, totalAssetsCents, type AccountItem } from '../state/accounts'
import { transactions, type Tx } from '../state/transactions'
import { TAB_BAR_HEIGHT, activeTab } from '../state/ui'
import { openTxPreviewSheet } from '../sheets/tx-preview'

/** Whether the total balance is hidden — toggled by tapping on the amount. Local to the page. */
const balanceHidden = signal(false)

export function homePage() {
  return {
    render: renderHome,
  }
}

function renderHome(): RenderNode {
  return View(
    { flex: 1, backgroundColor: colors.bg },

    headerBar(),

    ScrollView(
      {
        flex: 1,
        paddingBottom: TAB_BAR_HEIGHT + Math.max(lumen.safeArea.bottom, space.lg) + space.xxl,
        gap: space.lg,
      },
      totalCapital(),
      StoryRail(),
      paymentsSection(),
      cardsSection(),
      savingsSection(),
      investSection(),
      promoSection(),
      recentSection(),
    ),
  )
}

// ─────────────────────────────────────────────────────────────────
// Header

function headerBar(): RenderNode {
  return View(
    {
      flexDirection: 'row',
      alignItems: 'center',
      gap: space.md,
      paddingTop: lumen.safeArea.top + space.sm,
      paddingBottom: space.md,
      paddingLeft: space.lg,
      paddingRight: space.lg,
    },
    Avatar({
      name: account.peek().holderName,
      size: 40,
      onTap: () => { activeTab.value = 'profile' },
    }),
    View(
      { flex: 1 },
      Text({ fontSize: 11, color: colors.textTertiary, fontWeight: '500' }, 'Привет,'),
      Text(
        { fontSize: 16, fontWeight: '700', color: colors.textPrimary, numberOfLines: 1 },
        () => account.value.holderName.split(' ')[0]!,
      ),
    ),
    iconButton('🔔', () => lumen.alert({
      title: 'Уведомления',
      message: 'Пока тихо: всё прочитано.',
    })),
    iconButton('🔍', () => lumen.alert({
      title: 'Поиск',
      message: 'Поиск по операциям, счетам и платежам — в разработке.',
    })),
  )
}

function iconButton(icon: string, onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap: () => { lumen.haptics('soft'); onTap() },
      width: 38, height: 38, borderRadius: 19,
      backgroundColor: colors.surfaceElevated,
      alignItems: 'center', justifyContent: 'center',
    },
    Text({ fontSize: 17, color: colors.textPrimary }, icon),
  )
}

// ─────────────────────────────────────────────────────────────────
// Total capital — large "header-amount" in T-Bank style

function totalCapital(): RenderNode {
  return Pressable(
    {
      onTap: () => {
        lumen.haptics('soft')
        balanceHidden.value = !balanceHidden.peek()
      },
      paddingLeft: space.lg, paddingRight: space.lg,
      paddingTop: space.xs,
      gap: 2,
    },
    Text(
      { fontSize: 34, fontWeight: '800', color: colors.textPrimary },
      () => balanceHidden.value ? '••••••••' : moneyShort(totalAssetsCents.value),
    ),
    Text(
      { fontSize: 12, color: colors.textTertiary, fontWeight: '500' },
      () => balanceHidden.value ? 'Нажмите, чтобы показать' : 'Все деньги · нажмите, чтобы скрыть',
    ),
  )
}

// ─────────────────────────────────────────────────────────────────
// Payments & transfers

function paymentsSection(): RenderNode {
  return View(
    { paddingLeft: space.lg, paddingRight: space.lg, gap: space.sm },
    sectionHeader('Платежи и переводы', null),
    ServicesGrid(),
  )
}

// ─────────────────────────────────────────────────────────────────
// Cards / Savings / Invest — single template for account sections

/** Inset-divider: 1pt gray line with a left inset under the row icon.
 *  Lumen-flex doesn't know about margin, so we build a row from a spacer + a bar. */
function divider(insetLeft: number): RenderNode {
  return View(
    { flexDirection: 'row', height: 1 },
    View({ width: insetLeft }),
    View({ flex: 1, height: 1, backgroundColor: colors.divider }),
  )
}

function accountsCard(items: () => AccountItem[], extra?: RenderNode | null): RenderNode {
  return View(
    {
      backgroundColor: colors.surface,
      borderRadius: radius.card,
      borderWidth: 1,
      borderColor: colors.border,
      padding: space.xs,
      gap: 0,
    },
    Slot({ gap: 0 }, () => {
      const list = items()
      const visible = list.filter(a => !a.hidden)
      const rows: RenderNode[] = []
      for (let i = 0; i < visible.length; i++) {
        rows.push(AccountRow(visible[i]))
        if (i < visible.length - 1) {
          rows.push(divider(44 + space.md + space.md))
        }
      }
      return rows
    }),
    extra ?? null,
  )
}

function cardsSection(): RenderNode {
  return View(
    { paddingLeft: space.lg, paddingRight: space.lg, gap: space.sm },
    sectionHeader('Мои карты', null),
    accountsCard(
      () => cards.value,
      addRow('＋', 'Открыть новую карту', () =>
        lumen.alert({ title: 'Новая карта', message: 'Выбор продукта в разработке.' }),
      ),
    ),
  )
}

function savingsSection(): RenderNode {
  return View(
    { paddingLeft: space.lg, paddingRight: space.lg, gap: space.sm },
    sectionHeader('Накопления', null),
    accountsCard(
      () => savings.value,
      addRow('🎯', 'Создать цель', () =>
        lumen.alert({ title: 'Новая цель', message: 'Постановка финансовой цели — в разработке.' }),
      ),
    ),
  )
}

function investSection(): RenderNode {
  return View(
    { paddingLeft: space.lg, paddingRight: space.lg, gap: space.sm },
    sectionHeader('Инвестиции', 'История'),
    accountsCard(() => investments.value),
  )
}

function addRow(icon: string, label: string, onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap: () => { lumen.haptics('soft'); onTap() },
      flexDirection: 'row',
      alignItems: 'center',
      gap: space.md,
      paddingTop: space.md, paddingBottom: space.md,
      paddingLeft: space.md, paddingRight: space.md,
      borderRadius: radius.control,
    },
    View(
      {
        width: 44, height: 44, borderRadius: 22,
        backgroundColor: colors.surfaceElevated,
        alignItems: 'center', justifyContent: 'center',
      },
      Text({ fontSize: 20, color: colors.accent }, icon),
    ),
    Text(
      { flex: 1, fontSize: 14, fontWeight: '600', color: colors.accent },
      label,
    ),
  )
}

// ─────────────────────────────────────────────────────────────────
// Section header + promo + recent

function sectionHeader(title: string, link: string | null): RenderNode {
  return View(
    { flexDirection: 'row', alignItems: 'center', paddingLeft: space.xs, paddingTop: space.xs },
    Text(
      { flex: 1, fontSize: 18, fontWeight: '700', color: colors.textPrimary },
      title,
    ),
    link
      ? Pressable(
          {
            onTap: () => { lumen.haptics('soft'); activeTab.value = 'history' },
            paddingTop: space.xs, paddingBottom: space.xs,
            paddingLeft: space.sm, paddingRight: space.sm,
          },
          Text({ fontSize: 13, color: colors.textSecondary, fontWeight: '600' }, link + ' →'),
        )
      : null,
  )
}

function promoSection(): RenderNode {
  return View(
    { paddingLeft: space.lg, paddingRight: space.lg, gap: space.md },
    PromoBanner({
      title: 'Кэшбэк мая',
      subtitle: '5% на рестораны и такси, 3% на АЗС. До 5 000 ₽ за месяц.',
      cta: 'Подключить',
      icon: '🔥',
    }),
    PromoBanner({
      title: 'Tinkoff Pro',
      subtitle: 'Подписка с повышенным кэшбэком, бесплатными переводами и страховкой покупок.',
      cta: 'Попробовать 60 дней',
      icon: '⭐',
      bg: colors.surface,
      fg: colors.textPrimary,
    }),
  )
}

function recentSection(): RenderNode {
  return View(
    { paddingLeft: space.lg, paddingRight: space.lg, gap: space.sm },
    sectionHeader('Последние операции', 'Все'),
    View(
      {
        backgroundColor: colors.surface,
        borderRadius: radius.card,
        borderWidth: 1,
        borderColor: colors.border,
        padding: space.xs,
        gap: 0,
      },
      Slot({ gap: 0 }, () => {
        const list = transactions.value.slice(0, 6)
        const rows: RenderNode[] = []
        for (let i = 0; i < list.length; i++) {
          rows.push(txRow(list[i]!))
          if (i < list.length - 1) {
            rows.push(divider(44 + space.md + space.md))
          }
        }
        return rows
      }),
    ),
  )
}

function txRow(t: Tx): RenderNode {
  return Pressable(
    {
      key: 'home-tx-' + t.id,
      onTap: () => { lumen.haptics('soft'); openTxPreviewSheet(t.id) },
      flexDirection: 'row',
      alignItems: 'center',
      gap: space.md,
      paddingTop: space.md, paddingBottom: space.md,
      paddingLeft: space.md, paddingRight: space.md,
      borderRadius: radius.control,
    },
    View(
      {
        width: 44, height: 44, borderRadius: 22,
        backgroundColor: colors.surfaceElevated,
        alignItems: 'center', justifyContent: 'center',
      },
      Text({ fontSize: 22 }, t.icon),
    ),
    View(
      { flex: 1, gap: 2 },
      Text({ fontSize: 14, fontWeight: '600', color: colors.textPrimary, numberOfLines: 1 }, t.name),
      Text({ fontSize: 12, color: colors.textTertiary, numberOfLines: 1 }, t.category),
    ),
    Text(
      {
        fontSize: 14,
        fontWeight: '700',
        color: t.amountCents > 0 ? colors.positive : colors.textPrimary,
      },
      (t.amountCents > 0 ? '+' : '') + money(t.amountCents),
    ),
  )
}
