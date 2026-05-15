# 05 — Native APIs

Всё нативное живёт в `lumen.*`. Эти вызовы — синхронные мосты в Swift,
без message-queue. Каждый вызов <100µs.

```ts
lumen.haptics('light')
lumen.alert({ title: 'Done', message: 'Saved' })
lumen.bottomSheet({ content: View({...}) })
```

Полный namespace — в `lumen-types.d.ts`. Здесь — кратко по каждому API
с примером.

---

## haptics

```ts
type HapticStyle =
  | 'light' | 'medium' | 'heavy'
  | 'soft' | 'rigid'
  | 'success' | 'warning' | 'error'

lumen.haptics('light')
```

Под капотом — `UIFeedbackGenerator`. `'success'` / `'warning'` / `'error'` —
notification feedback (двойная вибрация). Остальное — impact.

> Используй щедро. На iOS юзеры это любят. Особенно при tap'е CTA,
> успешном submit'е формы, drag-релизе.

---

## alert

```ts
lumen.alert({
  title: 'Confirm',
  message: 'This will sign you out.',
  onOK: () => signOut(),
})
```

Стандартный `UIAlertController`. Только один button — OK. Для выбора с
двумя+ опциями — используй `actionSheet` (ниже).

---

## actionSheet

```ts
lumen.actionSheet({
  title: 'Delete this?',
  actions: [
    { label: 'Delete', style: 'destructive' },
    { label: 'Archive' },
  ],
  onSelect: (index) => {
    if (index === 0) deleteIt()
    else if (index === 1) archiveIt()
  },
  onCancel: () => {},
})
```

iOS автоматически добавит "Cancel" внизу. `index` в `onSelect` — позиция
в массиве `actions` (без Cancel).

`style` — `'default'` (normal), `'destructive'` (красная), `'cancel'`
(жирная, обычно внизу — но iOS сам добавит cancel-кнопку).

---

## bottomSheet

```ts
lumen.bottomSheet({
  height: 'medium',  // 'small' | 'medium' | 'large' | 'full'
  content: View({ flex: 1, padding: 24, gap: 12, backgroundColor: '#15151A' },
    Text({ fontSize: 24, fontWeight: '700', color: '#FFFFFF' }, 'Details'),
    Text({ fontSize: 14, color: '#9CA3AF' }, 'Some explanation.'),
    Pressable({
      onTap: () => {},
      padding: 14, backgroundColor: '#6366F1', borderRadius: 10,
    },
      Text({ color: '#FFFFFF', textAlign: 'center' }, 'Got it'),
    ),
  ),
  onClose: () => console.log('sheet dismissed'),
})
```

Под капотом — `UISheetPresentationController`. Контент рендерится через
nested Renderer. Swipe-to-dismiss работает (system).

**Важно:** контент рендерится **один раз** на первый валидный bounds.
Не пытайся ре-рендерить sheet через signal — bottom-sheet не задизайнен
под динамический контент по detent. Если меняется состояние внутри sheet —
используй signal/Slot внутри `content` для частичных обновлений.

> Halo + threshold-snap у `.large` detent на iOS 26 — это поведение
> самой iOS, не Lumen. Воспроизводится в чистом UIKit.

---

## storage / secureStorage

```ts
// Обычное key-value (sandbox'ed по origin, под капотом UserDefaults)
lumen.storage.set('theme', 'dark')
lumen.storage.get('theme')         // 'dark' | undefined
lumen.storage.remove('theme')
lumen.storage.keys()                // ['theme', 'username', ...]
lumen.storage.clear()

// Keychain — для секретов
lumen.secureStorage.set('access_token', 'abc123')
lumen.secureStorage.get('access_token')
lumen.secureStorage.remove('access_token')
```

Оба — sandboxed: один fast-app не видит данные другого. Origin =
scheme+host+port.

`storage` синхронный (UserDefaults), `secureStorage` синхронный (Keychain).
Не нужно `await`.

---

## clipboard

```ts
lumen.clipboard.copy('hello')
lumen.clipboard.paste()  // 'hello' | null
lumen.clipboard.has()    // true если есть строковый контент
```

`UIPasteboard.general`. iOS показывает "Pasted from <app>" — это поведение
системы, не Lumen.

---

## linking — deep links

### Открыть URL

```ts
lumen.linking.open('https://example.com')
lumen.linking.open('mailto:user@example.com')
lumen.linking.open('tel:+15551234567')
lumen.linking.open('instagram://user?username=jack')

if (lumen.linking.canOpen('instagram://')) {
  // Instagram установлен
}
```

> Для не-http схем (`instagram://`, `tg://`) нужно объявить их в
> `Info.plist` под `LSApplicationQueriesSchemes` — иначе `canOpen`
> вернёт `false`.

### Принять deep link

```ts
const unsubscribe = lumen.linking.onIncoming.subscribe((url) => {
  console.log('opened by URL:', url)
  // парси и навигируй
})

// при unmount страницы
unsubscribe()
```

Cold-launch URLs тоже доставятся — рантайм держит pending queue до
первой подписки.

---

## biometrics — Face ID / Touch ID

