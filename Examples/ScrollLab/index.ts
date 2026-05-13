// ScrollLab — Vapor-style:
// - StickyOverlay: thunks для opacity и текста (per-prop effects)
// - Slot: динамический список карточек, кол-во меняется через signal,
//   mount(App) НЕ пересобирается при изменении

const tapped = signal<number | null>(null)
const scrollOffset = signal(0)
const contentHeight = signal(0)
const viewportHeight = signal(0)
const cardCount = signal(20)

lumen.bench.showFPS(true)
lumen.bench.resetStats()

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    // Scroll area: flex:1 + sticky overlay внутри (visual only)
    View({flex: 1},
      Stage(),
      StickyOverlay(),
    ),
    // AddRemoveBar — в flow ниже scroll'а. UIScrollView frame не покрывает
    // эту область, таппы по Pressable доходят через GestureRouter.
    AddRemoveBar(),
  )
}

function Stage() {
  return ScrollView({
    flex: 1,
    paddingTop: 60 + lumen.safeArea.top,
    paddingBottom: 16,
    paddingLeft: 16,
    paddingRight: 16,
    gap: 12,
    onScroll: (e) => {
      scrollOffset.value = Math.round(e.offset)
      contentHeight.value = Math.round(e.contentHeight)
      viewportHeight.value = Math.round(e.viewportHeight)
    },
  },
    Slot({flexDirection: 'column', gap: 12},
      () => Array.from({length: cardCount.value}, (_, i) => Card(i))
    ),
  )
}

function StickyOverlay() {
  return View({
    position: 'absolute',
    top: lumen.safeArea.top + 8,
    left: 16, right: 16,
    opacity: () => Math.min(1, Math.max(0, scrollOffset.value / 80)),
  },
    Glass({
      variant: 'regular',
      paddingTop: 12, paddingBottom: 12,
      paddingLeft: 18, paddingRight: 18,
      borderRadius: 22,
      flexDirection: 'row',
      alignItems: 'center',
      gap: 10,
    },
      Text({fontSize: 13, fontWeight: '700', color: '#0F0F12'},
        'Scroll Lab'),
      Text({fontSize: 11, color: '#0F0F1299', flex: 1},
        () => {
          const c = contentHeight.value
          const v = viewportHeight.value
          const o = scrollOffset.value
          const progress = (c > v) ? o / (c - v) : 0
          const pct = Math.round(Math.min(1, Math.max(0, progress)) * 100)
          const t = tapped.value
          return t === null
            ? `${pct}% · ${cardCount.value} cards`
            : `card #${t} · ${pct}%`
        }),
    ),
  )
}

function AddRemoveBar() {
  return View({
    paddingTop: 10,
    paddingBottom: 10 + lumen.safeArea.bottom,
    paddingLeft: 16, paddingRight: 16,
    flexDirection: 'row',
    gap: 8,
    backgroundColor: '#15151A',
  },
    Pressable({
      flex: 1, height: 44,
      backgroundColor: '#1E40AF', borderRadius: 22,
      justifyContent: 'center', alignItems: 'center',
      onTap: () => { cardCount.value++; lumen.haptics('light') },
    },
      Text({fontSize: 14, fontWeight: '600', color: '#FFFFFF'}, '+ Add card'),
    ),
    Pressable({
      flex: 1, height: 44,
      backgroundColor: '#7F1D1D', borderRadius: 22,
      justifyContent: 'center', alignItems: 'center',
      onTap: () => {
        if (cardCount.value > 0) {
          cardCount.value--
          lumen.haptics('light')
        }
      },
    },
      Text({fontSize: 14, fontWeight: '600', color: '#FFFFFF'}, '− Remove'),
    ),
  )
}

function Card(i: number) {
  const isAlt = i % 2 === 0
  return Pressable({
    backgroundColor: isAlt ? '#1A1A20' : '#1F1F27',
    borderColor: '#27272F',
    borderWidth: 1,
    borderRadius: 12,
    paddingTop: 16, paddingBottom: 16,
    paddingLeft: 18, paddingRight: 18,
    gap: 6,
    onTap: () => {
      tapped.value = i
      lumen.haptics('light')
    },
  },
    Text({fontSize: 13, fontWeight: '600', color: '#A5B4FC'},
      `Card ${i + 1}`),
    Text({fontSize: 12, color: '#9CA3AF', numberOfLines: 2},
      `Children-thunks: add/remove cards through a signal — only this Slot's ` +
      `subtree rebuilds. Sticky pill and card #${i + 1} unaffected.`),
  )
}

mount(App)
