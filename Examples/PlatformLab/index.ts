// PlatformLab — touch every Tier 1 platform API.
//
// Clipboard / Linking / Share / ActionSheet / SecureStorage / ImagePicker / WebSocket.
// Каждая карточка self-contained: title → status (большой, прямо под заголовком)
// → action(s). Нет глобального event-feed'а сверху — всё видно в самой карточке.

const clipboardSeen = signal<string>('—')
const secretValue = signal<string>('—')
const pickedAsset = signal<PickedAsset | null>(null)
const wsStatus = signal<string>('not connected')
const wsLog = signal<string[]>([])
const wsConnected = signal(false)
const linkingResult = signal<string>('—')
const shareResult = signal<string>('—')
const actionResult = signal<string>('—')
const bioResult = signal<string>('—')
const statusBarTheme = signal<'auto' | 'dark' | 'light'>('auto')
const statusBarHidden = signal(false)
const refreshCount = signal(0)
const isRefreshing = signal(false)
const notifStatus = signal<string>('—')
const lastTapped = signal<string>('—')
const incomingURL = signal<string>('—')
let wsHandle: WebSocketHandle | null = null

// Подписки на push-каналы native'а. Регистрируем один раз — handle'ы живут
// до конца жизни фастаппа.
lumen.notifications.onTap.subscribe((id) => {
  lastTapped.value = id
  lumen.haptics('success')
})
lumen.linking.onIncoming.subscribe((url) => {
  incomingURL.value = url
  lumen.haptics('light')
})

const COLORS = {
  bg: '#0B0B0F',
  surface: '#15151B',
  surfaceHi: '#1B1B22',
  border: '#26262E',
  text: '#ECECEE',
  textDim: '#8A8A93',
  textMuted: '#6B6B76',
  accent: '#B69CFF',
  ok: '#7FE0B0',
  danger: '#FF6F77',
  info: '#7FB8FF',
}

function App() {
  return View({flex: 1, backgroundColor: COLORS.bg, paddingTop: lumen.safeArea.top},
    Header(),
    ScrollView({
      flex: 1, padding: 14, gap: 12,
      onRefresh: handleRefresh,
    },
      RefreshCard(),
      BiometricsCard(),
      StatusBarCard(),
      NotificationsCard(),
      DeepLinkCard(),
      AppStateCard(),
      ThemeCard(),
      NetworkCard(),
      ClipboardCard(),
      LinkingCard(),
      ShareCard(),
      ActionSheetCard(),
      SecureStorageCard(),
      ImagePickerCard(),
      WebSocketCard(),
      View({height: lumen.safeArea.bottom + 16}),
    ),
  )
}

function Header() {
  return View({
    paddingTop: 8, paddingBottom: 14, paddingLeft: 16, paddingRight: 16,
    backgroundColor: COLORS.surface,
    borderColor: COLORS.border, borderWidth: 1,
    gap: 4,
  },
    Text({fontSize: 17, fontWeight: '700', color: COLORS.text}, 'Platform Lab'),
    Text({fontSize: 11, color: COLORS.textMuted}, 'Tap a card — result shows below its title.'),
  )
}

// ── card chrome ───────────────────────────────────────────────────────
//
// Layout: title row → status block (big colored) → action rows.
// Status block — единственное место где смотреть результат.

function Card(title: string, statusThunk: () => string, ...rows: Child[]) {
  return View({
    backgroundColor: COLORS.surface,
    borderColor: COLORS.border, borderWidth: 1,
    borderRadius: 14, padding: 14, gap: 12,
  },
    Text({fontSize: 13, fontWeight: '600', color: COLORS.textDim}, title),
    StatusLine(statusThunk),
    ...rows,
  )
}

function StatusLine(thunk: () => string) {
  return Text({
    fontSize: 16, fontWeight: '500', color: COLORS.text,
    fontFamily: 'Menlo',
  }, thunk)
}

function PrimaryButton(label: string | Thunk<string>, onTap: () => void, color: string = COLORS.accent) {
  return Pressable({
    backgroundColor: color,
    borderRadius: 10,
    paddingTop: 10, paddingBottom: 10, paddingLeft: 14, paddingRight: 14,
    alignItems: 'center',
    onTap,
  },
    Text({fontSize: 13, fontWeight: '600', color: '#0B0B0F'}, label as Thunk<string>),
  )
}

