// BankLab — banking dashboard. Demonstrates:
//  • ScrollView + sticky Glass pill (thunk-driven opacity and text)
//  • Slot — reactive transactions list
//  • bottomSheet with transaction details
//  • Quick actions row, hero card with balance
//  • Filter chips (Pressable + state)
//  • Reactive balance when adding transactions

// ─────────── data ───────────

interface Tx {
  id: number
  icon: string
  name: string
  category: string
  amountCents: number   // negative = spend, positive = income
  whenLabel: string
}

const initial: Tx[] = [
  {id: 1, icon: '☕', name: 'Blue Bottle', category: 'Coffee', amountCents: -485, whenLabel: 'Today, 09:14'},
  {id: 2, icon: '🛒', name: 'Whole Foods', category: 'Groceries', amountCents: -8240, whenLabel: 'Today, 08:02'},
  {id: 3, icon: '💰', name: 'Acme Inc · Salary', category: 'Income', amountCents: 320000, whenLabel: 'Yesterday'},
  {id: 4, icon: '🎬', name: 'Netflix', category: 'Subscriptions', amountCents: -1299, whenLabel: 'Yesterday'},
  {id: 5, icon: '🚇', name: 'Metro', category: 'Transit', amountCents: -275, whenLabel: 'Mon'},
  {id: 6, icon: '🍔', name: 'Shake Shack', category: 'Restaurants', amountCents: -1840, whenLabel: 'Mon'},
  {id: 7, icon: '⛽', name: 'Shell Station', category: 'Fuel', amountCents: -6230, whenLabel: 'Sun'},
  {id: 8, icon: '📱', name: 'AT&T', category: 'Phone', amountCents: -4500, whenLabel: 'Sat'},
  {id: 9, icon: '✈️', name: 'United Airlines', category: 'Travel', amountCents: -42800, whenLabel: 'Fri'},
]

const transactions = signal<Tx[]>(initial)
const filter = signal<'all' | 'income' | 'spending'>('all')
const scrollOffset = signal(0)
let nextID = initial.length + 1

const balance = computed(() => {
  let sum = 0
  for (const t of transactions.value) sum += t.amountCents
  return sum
})

const visibleTx = computed(() => {
  const f = filter.value
  if (f === 'all') return transactions.value
  return transactions.value.filter(t =>
    f === 'income' ? t.amountCents > 0 : t.amountCents < 0)
})

const weekDelta = computed(() => {
  // Simple model: positives − negatives for "this week" (first 5 items)
  let s = 0
  for (const t of transactions.value.slice(0, 5)) s += t.amountCents
  return s
})

// ─────────── helpers ───────────

function fmtCents(c: number, signed = false) {
  const abs = Math.abs(c) / 100
  const s = abs.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2})
  if (!signed) return '$' + s
  return (c >= 0 ? '+$' : '−$') + s
}

function amountColor(c: number): Color {
  return c >= 0 ? '#0A8754' : '#0F0F12'
}

// ─────────── app ───────────
// System light colors — so the Liquid Glass sheet (iOS 26)
// harmonizes with the app rather than contrasting.
//   bg page      #F2F2F7  (UIColor.systemGroupedBackground)
//   bg card      #FFFFFF
//   bg pill/btn  #FFFFFF  with a thin border
//   text 1       #0F0F12
//   text 2       #6B6B73  (.secondaryLabel-ish)
//   border       #E5E5EA  (.separator)
//   accent       #007AFF  (.systemBlue)
//   positive     #0A8754
//   destructive  #FF3B30

function App() {
  return View({flex: 1, backgroundColor: '#F2F2F7'},
    Body(),
    StickyHeader(),
  )
}

function Body() {
  return ScrollView({
    flex: 1,
    paddingTop: lumen.safeArea.top + 16,
    paddingBottom: lumen.safeArea.bottom + 16,
    paddingLeft: 16,
    paddingRight: 16,
    gap: 20,
    onScroll: (e) => { scrollOffset.value = e.offset },
  },
    Greeting(),
    BalanceCard(),
    QuickActions(),
    FilterChips(),
    TransactionsHeader(),
    Slot({gap: 4},
      () => visibleTx.value.map(TransactionRow)
    ),
    AddDemoButton(),
  )
}

// ─────────── sticky pill ───────────

function StickyHeader() {
  return View({
    position: 'absolute',
    top: lumen.safeArea.top + 6,
    left: 16, right: 16,
    opacity: () => Math.min(1, Math.max(0, (scrollOffset.value - 80) / 60)),
  },
    Glass({
      variant: 'regular',
      paddingTop: 10, paddingBottom: 10,
      paddingLeft: 16, paddingRight: 16,
      borderRadius: 22,
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
    },
      Text({fontSize: 13, fontWeight: '700', color: '#0F0F12', flex: 1},
        () => `Personal · ${fmtCents(balance.value)}`),
      Text({fontSize: 11, color: '#6B6B73'},
        () => `${visibleTx.value.length} tx`),
    ),
  )
}

