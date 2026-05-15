// AccountRow — row in the home accounts list. Left: a round
// icon tinted by account type; center: title and subtitle;
// right: balance (or meta line) and chevron.
//
// Tap → bottom-sheet with actions (Send/Deposit) for cards, or
// router.push to account details for savings/invest. For now — a stub
// with haptics + alert.

import { colors, radius, space } from '../lib/colors'
import { moneyShort } from '../lib/format'
import type { AccountItem } from '../state/accounts'
import { openSendSheet } from '../sheets/send'
import { openCardActionsSheet } from '../sheets/card-actions'

/** Per-card frozen-state. Created lazily on the first tap on a card,
 *  so the card-actions sheet receives a stable signal across openings. */
const frozenByCardId = new Map<string, Signal<boolean>>()
function frozenSignalFor(id: string): Signal<boolean> {
  let s = frozenByCardId.get(id)
  if (!s) { s = signal<boolean>(false); frozenByCardId.set(id, s) }
  return s
}

const ICON = 44

export function AccountRow(item: AccountItem): RenderNode {
  const isCredit = item.kind === 'credit'

  const balText: Thunk<string> = () => {
    const v = typeof item.balanceCents === 'function' ? item.balanceCents() : item.balanceCents
    return moneyShort(v)
  }

  const balColor: Color = isCredit ? colors.negative : colors.textPrimary

  return Pressable(
    {
      key: 'acc-' + item.id,
      onTap: () => {
        lumen.haptics('soft')
        onTap(item)
      },
      flexDirection: 'row',
      alignItems: 'center',
      gap: space.md,
      paddingTop: space.md,
      paddingBottom: space.md,
      paddingLeft: space.md,
      paddingRight: space.md,
      borderRadius: radius.control,
    },
    // Tinted icon tile
    View(
      {
        width: ICON, height: ICON,
        borderRadius: ICON / 2,
        backgroundColor: item.tint,
        alignItems: 'center',
        justifyContent: 'center',
      },
      Text({ fontSize: 22 }, item.icon),
    ),

    // Title + subtitle
    View(
      { flex: 1, gap: 2 },
      Text(
        { fontSize: 15, fontWeight: '600', color: colors.textPrimary, numberOfLines: 1 },
        item.title,
      ),
      item.subtitle
        ? Text(
            { fontSize: 12, color: colors.textTertiary, numberOfLines: 1 },
            item.subtitle,
          )
        : null,
    ),

    // Right column: balance + meta
    View(
      { alignItems: 'flex-end', gap: 2 },
      Text(
        { fontSize: 15, fontWeight: '700', color: balColor },
        balText,
      ),
      metaNode(item),
    ),
  )
}

function metaNode(item: AccountItem): RenderNode | null {
  const m = item.metaLine
  if (!m) return null
  const props: TextProps = {
    fontSize: 11,
    color: item.kind === 'invest' ? colors.positive : colors.textTertiary,
  }
  return typeof m === 'function' ? Text(props, m) : Text(props, m)
}

function onTap(item: AccountItem): void {
  switch (item.kind) {
    case 'card': {
      const last4 = item.subtitle?.match(/\d{4}/)?.[0] ?? '0000'
      openCardActionsSheet({ frozen: frozenSignalFor(item.id), cardLast4: last4 })
      break
    }
    case 'savings':
      openSendSheet()
      break
    case 'invest':
      lumen.alert({ title: item.title, message: 'Брокерский счёт в разработке.' })
      break
    case 'credit':
      lumen.alert({ title: item.title, message: 'Подробности по кредиту в разработке.' })
      break
  }
}
