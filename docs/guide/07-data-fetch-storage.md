# 07 — Data: fetch & storage

## fetch

Стандартный `fetch` (минимальное подмножество Web Fetch API):

```ts
const r = await fetch('https://api.example.com/users/42')
if (!r.ok) {
  console.error('failed:', r.status)
  return
}
const user = await r.json()
```

### Опции

```ts
await fetch('https://api.example.com/transfer', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
  },
  body: JSON.stringify({ amount: 100, to: 'IBAN...' }),
})
```

`body` принимает:
- `string` — отправится UTF-8
- `ArrayBuffer` / `Uint8Array` / любой typed array — сырые байты
  (для binary upload)

### binary response

`response.text()` пытается UTF-8 декодировать — для бинарных файлов
(PDF, images, mp3, zip) используй `arrayBuffer()`:

```ts
const r = await fetch('https://example.com/file.pdf')
const bytes = await r.arrayBuffer()  // ArrayBuffer
```

### Скачать локально и показать как Image

```ts
const r = await fetch('https://api.example.com/avatar.png')
const buf = await r.arrayBuffer()
// (TODO: API для записи в tmp — пока используй DocumentPicker uri или Image c source URL)

// Или проще — Image сам тянет:
Image({ source: 'https://api.example.com/avatar.png', width: 100, height: 100 })
```

---

## Sandbox: `connect` whitelist

**По умолчанию** `fetch` разрешён ТОЛЬКО на own-origin (тот же
scheme+host+port, откуда загрузился fast-app). Cross-origin блокируется.

Чтобы открыть нужные хосты — пропиши в `manifest.json`:

```json
{
  "name": "My App",
  "version": "0.0.1",
  "entry": "/index.ts",
  "min_runtime": "0.1",
  "connect": [
    "https://api.example.com",
    "https://*.cdn.example.com"
  ]
}
```

| Запись | Что разрешается |
|---|---|
| `"https://api.example.com"` | exact host, https-only, default port |
| `"https://api.example.com:8443"` | exact host+port |
| `"https://*.cdn.example.com"` | любой subdomain под cdn.example.com |
| `"https://*"` | (запрещено) — нельзя whitelist'ить всё подряд |

Правила:
- **Только https** (и wss). HTTP в манифесте отвергается.
- **Wildcard только на subdomain**, не на TLD/host.
- Schema нормализуется: пиши `https://api.example.com` без trailing slash.

При попытке fetch'нуть не-whitelisted хост `fetch` reject'нется с
`NetworkPolicyError`.

> Это критично для безопасности: пользователь должен видеть в манифесте
> до установки fast-app'а, куда он будет ходить.

> Локальная разработка: для dev-server'а (`http://192.168.x.y:8080`)
> own-origin = `http://192.168.x.y:8080`. Все relative fetch'и работают,
> cross-origin требует whitelist даже на dev.

---

## storage — обычное key-value

```ts
lumen.storage.set('theme', 'dark')
lumen.storage.get('theme')         // 'dark' | undefined
lumen.storage.remove('theme')
lumen.storage.keys()                // string[]
lumen.storage.clear()
```

Под капотом — `UserDefaults`, **scoped per origin**. Один fast-app не
видит данные другого.

**Тип значения — только `string`**. Хочешь сохранить объект — сериализуй:

```ts
lumen.storage.set('user', JSON.stringify(user))
const raw = lumen.storage.get('user')
const user = raw ? JSON.parse(raw) : null
```

### Реактивный wrapper

```ts
function persistedSignal<T>(key: string, initial: T): Signal<T> {
  const raw = lumen.storage.get(key)
  const sig = signal<T>(raw ? JSON.parse(raw) : initial)
  effect(() => lumen.storage.set(key, JSON.stringify(sig.value)))
  return sig
}

// usage
const theme = persistedSignal<'dark' | 'light'>('theme', 'dark')
```

---

## secureStorage — Keychain

Для секретов (access_token, refresh_token, encryption keys):

```ts
lumen.secureStorage.set('access_token', token)
lumen.secureStorage.get('access_token')
lumen.secureStorage.remove('access_token')
```

Под капотом — iOS Keychain Services. Шифруется системой, переживает
переустановку app'ы (опционально), биометрика-gated если настроить
(зайди в `KeychainAccessibility` константы Swift — пока default).

**Тип значения — только `string`**, как и `storage`.

> Не клади токены в `storage` — UserDefaults в plist'е читается без
> рут-доступа на джейлбрейке. Keychain — на secure enclave.

---

## Pattern: service layer

В средне-большом приложении вынеси сеть в отдельный `services/` модуль:

```ts
// services/bank-api.ts
const API = 'https://api.bank.example.com'

export class BankAPIError extends Error {
  constructor(public code: string, message: string) {
    super(message)
  }
}

export interface TransferRequest {
  to: string
  amountCents: number
}

export interface TransferResult {
  txId: string
  newBalanceCents: number
}

export async function makeTransfer(req: TransferRequest): Promise<TransferResult> {
  const token = lumen.secureStorage.get('access_token')
  if (!token) throw new BankAPIError('UNAUTH', 'Please log in')

  const r = await fetch(`${API}/transfer`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify(req),
  })

  if (r.status === 401) throw new BankAPIError('UNAUTH', 'Session expired')
  if (r.status === 422) {
    const detail = await r.json()
    throw new BankAPIError('VALIDATION', detail.message)
  }
  if (!r.ok) throw new BankAPIError('SERVER', `HTTP ${r.status}`)

  return await r.json() as TransferResult
}
```

В странице:

```ts
const submitting = signal(false)
const error = signal<string | null>(null)

async function submit() {
  submitting.value = true
  error.value = null
  try {
    const result = await makeTransfer({ to: iban.peek(), amountCents: amount.peek() })
    addTransaction({ ... })
    open('transactionDetail', { id: result.txId })
  } catch (e) {
    if (e instanceof BankAPIError) error.value = e.message
    else error.value = 'Unexpected error'
  } finally {
    submitting.value = false
  }
}
```

Page показывает loading через `() => submitting.value`, error через
`Slot({}, () => error.value ? Text(...) : null)`.

---

## WebSocket

```ts
const ws = lumen.ws('wss://stream.example.com/feed', {
  onOpen: () => ws?.send(JSON.stringify({ subscribe: 'BTC' })),
  onMessage: (msg) => {
    const data = JSON.parse(msg)
    price.value = data.price
  },
  onError: (err) => console.error(err),
  onClose: () => reconnect(),
})

// Закрыть когда страница уходит
const handle = mount(() => ...)
// ... in cleanup:
ws?.close()
```

WebSocket тоже под `connect`-policy: `wss://stream.example.com` должен
быть в манифесте.

`lumen.ws` возвращает `null` если URL не прошёл policy-check.

---

## Дальше

→ [08 — Advanced components](08-advanced-components.md): ScrollView,
VirtualList, TextInput, Blur/Glass, MapView.
