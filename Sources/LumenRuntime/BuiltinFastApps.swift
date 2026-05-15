import Foundation

/// Source of code for built-in lumen:// fast-apps (history, settings, ...).
/// JS is inlined as a string — no need for a bundling pipeline.
/// Once there are many built-ins — will move to resource files.
enum BuiltinFastApps {
    static func script(for host: String) -> String? {
        switch host {
        case "home":    return homeJS
        case "history": return historyJS
        case "library": return libraryStubJS
        default: return nil
        }
    }

    static func displayName(for host: String) -> String? {
        switch host {
        case "home":    return "Home"
        case "history": return "History"
        case "library": return "Library"
        default: return nil
        }
    }

    // MARK: - home

    private static let homeJS: String = #"""
// lumen://home — start page. Dark palette matching the shell,
// greeting + AI card + pinned grid + recent (from lumen.history).

function hostOf(u) {
  const m = /^[a-z]+:\/\/([^\/]+)/i.exec(u || '')
  return m ? m[1] : (u || '')
}

function timeAgo(ms) {
  const diff = Math.max(0, Date.now() - ms) / 1000
  if (diff < 60)    return 'just now'
  if (diff < 3600)  return Math.floor(diff / 60) + 'm ago'
  if (diff < 86400) return Math.floor(diff / 3600) + 'h ago'
  return Math.floor(diff / 86400) + 'd ago'
}

function greetingByTime() {
  const h = new Date().getHours()
  if (h < 5)  return 'Late night'
  if (h < 12) return 'Good morning'
  if (h < 18) return 'Good afternoon'
  return 'Good evening'
}

const pinned = [
  {name: 'GitHub',  ico: 'G', bg: '#27272F', fg: '#FFFFFF', url: 'https://github.com'},
  {name: 'Figma',   ico: 'F', bg: '#A259FF', fg: '#FFFFFF', url: 'https://figma.com'},
  {name: 'HN',      ico: 'Y', bg: '#FF6600', fg: '#FFFFFF', url: 'https://news.ycombinator.com'},
  {name: 'Notion',  ico: 'N', bg: '#FFFFFF', fg: '#000000', url: 'https://notion.so'},
  {name: 'X',       ico: '𝕏', bg: '#000000', fg: '#FFFFFF', url: 'https://x.com'},
  {name: 'YouTube', ico: '▶', bg: '#FF0000', fg: '#FFFFFF', url: 'https://youtube.com'},
  {name: 'arXiv',   ico: 'a', bg: '#B33B26', fg: '#FFFFFF', url: 'https://arxiv.org'},
  {name: 'History', ico: '⏱', bg: '#2A2A35', fg: '#ECECEE', url: 'lumen://history'},
]

// Lumen platform showcase — each chip opens the corresponding Lab.
// Replace 127.0.0.1 with your machine's LAN IP when testing from a physical
// device (e.g. http://192.168.x.x:80XX). Default works for the simulator.
const labs = [
  {name: 'Tabs',     ico: '⊞', bg: '#3B82F6', fg: '#FFFFFF',
   url: 'http://127.0.0.1:8080',
   desc: 'multi-tab API'},
  {name: 'Drag',     ico: '✥', bg: '#F59E0B', fg: '#0B0B0F',
   url: 'http://127.0.0.1:8082',
   desc: 'gestures + spring'},
  {name: 'Glass',    ico: '◐', bg: '#A78BFA', fg: '#0B0B0F',
   url: 'http://127.0.0.1:8083',
   desc: 'iOS 26 Liquid Glass'},
  {name: 'Scroll',   ico: '⇅', bg: '#10B981', fg: '#0B0B0F',
   url: 'http://127.0.0.1:8084',
   desc: 'scroll + safe-area'},
  {name: 'Inputs',   ico: 'A|', bg: '#EC4899', fg: '#FFFFFF',
   url: 'http://127.0.0.1:8085',
   desc: 'TextInput'},
  {name: 'Sheets',   ico: '▭', bg: '#06B6D4', fg: '#0B0B0F',
   url: 'http://127.0.0.1:8086',
   desc: 'bottomSheet'},
  {name: 'Maps',     ico: '◉', bg: '#22C55E', fg: '#0B0B0F',
   url: 'http://127.0.0.1:8088',
   desc: 'native MKMapView'},
  {name: 'Platform', ico: '⚡', bg: '#B69CFF', fg: '#0B0B0F',
   url: 'http://127.0.0.1:8089',
   desc: 'clipboard · share · ws · keychain · picker'},
]

const recent = signal(lumen.history.list().slice(0, 4))
lumen.history.subscribe(function () {
  recent.value = lumen.history.list().slice(0, 4)
})

function App() {
  return View({flex: 1, backgroundColor: '#0B0B0F'},
    ScrollView({
      flex: 1,
      paddingTop: lumen.safeArea.top + 28,
      paddingBottom: lumen.safeArea.bottom + 24,
      paddingLeft: 22, paddingRight: 22,
      gap: 26,
    },
      Greeting(),
      AICard(),
      PinnedSection(),
      LabsSection(),
      RecentSection(),
    ),
  )
}

function Greeting() {
  return View({gap: 6},
    Text({fontSize: 13, color: '#9A9AA5', fontWeight: '500'},
      greetingByTime()),
    Text({fontSize: 30, fontWeight: '600', color: '#ECECEE', lineHeight: 36},
      "What's on your mind?"),
  )
}

function AICard() {
  return Pressable({
    onTap: () => lumen.haptics('light'),
    flexDirection: 'row',
    gap: 14,
    padding: 18,
    backgroundColor: '#FFFFFF0D',
    borderColor: '#FFFFFF24', borderWidth: 0.5,
    borderRadius: 18,
  },
    View({
      width: 36, height: 36, borderRadius: 10,
      backgroundColor: '#B69CFF',
      justifyContent: 'center', alignItems: 'center',
    },
      Text({fontSize: 16, color: '#0B0B0F', fontWeight: '700'}, '✦'),
    ),
    View({flex: 1, gap: 4},
      Text({fontSize: 14, fontWeight: '600', color: '#ECECEE'},
        'Continue where you left off'),
      Text({fontSize: 12, color: '#9A9AA5', lineHeight: 17,
            numberOfLines: 2},
        'Tap ✦ in the bar below to ask about anything on screen, or start a fresh conversation.'),
    ),
  )
}

function PinnedSection() {
  return View({gap: 12},
    SectionHeader('PINNED'),
    View({flexDirection: 'row', gap: 8},
      Pin(pinned[0]), Pin(pinned[1]), Pin(pinned[2]), Pin(pinned[3]),
    ),
    View({flexDirection: 'row', gap: 8},
      Pin(pinned[4]), Pin(pinned[5]), Pin(pinned[6]), Pin(pinned[7]),
    ),
  )
}

function Pin(p) {
  return Pressable({
    flex: 1,
    gap: 7,
    alignItems: 'center',
    onTap: () => {
      lumen.haptics('light')
      lumen.tabs.navigate(p.url)
    },
  },
    View({
      width: 52, height: 52, borderRadius: 14,
      backgroundColor: p.bg,
      borderColor: '#FFFFFF12', borderWidth: 0.5,
      justifyContent: 'center', alignItems: 'center',
    },
      Text({fontSize: 18, fontWeight: '700', color: p.fg}, p.ico),
    ),
    Text({fontSize: 11, color: '#9A9AA5'}, p.name),
  )
}

function LabsSection() {
  return View({gap: 12},
    View({flexDirection: 'row', alignItems: 'flex-end', gap: 8},
      Text({fontSize: 11, fontWeight: '700', color: '#9A9AA5', flex: 1},
        'LUMEN'),
      Text({fontSize: 10, color: '#6B6B76'},
        'live demos · tap to open'),
    ),
    View({flexDirection: 'row', gap: 10},
      LabCell(labs[0]), LabCell(labs[1]), LabCell(labs[2]), LabCell(labs[3]),
    ),
    View({flexDirection: 'row', gap: 10},
      LabCell(labs[4]), LabCell(labs[5]), LabCell(labs[6]), LabCell(labs[7]),
    ),
  )
}

function LabCell(l) {
  return Pressable({
    flex: 1,
    gap: 6,
    alignItems: 'center',
    onTap: () => {
      lumen.haptics('light')
      lumen.tabs.navigate(l.url)
    },
  },
    View({
      width: 52, height: 52, borderRadius: 14,
      backgroundColor: l.bg,
      borderColor: '#FFFFFF14', borderWidth: 0.5,
      justifyContent: 'center', alignItems: 'center',
    },
      Text({fontSize: 17, fontWeight: '700', color: l.fg}, l.ico),
    ),
    Text({fontSize: 10.5, color: '#ECECEE', fontWeight: '500'}, l.name),
  )
}

function RecentSection() {
  return View({gap: 12},
    View({flexDirection: 'row', alignItems: 'center'},
      Text({fontSize: 11, fontWeight: '600', color: '#9A9AA5', flex: 1},
        'RECENT'),
      Pressable({
        onTap: () => lumen.tabs.navigate('lumen://history'),
      },
        Text({fontSize: 11, color: '#7FB8FF', fontWeight: '600'},
          'All →'),
      ),
    ),
    Slot({gap: 0}, function () {
      const list = recent.value
      if (list.length === 0) {
        return [Text({fontSize: 12, color: '#6B6B76', paddingTop: 4},
                     'Nothing visited yet — pick a pin above.')]
      }
      return list.map(RecentRow)
    }),
  )
}

function RecentRow(e) {
  const host = hostOf(e.url)
  const display = e.title && e.title.length > 0 ? e.title : host
  return Pressable({
    key: e.id,
    onTap: () => {
      lumen.haptics('light')
      lumen.tabs.navigate(e.url)
    },
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 10, paddingBottom: 10,
    gap: 12,
  },
    View({
      width: 32, height: 32, borderRadius: 8,
      backgroundColor: '#FFFFFF0D',
      borderColor: '#FFFFFF14', borderWidth: 0.5,
      justifyContent: 'center', alignItems: 'center',
    },
      Text({fontSize: 11, fontWeight: '700', color: '#ECECEE'},
        (host.charAt(0) || '?').toUpperCase()),
    ),
    View({flex: 1, gap: 2},
      Text({fontSize: 13.5, fontWeight: '500', color: '#ECECEE',
            numberOfLines: 1}, display),
      Text({fontSize: 11, color: '#9A9AA5', numberOfLines: 1}, host),
    ),
    Text({fontSize: 11, color: '#6B6B76'}, timeAgo(e.at)),
  )
}

function SectionHeader(title) {
  return Text({fontSize: 11, fontWeight: '700', color: '#9A9AA5'}, title)
}

mount(App)
"""#

    // MARK: - library (stub)

    private static let libraryStubJS: String = #"""
function App() {
  return View({flex: 1, backgroundColor: '#F2EDE2',
               paddingTop: lumen.safeArea.top + 40,
               paddingLeft: 24, paddingRight: 24,
               gap: 12, alignItems: 'center'},
    Text({fontSize: 28, fontWeight: '500', color: '#1A1612',
          fontFamily: 'Iowan Old Style'}, 'Library'),
    Text({fontSize: 12, color: '#8A8275'}, 'Tab switcher — coming next.'),
  )
}
mount(App)
"""#

    // MARK: - history

    private static let historyJS: String = #"""
// lumen://history — minimal visit history.
// Pure JS (no TS): fed directly to JSC without transpilation.

const items = signal(lumen.history.list())

// Push channel: HistoryStore (Swift) calls our callback after any mutation,
// including a visit recorded in another tab via addressBar. items is a signal,
// Vapor effects re-render only the affected slots.
lumen.history.subscribe(function () {
  items.value = lumen.history.list()
})

function timeAgo(ms) {
  const diff = Math.max(0, Date.now() - ms) / 1000
  if (diff < 60)    return 'just now'
  if (diff < 3600)  return Math.floor(diff / 60) + 'm ago'
  if (diff < 86400) return Math.floor(diff / 3600) + 'h ago'
  return Math.floor(diff / 86400) + 'd ago'
}

function hostOf(u) {
  // JSC has no URL — parse manually.
  const m = /^[a-z]+:\/\/([^\/]+)/i.exec(u || '')
  return m ? m[1] : (u || '')
}

function App() {
  return View({flex: 1, backgroundColor: '#F2F2F7'},
    ScrollView({
      flex: 1,
      paddingTop: lumen.safeArea.top + 8,
      paddingBottom: lumen.safeArea.bottom + 16,
      paddingLeft: 16,
      paddingRight: 16,
      gap: 8,
    },
      Header(),
      Slot({gap: 8}, () => items.value.map(Row)),
      EmptyState(),
    ),
  )
}

function Header() {
  return View({
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 8,
    paddingBottom: 8,
    gap: 12,
  },
    Text({fontSize: 28, fontWeight: '700', color: '#0F0F12', flex: 1}, 'History'),
    Text({fontSize: 12, color: '#6B6B73'},
      () => items.value.length + (items.value.length === 1 ? ' entry' : ' entries')),
    Pressable({
      paddingTop: 8, paddingBottom: 8, paddingLeft: 12, paddingRight: 12,
      borderRadius: 10,
      backgroundColor: '#FFFFFF',
      borderColor: '#E5E5EA', borderWidth: 1,
      onTap: () => {
        if (items.value.length === 0) return
        lumen.history.clear()
        lumen.haptics('warning')
      },
    },
      Text({fontSize: 12, fontWeight: '600', color: '#FF3B30'}, 'Clear'),
    ),
  )
}

function EmptyState() {
  return View({
    opacity: () => items.value.length === 0 ? 1 : 0,
    paddingTop: 60,
    alignItems: 'center',
    gap: 4,
  },
    Text({fontSize: 32}, '🕓'),
    Text({fontSize: 14, color: '#6B6B73'}, 'No history yet'),
    Text({fontSize: 12, color: '#9A9AA0'},
      'Visit a page in the address bar to see it here.'),
  )
}

function Row(e) {
  const h = hostOf(e.url)
  const display = e.title && e.title.length > 0 ? e.title : h
  return Pressable({
    key: e.id,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingTop: 12, paddingBottom: 12,
    paddingLeft: 14, paddingRight: 8,
    backgroundColor: '#FFFFFF',
    borderColor: '#E5E5EA', borderWidth: 1,
    borderRadius: 12,
    onTap: () => {
      lumen.haptics('light')
      lumen.tabs.open(e.url)
    },
  },
    View({
      width: 32, height: 32, borderRadius: 8,
      backgroundColor: '#F2F2F7',
      borderColor: '#E5E5EA', borderWidth: 1,
      justifyContent: 'center', alignItems: 'center',
    },
      Text({fontSize: 13, fontWeight: '700', color: '#0F0F12'},
        (h.charAt(0) || '?').toUpperCase()),
    ),
    View({flex: 1, gap: 2},
      Text({fontSize: 14, fontWeight: '600', color: '#0F0F12'}, display),
      Text({fontSize: 11, color: '#6B6B73'}, h + ' · ' + timeAgo(e.at)),
    ),
    Pressable({
      width: 32, height: 32, borderRadius: 16,
      justifyContent: 'center', alignItems: 'center',
      onTap: () => {
        lumen.history.remove(e.id)
        lumen.haptics('light')
      },
    },
      Text({fontSize: 16, color: '#9A9AA0'}, '×'),
    ),
  )
}

mount(App)
"""#
}