// ─────────── greeting ───────────

function Greeting() {
  return View({gap: 4, paddingTop: 8},
    Text({fontSize: 12, color: '#6B6B73', fontWeight: '600'},
      'GOOD MORNING'),
    Text({fontSize: 20, color: '#0F0F12', fontWeight: '600'},
      'Arian'),
  )
}

// ─────────── balance ───────────

function BalanceCard() {
  return View({
    backgroundColor: '#FFFFFF',
    borderColor: '#E5E5EA',
    borderWidth: 1,
    borderRadius: 18,
    paddingTop: 22, paddingBottom: 22,
    paddingLeft: 22, paddingRight: 22,
    gap: 8,
  },
    Text({fontSize: 11, fontWeight: '700', color: '#6B6B73'},
      'PERSONAL'),
    Text({fontSize: 38, fontWeight: '700', color: '#0F0F12'},
      () => fmtCents(balance.value)),
    View({flexDirection: 'row', gap: 6, alignItems: 'center'},
      Text({fontSize: 13, fontWeight: '600',
            color: () => weekDelta.value >= 0 ? '#0A8754' : '#FF3B30'},
        () => weekDelta.value >= 0 ? '▲' : '▼'),
      Text({fontSize: 13, fontWeight: '600',
            color: () => weekDelta.value >= 0 ? '#0A8754' : '#FF3B30'},
        () => fmtCents(weekDelta.value, true) + ' this week'),
    ),
  )
}

// ─────────── quick actions ───────────

function QuickActions() {
  return View({flexDirection: 'row', gap: 14},
    Action('💸', 'Pay'),
    Action('↗', 'Send'),
    Action('↘', 'Receive'),
    Action('⋯', 'More'),
  )
}

function Action(icon: string, label: string) {
  return Pressable({
    flex: 1, gap: 8, alignItems: 'center',
    onTap: () => {
      lumen.haptics('light')
      lumen.bottomSheet({
        height: 'small',
        content: View({padding: 24, gap: 8, alignItems: 'center'},
          Text({fontSize: 32}, icon),
          Text({fontSize: 18, fontWeight: '700', color: '#0F0F12'}, label),
          Text({fontSize: 13, color: '#6B6B73'}, 'Action not implemented in demo'),
        ),
      })
    },
  },
    View({
      width: 52, height: 52, borderRadius: 26,
      backgroundColor: '#FFFFFF',
      borderColor: '#E5E5EA', borderWidth: 1,
      justifyContent: 'center', alignItems: 'center',
    },
      Text({fontSize: 22, color: '#0F0F12'}, icon),
    ),
    Text({fontSize: 11, color: '#6B6B73', fontWeight: '600'}, label),
  )
}

// ─────────── filter chips ───────────

function FilterChips() {
  return View({flexDirection: 'row', gap: 8, paddingTop: 4},
    Chip('all', 'All'),
    Chip('income', 'Income'),
    Chip('spending', 'Spending'),
  )
}

function Chip(value: 'all' | 'income' | 'spending', label: string) {
  return Pressable({
    paddingTop: 8, paddingBottom: 8,
    paddingLeft: 14, paddingRight: 14,
    borderRadius: 14,
    backgroundColor: () => filter.value === value ? '#0F0F12' : '#FFFFFF',
    borderColor: '#E5E5EA', borderWidth: 1,
    onTap: () => {
      filter.value = value
      lumen.haptics('light')
    },
  },
    Text({fontSize: 12, fontWeight: '700',
          color: () => filter.value === value ? '#FFFFFF' : '#6B6B73'},
      label),
  )
}

// ─────────── transactions ───────────

function TransactionsHeader() {
  return View({flexDirection: 'row', alignItems: 'center', paddingTop: 4},
    Text({fontSize: 11, fontWeight: '700', color: '#6B6B73', flex: 1},
      'RECENT ACTIVITY'),
    Text({fontSize: 11, fontWeight: '600', color: '#007AFF'},
      'See all →'),
  )
}

function TransactionRow(t: Tx) {
  return Pressable({
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 12, paddingBottom: 12,
    paddingLeft: 4, paddingRight: 4,
    gap: 12,
    onTap: () => openTxSheet(t),
    key: String(t.id),
  },
    View({
      width: 42, height: 42, borderRadius: 21,
      backgroundColor: '#FFFFFF',
      borderColor: '#E5E5EA', borderWidth: 1,
      justifyContent: 'center', alignItems: 'center',
    },
      Text({fontSize: 20}, t.icon),
    ),
    View({flex: 1, gap: 2},
      Text({fontSize: 14, fontWeight: '600', color: '#0F0F12'}, t.name),
      Text({fontSize: 11, color: '#6B6B73'}, `${t.category} · ${t.whenLabel}`),
    ),
    Text({fontSize: 14, fontWeight: '700',
          color: amountColor(t.amountCents)},
      fmtCents(t.amountCents, t.amountCents > 0)),
  )
}

