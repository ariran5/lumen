// PlatformLab — touch every Tier 1 platform API.
//
// Clipboard / Linking / Share / ActionSheet / SecureStorage / ImagePicker / WebSocket.
// Each card is self-contained: title → status (large, right under the title)
// → action(s). No global event-feed at the top — everything is visible in the card itself.

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
const pickedDocs = signal<PickedDocument[]>([])
const docPreview = signal<string>('')
let wsHandle: WebSocketHandle | null = null

// Subscriptions to native push-channels. Registered once — handles live
// for the lifetime of the fastapp.
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
      DocumentPickerCard(),
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
// Status block — the only place to look for the result.

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

// ── Pass B / Pull-to-refresh ──────────────────────────────────────────
//
// onRefresh fires when the user pulls scroll down; the native spinner
// shows while `refreshing` is true. We fake a fetch — 1.5s setTimeout.

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

// ── Pass B / Biometrics ───────────────────────────────────────────────

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

// ── Pass B / StatusBar ────────────────────────────────────────────────

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

// ── Pass C / Notifications ────────────────────────────────────────────
//
// requestPermission → schedule in 5s → tap-listener records the id.

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

// ── Pass C / Deep links ───────────────────────────────────────────────
//
// Register `lumen://` in Info.plist; in Safari type lumen://hello —
// SwiftUI .onOpenURL catches it and pushes via NativeNotifier to the JS channel.

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
// Status — thunk over lumen.appState. On home/lock/return the Vapor-effect
// will rewrite only this node.

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

// ── 6b. DocumentPicker ────────────────────────────────────────────────
//
// UIDocumentPicker — pick from Files.app / iCloud Drive / Dropbox-like
// providers. `asCopy: true` — file is copied into our sandbox, we hand
// the fastapp a local file:// uri (like imagePicker). Then `fetch(uri)`
// reads the contents — URLSession supports the file:// scheme transparently.

function isImage(mime: string | undefined): boolean {
  return !!mime && mime.startsWith('image/')
}

function isTextual(mime: string | undefined, name: string): boolean {
  if (mime && (mime.startsWith('text/') ||
               mime === 'application/json' ||
               mime === 'application/xml' ||
               mime === 'application/javascript')) return true
  // Extension heuristic — UTType for md/log/ts/etc returns public.* without mime.
  const ext = name.split('.').pop()?.toLowerCase() ?? ''
  return ['md', 'txt', 'log', 'ts', 'tsx', 'js', 'jsx', 'json', 'xml',
          'yml', 'yaml', 'html', 'css', 'csv', 'srt'].includes(ext)
}

async function loadPreview(doc: PickedDocument): Promise<void> {
  docPreview.value = ''
  if (isImage(doc.mime)) return  // images render directly via Image
  if (isTextual(doc.mime, doc.name)) {
    try {
      const r = await fetch(doc.uri)
      const text = await r.text()
      docPreview.value = text.length > 800 ? text.slice(0, 800) + '\n…' : text
    } catch (e) {
      docPreview.value = `fetch failed: ${String(e)}`
    }
    return
  }
  // Binary (pdf/zip/audio/etc) — read via arrayBuffer and show
  // hex of the first 32 bytes. Proof that the bytes actually reached JS.
  try {
    const r = await fetch(doc.uri)
    const buf = await r.arrayBuffer()
    const view = new Uint8Array(buf)
    const head = Array.from(view.slice(0, 32))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join(' ')
    docPreview.value = `(binary · ${doc.mime ?? 'unknown'} · ${buf.byteLength} bytes)\nfirst 32 bytes:\n${head}`
  } catch (e) {
    docPreview.value = `arrayBuffer failed: ${String(e)}`
  }
}

function DocumentPickerCard() {
  return Card('DOCUMENTS',
    () => {
      const ds = pickedDocs.value
      if (ds.length === 0) return 'tap to pick'
      if (ds.length === 1) return `picked: ${ds[0].name} · ${ds[0].size}b`
      return `picked ${ds.length} files`
    },
    // List of picked items (compact, up to 5 rows).
    Slot({gap: 3}, () => {
      const ds = pickedDocs.value
      if (ds.length === 0) return null
      return ds.slice(0, 5).map((d, i) =>
        Text({
          fontSize: 11, color: COLORS.textDim, fontFamily: 'Menlo',
          key: `${i}-${d.name}`,
        }, `• ${d.name}  ${d.size}b  ${d.mime ?? '?'}`))
    }),
    // Preview block — fixed height, contents of the first file.
    Slot({
      backgroundColor: '#0B0B0F',
      borderColor: COLORS.border, borderWidth: 1,
      borderRadius: 8,
      padding: 10,
      minHeight: 160,
      alignItems: 'center', justifyContent: 'center',
    }, () => {
      const ds = pickedDocs.value
      if (ds.length === 0) {
        return Text({fontSize: 11, color: COLORS.textMuted}, '(no file picked)')
      }
      const first = ds[0]
      if (isImage(first.mime)) {
        return Image({
          source: first.uri,
          width: 140, height: 140, borderRadius: 8,
          contentMode: 'cover',
        })
      }
      const body = docPreview.value
      if (!body) {
        return Text({fontSize: 11, color: COLORS.textMuted}, 'loading…')
      }
      return Text({
        fontSize: 11, color: COLORS.textDim,
        fontFamily: 'Menlo',
      }, body)
    }),
    Row(
      View({flex: 1},
        PrimaryButton('Pick any file', async () => {
          const r = await lumen.documentPicker.pick()
          if (!r) { pickedDocs.value = []; docPreview.value = ''; return }
          pickedDocs.value = r
          await loadPreview(r[0])
        }),
      ),
      View({flex: 1},
        SecondaryButton('Pick multi (pdf+img)', async () => {
          const r = await lumen.documentPicker.pick({
            types: ['pdf', 'image'],
            multiple: true,
          })
          if (!r) { pickedDocs.value = []; docPreview.value = ''; return }
          pickedDocs.value = r
          await loadPreview(r[0])
        }),
      ),
    ),
  )
}

// ── 7. WebSocket ──────────────────────────────────────────────────────

function appendLog(line: string) {
  wsLog.value = [...wsLog.value, line].slice(-6)
}

function WebSocketCard() {
  return Card('WEBSOCKET',
    () => wsStatus.value,
    // Log block — last 6 messages top-to-bottom.
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
  wsHandle = lumen.ws('ws://127.0.0.1:9000', {
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
