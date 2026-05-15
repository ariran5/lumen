// Card-actions sheet in T-Bank style: mini card visualization on top
// (black pill with last4, chip and logo), 2×2 action grid
// (Freeze / Details / Limits / Cashback), then a settings section
// (Name on card / PIN / Reissue / Block).
//
//   ┌──────────────────────────────────────┐
//   │              ▁▁▁▁▁                   │
//   │  Card                            ✕   │
//   │  Tinkoff Black                       │
//   │                                      │
//   │  ╔══════════════════════════════╗    │
//   │  ║  ⬛  Tinkoff Black             ║    │  ← mini card
//   │  ║  ·· 4422               VISA  ║    │
//   │  ╚══════════════════════════════╝    │
//   │                                      │
//   │  [❄ Freeze]     [⊙ Details]          │  ← actions 2×2
//   │  [⚙ Limits]     [🔥 Cashback]         │
//   │                                      │
//   │  SETTINGS                            │
//   │  Name on card      Arian Allenson  › │
//   │  Change PIN                         ›│
//   │  Reissue card                       ›│
//   │  Block card (destructive)            │

import { SheetShell } from '../components/sheet-shell'
import { SheetRow } from '../components/sheet-row'
import { colors, radius, space } from '../lib/colors'
import { account } from '../state/account'
import { sheetOpen } from '../state/ui'

interface CardActionsSheetState {
  frozen: Signal<boolean>
  cardLast4: string
}

export function openCardActionsSheet(state: CardActionsSheetState): void {
  sheetOpen.value = true
  lumen.bottomSheet({
    height: 'large',
    onClose: () => { sheetOpen.value = false },
    content: SheetShell(
      {
        title: 'Карта',
        subtitle: () => state.frozen.value
          ? 'Tinkoff Black · заморожена'
          : 'Tinkoff Black',
      },

      // Mini card
      Slot({}, () => miniCard(state)),

      // Quick actions 2×2
      View(
        { gap: space.sm },
        View(
          { flexDirection: 'row', gap: space.sm },
          Slot({ flex: 1 }, () => actionTile(
            state.frozen.value ? '❄' : '⏸',
            state.frozen.value ? 'Разморозить' : 'Заморозить',
            state.frozen.value,
            () => {
              lumen.haptics('medium')
              state.frozen.value = !state.frozen.value
            },
          )),
          actionTile('⊙', 'Реквизиты', false, async () => {
            const ok = lumen.biometrics.available() === 'none'
              ? true
              : await lumen.biometrics.authenticate('Показать номер карты')
            if (ok) {
              lumen.alert({
                title: 'Реквизиты',
                message: `4422 1234 5678 ${state.cardLast4}\nСрок 12/29 · CVV 7•4`,
              })
            }
          }),
        ),
        View(
          { flexDirection: 'row', gap: space.sm },
          actionTile('⚙', 'Лимиты', false, () =>
            lumen.alert({ title: 'Лимиты', message: 'Лимиты на день: 100 000 ₽. Изменить — в настройках.' })),
          actionTile('🔥', 'Кэшбэк', false, () =>
            lumen.alert({ title: 'Кэшбэк', message: 'Май: рестораны 5%, такси 5%, АЗС 3%. Начислено 1 482 ₽.' })),
        ),
      ),

      // Settings section
      View(
        { gap: space.sm },
        Text(
          {
            fontSize: 11, fontWeight: '700',
            color: colors.textTertiary,
            paddingLeft: space.xs, paddingTop: space.xs,
          },
          'НАСТРОЙКИ КАРТЫ',
        ),
        SheetRow({
          icon: '👤',
          iconTint: colors.tileMobile,
          label: 'Имя на карте',
          value: () => account.value.holderName,
          onTap: () => lumen.alert({ title: 'Имя на карте', message: 'Изменение имени — в разработке.' }),
        }),
        SheetRow({
          icon: '🔢',
          iconTint: colors.tileQR,
          label: 'Сменить PIN',
          sublabel: 'В банкомате Tinkoff или партнёра',
          onTap: () => lumen.alert({ title: 'PIN', message: 'PIN можно изменить в любом банкомате партнёрской сети.' }),
        }),
        SheetRow({
          icon: '↻',
          iconTint: colors.tilePay,
          label: 'Перевыпустить карту',
          sublabel: '5 рабочих дней · бесплатно',
          onTap: () => lumen.actionSheet({
            title: 'Перевыпустить карту?',
            message: 'Старая карта будет заблокирована. Новая придёт в течение 5 рабочих дней.',
            actions: [{ label: 'Заказать перевыпуск' }],
            onSelect: () => lumen.alert({ title: 'Заявка принята', message: 'Курьер свяжется в течение дня.' }),
          }),
        }),
        SheetRow({
          icon: '⚠',
          iconTint: '#2A1518',
          label: 'Заблокировать карту',
          sublabel: 'Если карта потеряна или украдена',
          destructive: true,
          onTap: () => lumen.actionSheet({
            title: 'Заблокировать карту?',
            message: 'Все операции по карте будут запрещены. Перевыпуск — 5 рабочих дней.',
            actions: [{ label: 'Заблокировать', style: 'destructive' }],
            onSelect: () => {
              state.frozen.value = true
              lumen.haptics('warning')
              lumen.alert({ title: 'Карта заблокирована', message: 'Мы выпустим новую и доставим курьером.' })
            },
          }),
        }),
      ),
    ),
  })
}