function openTxSheet(t: Tx) {
  lumen.haptics('soft')
  lumen.bottomSheet({
    height: 'medium',
    content: View({padding: 24, gap: 18},
      View({flexDirection: 'row', alignItems: 'center', gap: 14},
        View({
          width: 56, height: 56, borderRadius: 28,
          backgroundColor: '#FFFFFF',
          borderColor: '#E5E5EA', borderWidth: 1,
          justifyContent: 'center', alignItems: 'center',
        },
          Text({fontSize: 26}, t.icon),
        ),
        View({flex: 1, gap: 4},
          Text({fontSize: 18, fontWeight: '700', color: '#0F0F12'}, t.name),
          Text({fontSize: 12, color: '#6B6B73'}, t.category),
        ),
      ),
      Text({fontSize: 32, fontWeight: '700',
            color: amountColor(t.amountCents)},
        fmtCents(t.amountCents, t.amountCents > 0)),
      View({gap: 8},
        DetailRow('Date', t.whenLabel),
        DetailRow('Status', 'Completed'),
        DetailRow('Reference', `TX-${1000 + t.id}`),
      ),
      View({flexDirection: 'row', gap: 8, paddingTop: 8},
        PrimaryButton('Repeat'),
        SecondaryButton('Hide'),
      ),
    ),
  })
}

function DetailRow(label: string, value: string) {
  return View({flexDirection: 'row', justifyContent: 'space-between'},
    Text({fontSize: 13, color: '#6B6B73'}, label),
    Text({fontSize: 13, color: '#0F0F12', fontWeight: '600'}, value),
  )
}

function PrimaryButton(label: string) {
  return Pressable({
    flex: 1, height: 44,
    backgroundColor: '#007AFF', borderRadius: 12,
    justifyContent: 'center', alignItems: 'center',
    onTap: () => lumen.haptics('light'),
  },
    Text({fontSize: 13, fontWeight: '600', color: '#FFFFFF'}, label),
  )
}

function SecondaryButton(label: string) {
  return Pressable({
    flex: 1, height: 44,
    backgroundColor: '#FFFFFF',
    borderColor: '#E5E5EA', borderWidth: 1,
    borderRadius: 12,
    justifyContent: 'center', alignItems: 'center',
    onTap: () => lumen.haptics('light'),
  },
    Text({fontSize: 13, fontWeight: '600', color: '#0F0F12'}, label),
  )
}

// ─────────── add demo tx ───────────

const demoSpendItems: Omit<Tx, 'id' | 'whenLabel'>[] = [
  {icon: '🍕', name: 'Joe\'s Pizza',  category: 'Restaurants', amountCents: -2475},
  {icon: '🎵', name: 'Spotify',       category: 'Subscriptions', amountCents: -999},
  {icon: '📚', name: 'Bookshop',      category: 'Books',         amountCents: -3299},
  {icon: '🚕', name: 'Taxi ride',     category: 'Transit',       amountCents: -1850},
]

function AddDemoButton() {
  return View({flexDirection: 'row', gap: 8, paddingTop: 12},
    Pressable({
      flex: 1, height: 44,
      backgroundColor: '#0A8754', borderRadius: 12,
      justifyContent: 'center', alignItems: 'center',
      onTap: () => {
        const t: Tx = {
          id: nextID++,
          icon: '💰',
          name: 'Refund',
          category: 'Income',
          amountCents: Math.floor(500 + Math.random() * 5000),
          whenLabel: 'Just now',
        }
        transactions.value = [t, ...transactions.value]
        lumen.haptics('success')
      },
    },
      Text({fontSize: 13, fontWeight: '700', color: '#FFFFFF'},
        '+ Add income'),
    ),
    Pressable({
      flex: 1, height: 44,
      backgroundColor: '#FFFFFF',
      borderColor: '#E5E5EA', borderWidth: 1,
      borderRadius: 12,
      justifyContent: 'center', alignItems: 'center',
      onTap: () => {
        const proto = demoSpendItems[Math.floor(Math.random() * demoSpendItems.length)]
        const t: Tx = {...proto, id: nextID++, whenLabel: 'Just now'}
        transactions.value = [t, ...transactions.value]
        lumen.haptics('soft')
      },
    },
      Text({fontSize: 13, fontWeight: '700', color: '#0F0F12'},
        '+ Add spend'),
    ),
  )
}

mount(App)
