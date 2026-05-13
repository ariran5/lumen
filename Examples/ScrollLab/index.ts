// ScrollLab — 40 карточек в ScrollView с onScroll. Sticky overlay
// (Glass-pill) сверху меняет opacity от 0 до 1 по мере скролла.

const tapped = signal<number | null>(null)
const scrollOffset = signal(0)
const contentHeight = signal(0)
const viewportHeight = signal(0)

// Auto-show FPS HUD так что видно сколько кадров и сколько занимает
// каждый render.
lumen.bench.showFPS(true)
lumen.bench.resetStats()

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    Stage(),
    StickyOverlay(),
  )
}

function Stage() {
  return View({flex: 1},
    ScrollView({
      flex: 1,
      paddingTop: 60 + lumen.safeArea.top,
      paddingBottom: 16 + lumen.safeArea.bottom,
      paddingLeft: 16,
      paddingRight: 16,
      gap: 12,
      onScroll: (e) => {
        scrollOffset.value = Math.round(e.offset)
        contentHeight.value = Math.round(e.contentHeight)
        viewportHeight.value = Math.round(e.viewportHeight)
      },
    },
      ...Array.from({length: 40}, (_, i) => Card(i)),
    ),
  )
}

// Прозрачность header'а появляется по мере прокрутки первых 80pt.
function StickyOverlay() {
  const o = Math.min(1, Math.max(0, scrollOffset.value / 80))
  const progress = (contentHeight.value > viewportHeight.value)
    ? scrollOffset.value / (contentHeight.value - viewportHeight.value)
    : 0
  const pct = Math.round(Math.min(1, Math.max(0, progress)) * 100)

  return View({
    position: 'absolute',
    top: lumen.safeArea.top + 8,
    left: 16, right: 16,
    opacity: o,
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
        tapped.value === null
          ? `${pct}% · offset ${scrollOffset.value}pt`
          : `card #${tapped.value} · ${pct}%`),
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
      `Scroll up to see the sticky pill fade in. The progress percentage and ` +
      `offset come live from native UIScrollViewDelegate via onScroll.`),
  )
}

mount(App)