/** Mini card: 1.6×1 aspect, black background, last4, chip, accent stripe on the right. */
function miniCard(state: CardActionsSheetState): RenderNode {
  return View(
    {
      backgroundColor: colors.cardBlack,
      borderRadius: 16,
      borderWidth: 1,
      borderColor: '#2F2F37',
      paddingTop: space.md, paddingBottom: space.md,
      paddingLeft: space.lg, paddingRight: space.lg,
      gap: space.md,
      opacity: state.frozen.value ? 0.55 : 1,
    },
    // Top row: brand + freeze badge
    View(
      { flexDirection: 'row', alignItems: 'center' },
      View(
        {
          width: 22, height: 22, borderRadius: 11,
          backgroundColor: colors.textPrimary,
          alignItems: 'center', justifyContent: 'center',
        },
        Text({ fontSize: 13, fontWeight: '900', color: colors.bg }, 'T'),
      ),
      Text(
        {
          flex: 1,
          fontSize: 14, fontWeight: '700',
          color: colors.textPrimary,
          paddingLeft: space.sm,
        },
        'Tinkoff Black',
      ),
      state.frozen.value
        ? View(
            {
              paddingTop: 2, paddingBottom: 2,
              paddingLeft: 8, paddingRight: 8,
              borderRadius: 8,
              backgroundColor: '#2A3144',
              borderWidth: 1,
              borderColor: '#3F4A66',
            },
            Text({ fontSize: 10, fontWeight: '700', color: '#9CB7FF' }, '❄ ЗАМОРОЖЕНА'),
          )
        : null,
    ),
    // Chip placeholder
    View(
      {
        width: 32, height: 24, borderRadius: 5,
        backgroundColor: '#C9A24A',
      },
    ),
    // Bottom row: number + payment system
    View(
      { flexDirection: 'row', alignItems: 'flex-end' },
      View(
        { flex: 1, gap: 2 },
        Text({ fontSize: 11, color: '#80808E' }, 'Номер карты'),
        Text(
          { fontSize: 18, fontWeight: '700', color: colors.textPrimary },
          '•••• ' + state.cardLast4,
        ),
      ),
      Text({ fontSize: 16, fontWeight: '900', color: colors.textPrimary }, 'VISA'),
    ),
  )
}

function actionTile(icon: string, label: string, active: boolean, onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap,
      flex: 1,
      paddingTop: space.md, paddingBottom: space.md,
      borderRadius: radius.control,
      backgroundColor: active ? colors.accentSoft : colors.surface,
      borderWidth: 1,
      borderColor: active ? colors.accent : colors.border,
      alignItems: 'center',
      gap: 6,
    },
    View(
      {
        width: 36, height: 36, borderRadius: 18,
        backgroundColor: active ? colors.accent : colors.surfaceElevated,
        alignItems: 'center', justifyContent: 'center',
      },
      Text(
        { fontSize: 16, color: active ? colors.textOnAccent : colors.textPrimary },
        icon,
      ),
    ),
    Text(
      {
        fontSize: 12, fontWeight: '700',
        color: active ? colors.accent : colors.textPrimary,
      },
      label,
    ),
  )
}