```ts
const type = lumen.biometrics.available()
// 'faceID' | 'touchID' | 'none'

if (type !== 'none') {
  const ok = await lumen.biometrics.authenticate('Authorize transfer')
  if (ok) {
    proceed()
  } else {
    // cancel / fallback / lockout
  }
}
```

`reason` показывается пользователю в system prompt'е. **Должен быть
осмысленным** — Apple отклоняет приложения с пустым/тупым reason.

`authenticate` всегда resolve'ится — никогда не reject. `true` — успех,
`false` — любая ошибка (cancel, lockout, нет permission).

> Требует `"biometric"` в `manifest.permissions`.

---

## notifications — local

### Permission

```ts
const status = await lumen.notifications.requestPermission()
// 'granted' | 'denied'
```

Если юзер уже отказал — iOS не покажет prompt снова, вернёт `denied`.

### Schedule

```ts
const id = await lumen.notifications.schedule({
  title: 'Reminder',
  body: 'Time to check your stats',
  at: Date.now() + 60_000,  // через минуту
  id: 'custom-id-or-omit',
})

// Отменить
lumen.notifications.cancel(id)
lumen.notifications.cancelAll()
```

### Tap на нотификации

```ts
const unsub = lumen.notifications.onTap.subscribe((id) => {
  console.log('user tapped notification:', id)
})
```

Cold-launch — рантайм удерживает event до первой подписки.

---

## statusBar

```ts
lumen.statusBar.style({ theme: 'light' })  // белые иконки
lumen.statusBar.style({ theme: 'dark' })   // тёмные иконки
lumen.statusBar.style({ theme: 'auto' })   // система
lumen.statusBar.style({ hidden: true })    // скрыть
```

Сбрасывается к `'auto'` на каждый mount fast-app'а.

---

## imagePicker / documentPicker

### Image

```ts
const asset = await lumen.imagePicker.pick({ limit: 1 })
if (asset) {
  // asset.uri = 'file:///tmp/lumen-picker/uuid.jpg'
  Image({ source: asset.uri, width: 200, height: 200 })
}

// Несколько
const assets = await lumen.imagePicker.pick({ limit: 5 })
// assets: PickedAsset[] | null
```

Не требует `NSPhotoLibraryUsageDescription` — picker работает
out-of-process через PHPicker.

### Documents

```ts
const docs = await lumen.documentPicker.pick({
  types: ['pdf'],     // или ['data'] для любых, или UTIs
  multiple: false,
})
if (docs) {
  for (const d of docs) {
    console.log(d.name, d.size, d.mime)
    // fetch как обычный файл
    const r = await fetch(d.uri)
    const blob = await r.arrayBuffer()
  }
}
```

Поддерживаемые алиасы: `'image'`, `'pdf'`, `'text'`, `'data'`, `'content'`,
`'audio'`, `'video'`, `'json'`, `'zip'`, `'html'`. Или raw UTI типа
`'public.pdf'`.

---

## share

```ts
lumen.share({
  text: 'Check this out',
  url: 'https://example.com',
  onDone: (completed, activity) => {
    if (completed) console.log('shared via', activity)
  },
})
```

`UIActivityViewController` — system share sheet. `activity` — bundle id
выбранной target-аппы.

---

## WebSocket

```ts
const ws = lumen.ws('wss://stream.example.com/feed', {
  onOpen: () => console.log('connected'),
  onMessage: (text) => console.log('msg:', text),
  onClose: () => console.log('disconnected'),
  onError: (msg) => console.error('ws error:', msg),
})

ws?.send('hello')
ws?.close()
```

`ws` возвращает `null`, если URL не прошёл sandbox-проверку (не в
`manifest.connect` или не https/wss). Подробнее — глава 07.

---

## tabs — управление табами браузера

```ts
lumen.tabs.list()        // все табы
lumen.tabs.current()     // активный таб
lumen.tabs.own()         // мой собственный
lumen.tabs.open('https://other-app.com')   // открыть новый
lumen.tabs.close()       // закрыть мой
lumen.tabs.switch(tabId) // переключить shell на таб
```

Удобно для multi-tab воркфлоу или открытия related fast-app'ов.

---

## Reactive system state

Эти поля **реактивные** — читай в thunk'е, получаешь автообновление:

```ts
lumen.safeArea.top                      // pt, обновляется при rotate/keyboard
lumen.appState                          // 'active' | 'inactive' | 'background'
lumen.appearance.theme                  // 'dark' | 'light'
lumen.network.online                    // boolean
lumen.network.type                      // 'wifi' | 'cellular' | 'none' | ...
```

Пример:

```ts
mount(() => View({
    flex: 1,
    paddingTop: lumen.safeArea.top,
    backgroundColor: () => lumen.appearance.theme === 'dark' ? '#000' : '#FFF',
  },
  Slot({}, () => lumen.network.online
    ? renderApp()
    : Text('No connection'),
  ),
))
```

---

## bench — performance HUD

```ts
lumen.bench.showFPS(true)         // floating FPS HUD
lumen.bench.resetStats()
const stats = lumen.bench.snapshot()
// { avg, min, p5, max, count }
```

Полезно для проверки 120 fps на ProMotion или поиска frame drops.

---

## Дальше

→ [06 — Navigation](06-navigation.md): router, страницы, табы.