function SecondaryButton(label: string | Thunk<string>, onTap: () => void) {
  return Pressable({
    backgroundColor: COLORS.surfaceHi,
    borderColor: COLORS.border, borderWidth: 1,
    borderRadius: 10,
    paddingTop: 10, paddingBottom: 10, paddingLeft: 14, paddingRight: 14,
    alignItems: 'center',
    onTap,
  },
    Text({fontSize: 13, fontWeight: '500', color: COLORS.text}, label as Thunk<string>),
  )
}

function Row(...children: Child[]) {
  return View({flexDirection: 'row', gap: 8}, ...children)
}

// ── Заход B / Pull-to-refresh ─────────────────────────────────────────
//
// onRefresh приходит когда юзер дёрнул scroll вниз; нативный спиннер
// показывается пока `refreshing` true. Имитируем fetch — 1.5s setTimeout.

function handleRefresh(): Promise<void> {
  isRefreshing.value = true
  return new Promise((resolve) => {
    setTimeout(() => {
      refreshCount.value = refreshCount.value + 1
      isRefreshing.value = false
      resolve()
    }, 1500)
  })
}

function RefreshCard() {
  return Card('PULL-TO-REFRESH',
    () => `refreshed ${refreshCount.value}× · ${isRefreshing.value ? 'fetching…' : 'idle'}`,
    Text({fontSize: 11, color: COLORS.textMuted},
         'Потяни scroll вниз — спиннер живёт пока Promise не resolve\'нется.'),
  )
}

// ── Заход B / Biometrics ──────────────────────────────────────────────

function BiometricsCard() {
  return Card('BIOMETRICS',
    () => bioResult.value,
    Text({fontSize: 11, color: COLORS.textMuted},
         () => `available: ${lumen.biometrics.available()}`),
    Row(
      View({flex: 1},
        PrimaryButton('Authenticate', async () => {
          bioResult.value = 'prompting…'
          const ok = await lumen.biometrics.authenticate('Unlock platform lab')
          bioResult.value = ok ? 'authenticated ✓' : 'denied / cancelled'
          if (ok) lumen.haptics('success')
        }),
      ),
      View({flex: 1},
        SecondaryButton('Reset', () => { bioResult.value = '—' }),
      ),
    ),
  )
}

// ── Заход B / StatusBar ───────────────────────────────────────────────

function StatusBarCard() {
  return Card('STATUS BAR',
    () => `theme: ${statusBarTheme.value} · hidden: ${statusBarHidden.value}`,
    Row(
      View({flex: 1},
        SecondaryButton('auto', () => {
          statusBarTheme.value = 'auto'
          lumen.statusBar.style({theme: 'auto'})
        }),
      ),
      View({flex: 1},
        SecondaryButton('dark', () => {
          statusBarTheme.value = 'dark'
          lumen.statusBar.style({theme: 'dark'})
        }),
      ),
      View({flex: 1},
        SecondaryButton('light', () => {
          statusBarTheme.value = 'light'
          lumen.statusBar.style({theme: 'light'})
        }),
      ),
    ),
    SecondaryButton(() => statusBarHidden.value ? 'Show bar' : 'Hide bar', () => {
      const next = !statusBarHidden.value
      statusBarHidden.value = next
      lumen.statusBar.style({hidden: next})
    }),
  )
}

// ── Заход C / Notifications ───────────────────────────────────────────
//
// requestPermission → schedule в 5s → tap-listener фиксирует id.

function NotificationsCard() {
  return Card('NOTIFICATIONS',
    () => `${notifStatus.value} · last tap: ${lastTapped.value}`,
    Text({fontSize: 11, color: COLORS.textMuted},
         'Запроси permission, запланируй на 5 сек, лочь экран — придёт notification. Тап → id.'),
    Row(
      View({flex: 1},
        PrimaryButton('Request permission', async () => {
          const r = await lumen.notifications.requestPermission()
          notifStatus.value = `permission: ${r}`
        }),
      ),
      View({flex: 1},
        SecondaryButton('Schedule +5s', async () => {
          try {
            const id = await lumen.notifications.schedule({
              title: 'Lumen lab',
              body: 'Tap me to fire onTap.',
              at: Date.now() + 5000,
            })
            notifStatus.value = `scheduled: ${id.slice(0, 8)}…`
          } catch (e) {
            notifStatus.value = `schedule failed: ${String(e)}`
          }
        }),
      ),
    ),
    SecondaryButton('Cancel all', () => {
      lumen.notifications.cancelAll()
      notifStatus.value = 'cleared all'
    }),
  )
}

