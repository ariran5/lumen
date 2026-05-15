// "Payments & transfers" grid — 2 rows of 4 tiles. T-Bank draws this
// as a grid of round-square tiles with emoji + caption below.
// For now every tap is a stub via haptics + alert; in production
// each tile pushes its own page or opens a sheet.

import { colors, radius, space } from '../lib/colors'
import { openSendSheet } from '../sheets/send'
import { openDepositSheet } from '../sheets/deposit'

interface ServiceTile {
  id: string
  icon: string
  label: string
  tint: Color
  onTap: () => void
}

const tiles: ServiceTile[] = [
  {
    id: 'phone',
    icon: '📲',
    label: 'По\nтелефону',
    tint: colors.tileMobile,
    onTap: () => openSendSheet(),
  },
  {
    id: 'card',
    icon: '💳',
    label: 'По номеру\nкарты',
    tint: colors.tileTransfer,
    onTap: () => openSendSheet(),
  },
  {
    id: 'qr',
    icon: '⊞',
    label: 'Оплатить\nQR',
    tint: colors.tileQR,
    onTap: () => stub('Оплата по QR', 'Откройте камеру и наведите её на QR-код.'),
  },
  {
    id: 'topup',
    icon: '⬇',
    label: 'Пополнить',
    tint: colors.tilePay,
    onTap: () => openDepositSheet(),
  },
  {
    id: 'mobile',
    icon: '📞',
    label: 'Связь',
    tint: colors.tileMobile,
    onTap: () => stub('Мобильная связь', 'Пополнение телефона любого оператора без комиссии.'),
  },
  {
    id: 'gov',
    icon: '🏛️',
    label: 'Госуслуги',
    tint: colors.tileGov,
    onTap: () => stub('Госуслуги', 'Налоги, штрафы, госпошлины, ЖКХ.'),
  },
  {
    id: 'travel',
    icon: '🛫',
    label: 'Travel',
    tint: colors.tileTravel,
    onTap: () => stub('Tinkoff Travel', 'Авиа, отели, ж/д со скидкой и кэшбэком до 5%.'),
  },
  {
    id: 'all',
    icon: '⋯',
    label: 'Все\nплатежи',
    tint: colors.surfaceElevated,
    onTap: () => stub('Все платежи', 'Каталог получателей: ЖКХ, провайдеры, благотворительность.'),
  },
]

function stub(title: string, message: string): void {
  lumen.alert({ title, message })
}

export function ServicesGrid(): RenderNode {
  const rows: RenderNode[] = []
  for (let i = 0; i < tiles.length; i += 4) {
    rows.push(View(
      { flexDirection: 'row', gap: space.sm },
      ...tiles.slice(i, i + 4).map(tile),
    ))
  }
  return View({ gap: space.sm }, ...rows)
}

function tile(t: ServiceTile): RenderNode {
  return Pressable(
    {
      key: t.id,
      onTap: () => { lumen.haptics('light'); t.onTap() },
      flex: 1,
      paddingTop: space.md,
      paddingBottom: space.md,
      paddingLeft: space.xs,
      paddingRight: space.xs,
      borderRadius: radius.card,
      backgroundColor: colors.surface,
      borderWidth: 1,
      borderColor: colors.border,
      alignItems: 'center',
      gap: 8,
    },
    View(
      {
        width: 40, height: 40, borderRadius: 20,
        backgroundColor: t.tint,
        alignItems: 'center',
        justifyContent: 'center',
      },
      Text({ fontSize: 20 }, t.icon),
    ),
    Text(
      {
        fontSize: 11,
        fontWeight: '600',
        color: colors.textPrimary,
        textAlign: 'center',
        numberOfLines: 2,
        lineHeight: 13,
      },
      t.label,
    ),
  )
}
