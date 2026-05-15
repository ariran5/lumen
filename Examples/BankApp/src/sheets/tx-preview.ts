// Transaction receipt. Tap on a tx row on Home → this sheet in T-Bank style:
// big category icon, large centered amount, merchant name,
// receipt section with details (category, date, payment method, cashback,
// MCC), then a quick-action grid (Repeat / Chat / Cashback / Category),
// and at the end — a "Подробнее" link to the full detail.

import { SheetShell } from '../components/sheet-shell'
import { colors, radius, space } from '../lib/colors'
import { dateLabel, money, moneyShort } from '../lib/format'
import { open } from '../lib/router'
import { findTransaction, type Tx } from '../state/transactions'
import { sheetOpen } from '../state/ui'

export function openTxPreviewSheet(txID: number): void {
  const tx = findTransaction(txID)
  if (!tx) return

  // Cashback for the preview demo: 1% of spend, nothing on income.
  const cashbackCents = tx.amountCents < 0 ? Math.round(Math.abs(tx.amountCents) * 0.01) : 0

  sheetOpen.value = true
  lumen.bottomSheet({
    height: 'large',
    onClose: () => { sheetOpen.value = false },
    content: SheetShell(
      { title: 'Операция' },

      // Hero — large icon + amount + merchant
      View(
        { alignItems: 'center', gap: space.sm, paddingTop: space.md, paddingBottom: space.md },
        View(
          {
            width: 76, height: 76, borderRadius: 38,
            backgroundColor: colors.surfaceElevated,
            alignItems: 'center', justifyContent: 'center',
          },
          Text({ fontSize: 38 }, tx.icon),
        ),
        Text(
          {
            fontSize: 32, fontWeight: '800',
            color: tx.amountCents > 0 ? colors.positive : colors.textPrimary,
            textAlign: 'center',
          },
          (tx.amountCents > 0 ? '+' : '') + money(tx.amountCents),
        ),
        Text(
          { fontSize: 16, fontWeight: '600', color: colors.textPrimary, textAlign: 'center' },
          tx.name,
        ),
        Text(
          { fontSize: 12, color: colors.textTertiary, textAlign: 'center' },
          tx.category + ' · ' + dateLabel(tx.at),
        ),
      ),

      // Cashback banner for spending operations
      cashbackCents > 0
        ? View(
            {
              flexDirection: 'row',
              alignItems: 'center',
              gap: space.md,
              backgroundColor: colors.accentSoft,
              borderRadius: radius.control,
              paddingTop: space.md, paddingBottom: space.md,
              paddingLeft: space.md, paddingRight: space.md,
            },
            View(
              {
                width: 36, height: 36, borderRadius: 18,
                backgroundColor: colors.accent,
                alignItems: 'center', justifyContent: 'center',
              },
              Text({ fontSize: 16 }, '🔥'),
            ),
            View(
              { flex: 1, gap: 2 },
              Text({ fontSize: 14, fontWeight: '700', color: colors.textPrimary }, 'Кэшбэк ' + moneyShort(cashbackCents)),
              Text({ fontSize: 11, color: colors.textSecondary }, 'Начислено за операцию · 1%'),
            ),
          )
        : null,

      // Quick actions grid 4x1
      actionsGrid(tx),

      // Receipt section
      receiptSection(tx, cashbackCents),

      // Open full page
      Pressable(
        {
          onTap: () => {
            // TODO: programmatic dismiss; for now router.push rises over the sheet
            open('transactionDetail', { id: tx.id })
          },
          paddingTop: space.md, paddingBottom: space.md,
          borderRadius: radius.control,
          backgroundColor: colors.surface,
          borderWidth: 1, borderColor: colors.border,
          alignItems: 'center',
        },
        Text({ fontSize: 15, fontWeight: '700', color: colors.accent }, 'Подробнее →'),
      ),
    ),
  })
}

