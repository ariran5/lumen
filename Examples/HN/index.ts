// HN reader — Vapor-style миграция.
//
// До: VirtualList(count, render) + visitedRev hack для invalidation.
//     Каждый visited.set → mount re-run → 30 row rebuilds.
// После: ScrollView + Slot для списка, per-row opacity thunk, header
//     counter thunk. visitedRev убран — теперь visited signal,
//     row подписан только на свой бит через thunk.

const HN = 'https://hacker-news.firebaseio.com/v0'

interface Story {
  id: number
  title: string
  by: string
  score: number
  descendants: number
  url: string
  time: number
  hostname: string
}

const stories = signal<Story[]>([])
const placeholder = signal('Fetching top stories…')

// Object а не Set: Set.add мутирует in-place, signal не выстрелит.
// Запись `{...visited.value, [id]: true}` создаёт новую ссылку → fire.
function loadVisited(): {[id: string]: boolean} {
  const out: {[id: string]: boolean} = {}
  for (const k of lumen.storage.keys()) {
    if (k.indexOf('visited.') === 0) out[k.slice(8)] = true
  }
  return out
}
const visited = signal<{[id: string]: boolean}>(loadVisited())

lumen.bench.showFPS(true)

mount(App)

// ─── App tree ───────────────────────────────────────────────────

function App() {
  return View({flex: 1, backgroundColor: '#0F0F12'},
    Header(),
    // Slot — реактивный switch placeholder ↔ list. Mount-effect
    // НЕ читает stories.value в body, только thunk; mount запускается
    // ровно один раз.
    Slot({flex: 1},
      () => stories.value.length === 0 ? Placeholder() : List()
    ),
  )
}

function Header() {
  return View({
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 10, paddingRight: 16, paddingBottom: 10, paddingLeft: 16,
    gap: 10,
    backgroundColor: '#15151A',
  },
    // Per-prop thunk: только этот Text патчится когда stories.length меняется.
    Text({flex: 1, fontSize: 14, fontWeight: '600', color: '#10B981'},
      () => '✅ HMR live · ' + stories.value.length + ' stories'),
    Pressable({
      onTap: clearVisited,
      paddingTop: 5, paddingRight: 10, paddingBottom: 5, paddingLeft: 10,
      backgroundColor: '#27272F',
      borderRadius: 8,
    },
      Text({fontSize: 12, fontWeight: '600', color: '#A5B4FC'}, 'Clear visited'),
    ),
  )
}

function Placeholder() {
  return View({flex: 1, padding: 32, gap: 12},
    Text({fontSize: 28, fontWeight: '700', color: '#FFFFFF'}, 'Hacker News'),
    Text({fontSize: 14, color: '#9CA3AF'}, () => placeholder.value),
  )
}

function List() {
  return ScrollView({
    flex: 1,
    paddingBottom: lumen.safeArea.bottom,
  },
    // Slot — реактивный список. Effect срабатывает на stories.value
    // (load complete). На изменение visited не дёргается — opacity thunk
    // живёт в Row и подписывается отдельно.
    Slot({}, () => stories.value.map(Row)),
  )
}

function Row(s: Story, i: number) {
  return Pressable({
    key: String(s.id),
    onTap: () => openStory(s),
    flexDirection: 'row',
    padding: 14,
    gap: 12,
    height: 88,
    backgroundColor: i % 2 === 0 ? '#15151A' : '#1A1A20',
    // Per-row opacity thunk: подписан только на visited.value.
    // 30 rows × 1 effect = 30 patch calls per visited mutation,
    // mount/slot НЕ дёргаются.
    opacity: () => visited.value[s.id] ? 0.55 : 1,
  },
    View({width: 32, height: 32, borderRadius: 8, backgroundColor: '#27272F', padding: 4},
      s.hostname ? Image({flex: 1, contentMode: 'contain', source: faviconURL(s.hostname)}) : null,
    ),
    View({flex: 1, gap: 4, height: 60},
      Text({fontSize: 14, fontWeight: '600', color: '#FFFFFF', numberOfLines: 2, lineHeight: 18, height: 36},
        s.title),
      Text({fontSize: 11, color: '#9CA3AF', height: 16, numberOfLines: 1},
        s.score + ' · ' + s.descendants + ' comments · ' + (s.hostname || 'self') + ' · ' + timeAgo(s.time)),
    ),
  )
}

// ─── actions ───────────────────────────────────────────────────

function openStory(s: Story) {
  lumen.haptics('light')
  lumen.storage.set('visited.' + s.id, '1')
  visited.value = {...visited.value, [s.id]: true}
  lumen.router.push({
    title: s.hostname || 'Story',
    render: () => renderStoryDetail(s),
    onPop: () => lumen.haptics('soft'),
  })
}

function clearVisited() {
  lumen.haptics('light')
  lumen.storage.clear()
  visited.value = {}
}

// ─── detail / comments pages ───────────────────────────────────