// ── Заход C / Deep links ──────────────────────────────────────────────
//
// Регистрируем `lumen://` в Info.plist; в Safari вбей lumen://hello —
// SwiftUI .onOpenURL ловит и пушит через NativeNotifier на JS-канал.

function DeepLinkCard() {
  return Card('DEEP LINK',
    () => `last: ${incomingURL.value}`,
    Text({fontSize: 11, color: COLORS.textMuted},
         'Открой в Safari: lumen://hello — вернёшься сюда, URL появится.'),
    Row(
      View({flex: 1},
        PrimaryButton('Self-fire lumen://demo', () => {
          const ok = lumen.linking.open('lumen://demo?from=lab')
          if (!ok) incomingURL.value = 'cannot open'
        }),
      ),
      View({flex: 1},
        SecondaryButton('Clear', () => { incomingURL.value = '—' }),
      ),
    ),
  )
}

// ── 0a. AppState (Tier 2 — reactive lifecycle) ────────────────────────
//
// Status — thunk над lumen.appState. При home/lock/return Vapor-effect
// перепишет только этот узел.

function AppStateCard() {
  return Card('APP STATE',
    () => `state: ${lumen.appState}`,
    Text({fontSize: 11, color: COLORS.textMuted},
         'Background app → выйди на home, вернись. Inactive — pull-down notification center.'),
  )
}

// ── 0b. Theme (Tier 2 — reactive appearance) ──────────────────────────

function ThemeCard() {
  return Card('SYSTEM THEME',
    () => `theme: ${lumen.appearance.theme}`,
    Text({fontSize: 11, color: COLORS.textMuted},
         'Поменяй системную тему — Settings → Display, или Control Center.'),
  )
}

// ── 0c. Network ───────────────────────────────────────────────────────

function NetworkCard() {
  return Card('NETWORK',
    () => `${lumen.network.online ? 'online' : 'offline'} · ${lumen.network.type}`,
    Text({fontSize: 11, color: COLORS.textMuted},
         'Toggle airplane / wifi off — состояние обновится в реальном времени.'),
  )
}

// ── 1. Clipboard ──────────────────────────────────────────────────────

function ClipboardCard() {
  return Card('CLIPBOARD',
    () => clipboardSeen.value,
    Row(
      View({flex: 1},
        PrimaryButton('Copy "Lumen rocks"', () => {
          lumen.clipboard.copy('Lumen rocks')
          clipboardSeen.value = 'copied: Lumen rocks'
        }),
      ),
      View({flex: 1},
        SecondaryButton('Paste', () => {
          const v = lumen.clipboard.paste()
          clipboardSeen.value = v != null ? `pasted: ${v}` : 'pasted: ∅'
        }),
      ),
    ),
  )
}

// ── 2. Linking ────────────────────────────────────────────────────────

function LinkingCard() {
  return Card('LINKING',
    () => linkingResult.value,
    Row(
      View({flex: 1},
        PrimaryButton('Open apple.com', () => {
          const ok = lumen.linking.open('https://apple.com')
          linkingResult.value = ok ? 'opened https://apple.com' : 'cannot open'
        }),
      ),
      View({flex: 1},
        SecondaryButton('Mail Apple', () => {
          const ok = lumen.linking.open('mailto:tim@apple.com?subject=Hi')
          linkingResult.value = ok ? 'opened mailto:' : 'cannot open mail'
        }),
      ),
    ),
  )
}

// ── 3. Share ──────────────────────────────────────────────────────────

function ShareCard() {
  return Card('SHARE',
    () => shareResult.value,
    PrimaryButton('Share apple.com', () => {
      shareResult.value = 'sheet open…'
      lumen.share({
        text: 'Check this out',
        url: 'https://apple.com',
        onDone: (completed, activity) => {
          shareResult.value = completed
            ? `sent via ${activity ?? 'unknown'}`
            : 'cancelled'
        },
      })
    }),
  )
}

// ── 4. ActionSheet ────────────────────────────────────────────────────

function ActionSheetCard() {
  const labels = ['Option A', 'Option B', 'Delete']
  return Card('ACTION SHEET',
    () => actionResult.value,
    PrimaryButton('Pick an option', () => {
      lumen.actionSheet({
        title: 'Choose something',
        message: 'Native UIAlertController',
        actions: [
          {label: labels[0]},
          {label: labels[1]},
          {label: labels[2], style: 'destructive'},
        ],
        onSelect: (index) => {
          actionResult.value = `picked: ${labels[index]}`
          lumen.haptics('light')
        },
        onCancel: () => { actionResult.value = 'cancelled' },
      })
    }),
  )
}