function actionsGrid(tx: Tx): RenderNode {
  return View(
    { flexDirection: 'row', gap: space.sm },
    quickAction('↻', 'Повторить', () =>
      lumen.alert({ title: 'Повтор операции', message: `Создаём такой же платёж ${money(Math.abs(tx.amountCents))} в ${tx.name}.` }),
    ),
    quickAction('💬', 'В чат', () =>
      lumen.alert({ title: 'Чат поддержки', message: 'Откроем диалог с оператором по этой операции.' }),
    ),
    quickAction('📄', 'Чек', () =>
      lumen.alert({ title: 'Электронный чек', message: 'PDF-чек будет отправлен на email.' }),
    ),
    quickAction('⚐', 'Спор', () =>
      lumen.actionSheet({
        title: 'Оспорить операцию?',
        message: 'Мы заблокируем сумму и начнём проверку. Это займёт до 30 дней.',
        actions: [
          { label: 'Оспорить', style: 'destructive' },
        ],
        onSelect: () => lumen.alert({ title: 'Заявка принята', message: 'Чат поддержки скоро напишет.' }),
      }),
    ),
  )
}

function quickAction(icon: string, label: string, onTap: () => void): RenderNode {
  return Pressable(
    {
      onTap: () => { lumen.haptics('light'); onTap() },
      flex: 1,
      paddingTop: space.md, paddingBottom: space.md,
      borderRadius: radius.control,
      backgroundColor: colors.surface,
      borderWidth: 1, borderColor: colors.border,
      alignItems: 'center',
      gap: 6,
    },
    View(
      {
        width: 36, height: 36, borderRadius: 18,
        backgroundColor: colors.surfaceElevated,
        alignItems: 'center', justifyContent: 'center',
      },
      Text({ fontSize: 16, color: colors.textPrimary }, icon),
    ),
    Text({ fontSize: 11, fontWeight: '600', color: colors.textPrimary, textAlign: 'center' }, label),
  )
}

function receiptSection(tx: Tx, cashbackCents: number): RenderNode {
  const rows: RenderNode[] = []

  rows.push(receiptRow('Категория', tx.category, '›', () =>
    lumen.alert({ title: 'Категория', message: 'Изменение категории — в разработке.' })))
  rows.push(divider())
  rows.push(receiptRow('Когда', dateLabel(tx.at)))
  rows.push(divider())
  rows.push(receiptRow('Счёт', 'Tinkoff Black ·· 4422'))
  rows.push(divider())
  rows.push(receiptRow('Способ', 'Apple Pay'))
  rows.push(divider())
  rows.push(receiptRow('MCC', tx.amountCents > 0 ? '6011' : '5814'))
  if (cashbackCents > 0) {
    rows.push(divider())
    rows.push(receiptRow('Кэшбэк', moneyShort(cashbackCents), undefined, undefined, colors.accent))
  }
  if (tx.note) {
    rows.push(divider())
    rows.push(receiptRow('Комментарий', tx.note))
  }

  return View(
    {
      backgroundColor: colors.surface,
      borderRadius: radius.card,
      borderWidth: 1, borderColor: colors.border,
      paddingLeft: space.md, paddingRight: space.md,
      paddingTop: space.xs, paddingBottom: space.xs,
    },
    ...rows,
  )
}

function receiptRow(
  label: string,
  value: string,
  chevron?: string,
  onTap?: () => void,
  valueColor?: Color,
): RenderNode {
  const content = View(
    { flexDirection: 'row', alignItems: 'center', paddingTop: space.md, paddingBottom: space.md },
    Text({ flex: 1, fontSize: 14, color: colors.textTertiary }, label),
    Text(
      { fontSize: 14, fontWeight: '600', color: valueColor ?? colors.textPrimary, numberOfLines: 1 },
      value,
    ),
    chevron
      ? Text({ fontSize: 16, color: colors.textTertiary, paddingLeft: space.sm }, chevron)
      : null,
  )
  if (onTap) {
    return Pressable(
      { onTap: () => { lumen.haptics('soft'); onTap() } },
      content,
    )
  }
  return content
}

function divider(): RenderNode {
  return View({ height: 1, backgroundColor: colors.divider })
}

