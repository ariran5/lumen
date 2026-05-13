// TabsLab — упражнение lumen.tabs.* API. Видно собственную табу (own),
// активную табу (current), список всех. Кнопки открывают новые табы
// разных типов + закрывают по id.

const refreshCount = signal(0)
const refresh = () => { refreshCount.value++ }

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    Header(),
    ScrollView({
      flex: 1, padding: 16, gap: 14,
      paddingBottom: 16 + lumen.safeArea.bottom,
    },
      OwnPanel(),
      ActionsPanel(),
      ListPanel(),
    ),
  )
}

function Header() {
  return View({
    paddingTop: 14, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
    backgroundColor: '#15151A', gap: 4,
  },
    Text({fontSize: 16, fontWeight: '700', color: '#FFFFFF'}, 'Tabs Lab'),
    Text({fontSize: 11, color: '#9CA3AF'},
      `lumen.tabs.* · ${lumen.tabs.list().length} tab(s) open · refresh #${refreshCount.value}`),
  )
}

function OwnPanel() {
  const own = lumen.tabs.own()
  const cur = lumen.tabs.current()
  return Panel('Identity',
    Row('own.id', own ? own.id.slice(0, 8) + '…' : '—'),
    Row('own.title', own?.title || '—'),
    Row('current.id', cur ? cur.id.slice(0, 8) + '…' : '—'),
    Row('isActive', String(own?.isActive ?? false)),
  )
}

function ActionsPanel() {
  return Panel('Actions',
    Button('Open HN (fast-app)', () => {
      lumen.tabs.open('http://localhost:8080')
      refresh()
    }),
    Button('Open ycombinator (web)', () => {
      lumen.tabs.open('https://news.ycombinator.com')
      refresh()
    }),
    Button('Open empty new tab', () => {
      lumen.tabs.open()
      refresh()
    }),
    Button('Close own tab', () => {
      lumen.tabs.close()  // no id = own
    }, '#7F1D1D'),
  )
}

function ListPanel() {
  return Panel('All tabs',
    ...lumen.tabs.list().map(TabRow),
  )
}

function TabRow(t: TabInfo) {
  return View({
    flexDirection: 'row',
    paddingTop: 10, paddingBottom: 10, paddingLeft: 12, paddingRight: 12,
    borderRadius: 8,
    backgroundColor: t.isActive ? '#1E1E28' : '#15151A',
    borderColor: '#27272F',
    borderWidth: 1,
    gap: 10,
    alignItems: 'center',
  },
    View({flex: 1, gap: 2},
      Text({fontSize: 13, fontWeight: '600',
            color: t.isActive ? '#A5B4FC' : '#FFFFFF'},
        t.title),
      Text({fontSize: 10, color: '#6B7280'},
        t.url || '(no url)'),
    ),
    Pressable({
      paddingTop: 6, paddingBottom: 6, paddingLeft: 10, paddingRight: 10,
      backgroundColor: '#27272F', borderRadius: 6,
      onTap: () => {
        lumen.tabs.switch(t.id)
      },
    },
      Text({fontSize: 11, color: '#FFFFFF'}, 'switch'),
    ),
    Pressable({
      paddingTop: 6, paddingBottom: 6, paddingLeft: 10, paddingRight: 10,
      backgroundColor: '#7F1D1D', borderRadius: 6,
      onTap: () => {
        lumen.tabs.close(t.id)
        refresh()
      },
    },
      Text({fontSize: 11, color: '#FFFFFF'}, '✕'),
    ),
  )
}

function Panel(title: string, ...rows: RenderNode[]) {
  return View({
    backgroundColor: '#15151A',
    borderRadius: 12,
    paddingTop: 12, paddingBottom: 12, paddingLeft: 14, paddingRight: 14,
    gap: 8,
  },
    Text({fontSize: 12, fontWeight: '700', color: '#A5B4FC'},
      title.toUpperCase()),
    ...rows,
  )
}

function Row(label: string, value: string) {
  return View({flexDirection: 'row', gap: 8},
    Text({fontSize: 12, color: '#9CA3AF', width: 90}, label),
    Text({fontSize: 12, fontWeight: '600', color: '#FFFFFF', flex: 1}, value),
  )
}

function Button(label: string, onTap: () => void, color: Color = '#1E40AF') {
  return Pressable({
    height: 40,
    backgroundColor: color,
    borderRadius: 8,
    justifyContent: 'center', alignItems: 'center',
    onTap,
  },
    Text({fontSize: 13, fontWeight: '600', color: '#FFFFFF'}, label),
  )
}

mount(App)