function renderStoryDetail(s: Story) {
  return View({flex: 1, padding: 24, gap: 16, backgroundColor: '#0F0F12'},
    View({flexDirection: 'row', gap: 12, height: 64},
      View({width: 64, height: 64, borderRadius: 14, backgroundColor: '#27272F', padding: 8},
        s.hostname ? Image({flex: 1, contentMode: 'contain', source: faviconURL(s.hostname)}) : null,
      ),
      View({flex: 1, gap: 4, height: 64},
        Text({fontSize: 13, fontWeight: '600', color: '#FFFFFF', height: 18}, s.hostname || 'news.ycombinator.com'),
        Text({fontSize: 12, color: '#9CA3AF', height: 16}, 'by ' + s.by),
        Text({fontSize: 12, color: '#9CA3AF', height: 16}, timeAgo(s.time)),
      ),
    ),
    Text({fontSize: 22, fontWeight: '700', color: '#FFFFFF', numberOfLines: 6, lineHeight: 28, height: 170},
      s.title),
    View({flexDirection: 'row', gap: 10, height: 36},
      View({paddingTop: 8, paddingRight: 14, paddingBottom: 8, paddingLeft: 14, backgroundColor: '#27272F', borderRadius: 10, height: 34},
        Text({fontSize: 13, fontWeight: '600', color: '#FBBF24', height: 18},
          '▲ ' + s.score + ' points'),
      ),
      Pressable({
        onTap: () => {
          lumen.haptics('medium')
          lumen.router.push({title: 'Comments', render: () => renderCommentsPlaceholder(s)})
        },
        paddingTop: 8, paddingRight: 14, paddingBottom: 8, paddingLeft: 14,
        backgroundColor: '#27272F', borderRadius: 10, height: 34,
      },
        Text({fontSize: 13, fontWeight: '600', color: '#A5B4FC', height: 18},
          '💬 ' + s.descendants + ' comments'),
      ),
    ),
    Pressable({
      onTap: () => openShareSheet(s),
      paddingTop: 14, paddingRight: 18, paddingBottom: 14, paddingLeft: 18,
      backgroundColor: '#6366F1', borderRadius: 12, height: 50,
    },
      Text({fontSize: 15, fontWeight: '600', color: '#FFFFFF', textAlign: 'center', height: 22},
        'Open article'),
    ),
  )
}

function openShareSheet(s: Story) {
  lumen.haptics('success')
  lumen.bottomSheet({
    height: 'medium',
    onClose: () => lumen.haptics('soft'),
    content: View({flex: 1, padding: 24, gap: 16, backgroundColor: '#15151A'},
      Text({fontSize: 20, fontWeight: '700', color: '#FFFFFF', numberOfLines: 3, lineHeight: 26},
        s.title),
      Text({fontSize: 13, color: '#9CA3AF'},
        s.hostname || 'news.ycombinator.com'),
      Pressable({
        onTap: () => {
          lumen.haptics('light')
          lumen.alert({title: 'Opened', message: s.url || '(no url)'})
        },
        paddingTop: 14, paddingRight: 18, paddingBottom: 14, paddingLeft: 18,
        backgroundColor: '#10B981', borderRadius: 12,
      },
        Text({fontSize: 15, fontWeight: '600', color: '#FFFFFF', textAlign: 'center'},
          'Open in Safari'),
      ),
      Pressable({
        onTap: () => {
          lumen.haptics('light')
          lumen.storage.set('saved.' + s.id, JSON.stringify({title: s.title, url: s.url}))
          lumen.alert({title: 'Saved', message: 'Story сохранён в lumen.storage'})
        },
        paddingTop: 14, paddingRight: 18, paddingBottom: 14, paddingLeft: 18,
        backgroundColor: '#27272F', borderRadius: 12,
      },
        Text({fontSize: 15, fontWeight: '600', color: '#A5B4FC', textAlign: 'center'},
          'Save for later'),
      ),
    ),
  })
}

function renderCommentsPlaceholder(s: Story) {
  return View({flex: 1, padding: 24, gap: 12, backgroundColor: '#0F0F12'},
    Text({fontSize: 24, fontWeight: '700', color: '#FFFFFF', height: 32},
      s.descendants + ' comments'),
    Text({fontSize: 14, color: '#9CA3AF', numberOfLines: 6, lineHeight: 20, height: 120},
      'You navigated three levels deep through native UINavigationController — swipe from the left edge to pop back. Each page has its own JS-driven CALayer tree.'),
  )
}

// ─── helpers ───────────────────────────────────────────────────

function hostnameOf(url: string): string {
  if (!url) return ''
  const m = url.match(/^https?:\/\/([^\/]+)/)
  return m ? m[1] : ''
}

function faviconURL(host: string): string {
  if (!host) return ''
  return `https://www.google.com/s2/favicons?domain=${host}&sz=64`
}

function timeAgo(t: number): string {
  const sec = Math.max(0, Math.floor(Date.now() / 1000 - t))
  if (sec < 60) return sec + 's ago'
  if (sec < 3600) return Math.floor(sec / 60) + 'm ago'
  if (sec < 86400) return Math.floor(sec / 3600) + 'h ago'
  return Math.floor(sec / 86400) + 'd ago'
}

// ─── fetch on start ────────────────────────────────────────────

fetch(`${HN}/topstories.json`)
  .then(r => r.json())
  .then((ids: number[]) => {
    const top = ids.slice(0, 30)
    placeholder.value = 'Loading ' + top.length + ' stories…'
    return Promise.all(top.map(id =>
      fetch(`${HN}/item/${id}.json`).then(r => r.json()).catch(() => null)
    ))
  })
  .then((items: any[]) => {
    stories.value = items
      .filter(s => s && s.title)
      .map(s => ({
        id: s.id as number,
        title: (s.title as string) || '(untitled)',
        by: (s.by as string) || 'anon',
        score: (s.score as number) || 0,
        descendants: (s.descendants as number) || 0,
        url: (s.url as string) || '',
        time: (s.time as number) || 0,
        hostname: hostnameOf(s.url || ''),
      }))
    lumen.haptics('soft')
  })
  .catch((err: any) => {
    placeholder.value = 'Load failed: ' + (err && err.message ? err.message : String(err))
    lumen.haptics('error')
  })
