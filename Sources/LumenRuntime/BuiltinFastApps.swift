import Foundation

/// Источник кода для встроенных lumen:// fast-app'ов (history, settings, ...).
/// JS встроен прямо строкой — нет необходимости в bundling-пайплайне.
/// Когда builtin'ов станет много — переедет в файлы-ресурсы.
enum BuiltinFastApps {
    static func script(for host: String) -> String? {
        switch host {
        case "history": return historyJS
        default: return nil
        }
    }

    static func displayName(for host: String) -> String? {
        switch host {
        case "history": return "History"
        default: return nil
        }
    }

    // MARK: - history

    private static let historyJS: String = #"""
// lumen://history — минимальная история визитов.
// Pure JS (no TS): подаётся прямо в JSC без транспиляции.

const items = signal(lumen.history.list())

// Push-канал: HistoryStore (Swift) дёргает наш callback после любой мутации,
// в т.ч. от записи визита в другой табе через addressBar. items — signal,
// Vapor effect'ы перерисуют только нужные слоты.
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
  // JSC не имеет URL — парсим вручную.
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
