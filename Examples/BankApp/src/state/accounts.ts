// List of the user's financial products — cards, savings, investments,
// credit. Shown on the home in groups; the main balance (Tinkoff Black)
// lives in `balanceCents` from `account.ts`, the rest sits here.
//
// The computed aggregate `totalAssetsCents` sums positive positions —
// shown at the top of the home as "total capital".

import { balanceCents } from './account'
import { colors } from '../lib/colors'

export type AccountKind = 'card' | 'savings' | 'invest' | 'credit'

export interface AccountItem {
  id: string
  kind: AccountKind
  /** Short name in the list. */
  title: string
  /** Subtitle (card type / deposit term / ticker). */
  subtitle?: string
  /** Emoji icon on the left. */
  icon: string
  /** Tile tint color. */
  tint: string
  /** Current balance in kopecks. For credit — remaining debt (negative). */
  balanceCents: number | (() => number)
  /** YTD return in kopecks (for invest) or deposit rate (savings). */
  metaLine?: string | (() => string)
  /** Hidden from the home (shown only in "All products"). */
  hidden?: boolean
}

/** Card products — separate so we can show them in a hero-rail. */
export const cards = signal<AccountItem[]>([
  {
    id: 'black',
    kind: 'card',
    title: 'Tinkoff Black',
    subtitle: '·· 4422',
    icon: '⬛',
    tint: colors.cardBlack,
    balanceCents: () => balanceCents.value,
  },
  {
    id: 'platinum',
    kind: 'card',
    title: 'Platinum',
    subtitle: 'Кредитная · ·· 7781',
    icon: '◾',
    tint: colors.cardPremium,
    balanceCents: 0,
    metaLine: 'Лимит 150 000 ₽',
  },
  {
    id: 'all-airlines',
    kind: 'card',
    title: 'All Airlines',
    subtitle: 'Мили · ·· 0290',
    icon: '✈️',
    tint: colors.cardPremium,
    balanceCents: 12_450_00,
    metaLine: '8 420 миль',
  },
])

export const savings = signal<AccountItem[]>([
  {
    id: 'goal-vacation',
    kind: 'savings',
    title: 'Отпуск',
    subtitle: 'Цель 250 000 ₽',
    icon: '🏝️',
    tint: colors.cardSavings,
    balanceCents: 138_400_00,
    metaLine: '55% до цели',
  },
  {
    id: 'reserve',
    kind: 'savings',
    title: 'Подушка',
    subtitle: 'Накопительный',
    icon: '🪙',
    tint: colors.cardSavings,
    balanceCents: 412_300_00,
    metaLine: '16% годовых',
  },
])

export const investments = signal<AccountItem[]>([
  {
    id: 'broker',
    kind: 'invest',
    title: 'Брокерский счёт',
    subtitle: 'ИИС-Б · РФ',
    icon: '📈',
    tint: colors.cardInvest,
    balanceCents: 1_286_540_00,
    metaLine: '+8,4% YTD',
  },
])

export const credits = signal<AccountItem[]>([
  {
    id: 'mortgage',
    kind: 'credit',
    title: 'Ипотека',
    subtitle: 'Семейная · до 2042',
    icon: '🏠',
    tint: colors.cardCredit,
    balanceCents: -4_120_000_00,
    metaLine: 'Платёж 47 800 ₽ · 14 мая',
    hidden: true,
  },
])

/** Sum of assets (cards + savings + invest), excluding credits. */
export const totalAssetsCents = computed<number>(() => {
  let sum = 0
  for (const acc of cards.value) {
    const v = typeof acc.balanceCents === 'function' ? acc.balanceCents() : acc.balanceCents
    if (v > 0) sum += v
  }
  for (const acc of savings.value) {
    const v = typeof acc.balanceCents === 'function' ? acc.balanceCents() : acc.balanceCents
    sum += v
  }
  for (const acc of investments.value) {
    const v = typeof acc.balanceCents === 'function' ? acc.balanceCents() : acc.balanceCents
    sum += v
  }
  return sum
})