// ── 5. SecureStorage ──────────────────────────────────────────────────

function SecureStorageCard() {
  const TOKEN = 'demo-token'
  return Card('KEYCHAIN',
    () => secretValue.value,
    Row(
      View({flex: 1},
        PrimaryButton('Save random', () => {
          const v = `sk_${Math.random().toString(36).slice(2, 10)}`
          const ok = lumen.secureStorage.set(TOKEN, v)
          secretValue.value = ok ? `saved: ${v}` : 'save failed'
        }),
      ),
      View({flex: 1},
        SecondaryButton('Read', () => {
          const v = lumen.secureStorage.get(TOKEN)
          secretValue.value = v != null ? `read: ${v}` : 'read: ∅'
        }),
      ),
    ),
    SecondaryButton('Clear', () => {
      lumen.secureStorage.remove(TOKEN)
      secretValue.value = 'cleared'
    }),
  )
}

// ── 6. ImagePicker ────────────────────────────────────────────────────

function ImagePickerCard() {
  return Card('PHOTO PICKER',
    () => {
      const a = pickedAsset.value
      return a ? `picked: ${a.width}×${a.height}` : 'tap to pick'
    },
    Slot({alignItems: 'center'}, () => {
      const a = pickedAsset.value
      if (!a) return null
      return Image({
        source: a.uri,
        width: 140, height: 140, borderRadius: 12,
        contentMode: 'cover',
      })
    }),
    PrimaryButton('Pick a photo', async () => {
      const r = await lumen.imagePicker.pick({limit: 1})
      if (!r) {
        pickedAsset.value = null
        return
      }
      const asset = Array.isArray(r) ? r[0] : r
      pickedAsset.value = asset
    }),
  )
}

// ── 7. WebSocket ──────────────────────────────────────────────────────

function appendLog(line: string) {
  wsLog.value = [...wsLog.value, line].slice(-6)
}

function WebSocketCard() {
  return Card('WEBSOCKET',
    () => wsStatus.value,
    // Log block — последние 6 сообщений сверху вниз.
    View({
      backgroundColor: '#0B0B0F',
      borderColor: COLORS.border, borderWidth: 1,
      borderRadius: 8,
      paddingTop: 8, paddingBottom: 8,
      paddingLeft: 10, paddingRight: 10,
      minHeight: 80,
      gap: 3,
    },
      Slot({gap: 3}, () => {
        const lines = wsLog.value
        if (lines.length === 0) {
          return [Text({fontSize: 11, color: COLORS.textMuted, fontFamily: 'Menlo'},
                       '(no traffic yet)')]
        }
        return lines.map((line, i) =>
          Text({
            fontSize: 11, color: COLORS.textDim, fontFamily: 'Menlo',
            key: `${i}-${line.slice(0, 16)}`,
          }, line))
      }),
    ),
    Row(
      View({flex: 1},
        PrimaryButton(
          () => wsConnected.value ? 'Disconnect' : 'Connect',
          connectOrDisconnect,
        ),
      ),
      View({flex: 1},
        SecondaryButton('Send "ping"', () => {
          if (!wsHandle) {
            wsStatus.value = 'not connected — connect first'
            return
          }
          wsHandle.send('ping')
          appendLog('→ ping')
        }),
      ),
    ),
  )
}

function connectOrDisconnect() {
  if (wsHandle) {
    wsHandle.close()
    return
  }
  wsStatus.value = 'connecting…'
  wsLog.value = []
  wsHandle = lumen.ws('ws://192.168.0.107:9000', {
    onOpen: () => {
      wsStatus.value = 'connected'
      wsConnected.value = true
      appendLog('› open')
    },
    onMessage: (text) => appendLog(`← ${text}`),
    onClose: () => {
      wsStatus.value = 'disconnected'
      wsConnected.value = false
      appendLog('› closed')
      wsHandle = null
    },
    onError: (msg) => {
      wsStatus.value = `error: ${msg}`
      wsConnected.value = false
      appendLog(`✗ ${msg}`)
      wsHandle = null
    },
  })
  if (!wsHandle) {
    wsStatus.value = 'lumen.ws returned null'
  }
}

mount(App)
