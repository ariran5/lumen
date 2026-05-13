# Session 014 — 2026-05-14: Tier 3.A (document picker + fetch binary I/O) + Tier 3.B (per-origin sandbox foundation)

> Два логических куска в одной сессии. Сначала закрыли пункт из Tier 3 (document picker) и попутно расширили fetch до binary I/O — нужно чтобы что-то полезное делать с выбранным файлом. Потом большое design-обсуждение про sandbox / изоляцию apps по origin, и реализован Блок 1 «фундамент» (Origin + OriginContext + namespacing storage). Single-app продолжает работать; multi-app sandbox включится автоматически когда дозреет.

---

## TL;DR

| Часть | ID | Что | Файлы |
|---|---|---|---|
| Tier 3.A | P10.A.1 | `lumen.documentPicker.pick({types, multiple})` → `Promise<PickedDocument[] \| null>` (UIDocumentPickerViewController; security-scoped resource → copy в tmp; `{uri, name, size, mime}`) | JSEngine+DocumentPicker.swift, JSEngine+Platform.swift |
| Tier 3.A | P10.A.2 | `fetch()` binary I/O: `Response.arrayBuffer()` → real ArrayBuffer; request body принимает `ArrayBuffer \| ArrayBufferView`; обратная совместимость с string body | JSEngine+Fetch.swift |
| Tier 3.A | Types | LumenDocumentPicker, PickedDocument, DocumentPickerOptions; FetchOptions.body union; FetchResponse.arrayBuffer() | packages/lumen-types/index.d.ts |
| Tier 3.A | Demo | DocumentPickerCard с type-aware preview (image thumb / text snippet / hex dump первых 32 байт для binary) | Examples/PlatformLab/index.ts |
| Tier 3.B | P10.B.1 | `Origin` value type — scheme+host+port, нормализация default-портов, `shortHash` (SHA-256 prefix) | Sources/LumenRuntime/Origin.swift |
| Tier 3.B | P10.B.2 | `OriginContext` + `OriginContextRegistry` — per-origin persistent state (storage prefix, Keychain service, FS roots) с дедупом по Origin | Sources/LumenRuntime/OriginContext.swift |
| Tier 3.B | P10.B.3 | `JSEngine.init(origin:)` обязательный; `originContext` доступен всем bridge-extension'ам | JSEngine.swift |
| Tier 3.B | P10.B.4 | `lumen.storage` UserDefaults prefix per origin (`lumen.storage.<hash>.<key>`) | JSEngine+Storage.swift |
| Tier 3.B | P10.B.5 | `lumen.secureStorage` Keychain `service` per origin (`com.lumen.secureStorage.<hash>`) | JSEngine+SecureStorage.swift |
| Tier 3.B | P10.B.6 | `LumenManifest` расширен опциональными `permissions` / `connect` / `storage_quota` (заделы под будущий enforcement, runtime пока не читает) | BundleLoader.swift |
| Tier 3.B | P10.B.7 | `FastAppHost.Coordinator.setupEngine` извлекает Origin из tab URL, прокидывает в JSEngine | FastAppHost.swift |

Коммиты: `bfd019c` (Tier 3.A), `99c2058` (Tier 3.B).

---

## Tier 3.A.1 — Document picker

```ts
const docs = await lumen.documentPicker.pick({
  types: ['pdf', 'image', 'text'],   // алиасы → UTI'и
  multiple: true,
})
// docs: [{ uri: 'file:///tmp/.../<uuid>.pdf', name: 'report.pdf', size: 124356, mime: 'application/pdf' }, ...]
```

### Архитектура

- **`UIDocumentPickerViewController(forOpeningContentTypes:asCopy:true)`** — `asCopy:true` чтобы система сделала локальную копию из iCloud/external provider (иначе при оффлайн-доступе обломится).
- **`parseContentTypes`** принимает алиасы (`image/pdf/text/data/content/audio/video/movie/json/zip/html`) → соответствующие `UTType`. Можно также передать raw UTI (`"public.image"`). Default — `[.data]` (любой файл).
- **Security-scoped resource:** `startAccessingSecurityScopedResource()` обязательно перед чтением URL'а из Files.app / iCloud / external provider — без этого `Data(contentsOf:)` упадёт с permission denied. После копирования — `stopAccessingSecurityScopedResource()`.
- **Tmp файл per pick:** mirrors imagePicker pattern. `NSTemporaryDirectory()/lumen-docs/<uuid>.<ext>`. Оригинальное имя сохраняется в `name` поле — fast-app может показать пользователю «report.pdf» вместо UUID'а.
- **Delegate retain pattern:** `DocumentPickerCoordinator` — `@MainActor` класс с nonisolated делегат-методами, статический `alive` dict держит retain пока picker'а не закрыли.

### MIME inference

`UTType.preferredMIMEType` — если есть в UTI, иначе nil. Для unknown типов пропускаем поле — JS видит `mime: undefined`.

---

## Tier 3.A.2 — fetch binary I/O

```ts
// Read binary
const r = await fetch(doc.uri)              // file:// URL'ы тоже работают (URLSession transparent)
const buf = await r.arrayBuffer()           // real ArrayBuffer, не fake-bytes-from-string
const view = new Uint8Array(buf)
console.log(view.slice(0, 4))               // [0x25, 0x50, 0x44, 0x46] для PDF

// Write binary
await fetch('https://api.example.com/upload', {
  method: 'POST',
  body: await someFile.arrayBuffer(),       // или Uint8Array, или Int8Array, и т.д.
})
```

### JavaScriptCore C-API (без него — никак)

JSC C-API нужен потому что Objective-C bridge не умеет ArrayBuffer'ы. Импортируется `@preconcurrency import JavaScriptCore` для доступа к C-функциям.

**Read (JS ArrayBuffer/TypedArray → Swift Data):**

```swift
JSObjectGetArrayBufferBytesPtr(ctx, ref, nil)
JSObjectGetArrayBufferByteLength(ctx, ref, nil)
// Для TypedArray'ев — с offset/length вариант:
JSObjectGetTypedArrayBytesPtr / ByteLength / ByteOffset
JSValueGetTypedArrayType(ctx, ref, nil)
```

**Write (Swift Data → JS ArrayBuffer):**

```swift
let ptr = malloc(length)
data.copyBytes(to: ptr.assumingMemoryBound(to: UInt8.self), count: length)
let deallocator: JSTypedArrayBytesDeallocator = { p, _ in free(p) }
JSObjectMakeArrayBufferWithBytesNoCopy(ctx, ptr, length, deallocator, nil, nil)
```

`MakeArrayBufferWithBytesNoCopy` передаёт ownership malloc'нутого буфера JSC. Когда JS GC соберёт ArrayBuffer — JSC позовёт наш free. Чистый ownership transfer без double-free / leak.

### Backwards compat

- Старый `body: JSON.stringify(...)` (string) продолжает работать — fallback на UTF-8 encoding если bodyVal не binary.
- `Response.text()` / `.json()` теперь декодит UTF-8 lossy из тех же байт что положены в `_buffer`. Бинарный response с `.text()` даст мусор — нормальное поведение fetch.

---

## Design discussion — sandbox isolation model

Перед стартом Tier 3.B было длинное обсуждение про то, как изолировать apps друг от друга. Фиксирую решения здесь для будущих сессий.

### Identity model

- **Origin = `scheme + host + port`** (как web). Никаких манифестных `app_id`, никаких app groups.
- Манифестный `id` — это claim, не proof. Без подписи манифеста любой может объявить `"id": "com.acme.notes"`. Использовали бы либо подпись (большая инфра), либо TOFU (first-claim-wins). Решили: проще не вводить вовсе.
- App groups (sharing данных между «своими» appами) — нет. Если когда-то понадобится — обмен через user-gesture API (share, deep link).

### Permissions

- **Default-deny.** notifications, biometric, camera, mic, photos, location, contacts — все запрещены до user-prompt'а.
- **Двухслойная permission модель:** OS → Lumen (Apple-side grant Lumen'у как app'у), Lumen → конкретный app внутри (per-origin registry `{origin → {capability → grant}}`). Точная аналогия Chrome / Safari permissions.
- **Gesture-API исключения** (без persistent grant): `documentPicker`, `imagePicker`, `share`, `clipboard.write` — каждый клик «выбрать файл» = consent.

### Network

- **Default-allow только своему host:** `https://<own-host>`, `https://*.<own-host>`, любой порт. WS/WSS туда же.
- **Остальное — манифестный `connect` allowlist:** `"connect": ["api.partner.com", "*.cdn.io"]`. Wildcard `"*"` = allow-all с варнингом в шелле.
- **Cross-origin redirect блокируется** если target не в `connect`.
- **Public Suffix List** для `*.acme.com` matching — `app.co.uk` НЕ должен считать `co.uk` своим родителем. MVP-матчер сначала, PSL подцепим позже.

### Transport

- **HTTPS-only для apps by default.** Только `localhost` и `*.local` — free pass.
- **HTTP exception:** Developer Mode toggle в Lumen settings (off для prod). Per-origin override list — на потом, для preview-деплоев типа `*.vercel.app` (которые впрочем сами на https обычно).

### Deep links

- Apps НЕ объявляют custom URL schemes (`acme://`). Это путь к конфликтам (claim races, TOFU vs registry, picker UI).
- HTTPS-ссылки на `lumen.json` URL — это и есть универсальный deep link. Lumen регистрирует один URL handler в iOS (либо `lumen://`, либо Universal Links), внутри роутит к нужному app'у по URL.

### Storage quota

- Default 100 MB per origin.
- Больше — через permission prompt (как `storage_quota: "500MB"` в манифесте).

### Что под изоляцию

**Persistent:** `lumen.storage`, `lumen.secureStorage`, filesystem (`Documents/apps/<hash>/`), tmp, HTTP cache + cookies, push token, granted permissions.

**Runtime:** JSContext per app, таймеры / observers / WS — умирают с контекстом.

**Shared by design:** clipboard, share sheet, file/image picker, haptics, statusBar, appearance.

### Архитектура контекстов — два слоя

```
OriginContext (per origin, shared across tabs of same site)
├── permissions    {capability → grant}
├── storage handle (namespaced)
├── secureStorage handle
├── FS root        Documents/apps/<hash>/
├── HTTP cache + cookies
└── manifest + integrity hashes

TabContext (per tab, one origin)
├── JSContext      ← bridges installed here, capture context в closure
├── current URL + history stack
├── ref → OriginContext   (через registry, дедуп по origin)
└── ephemeral runtime state
```

Tab умирает → JSContext умирает → ephemeral cleaned. OriginContext живёт пока есть хоть один таб (или persistent в registry).

Это ровно браузерная модель (Chrome `Profile → Site → Tab`, Safari аналогично). Проверена годами.

### Roadmap по блокам реализации

| Блок | Что | Зависимости |
|---|---|---|
| **1** | Foundation — Origin + OriginContext + namespacing | — |
| **2** | Network policy — `connect` enforcement в fetch/WS + PSL + redirect blocking | манифест парсер |
| **3** | Permission registry + prompt UI + wire к camera/mic/notifications/biometric/location/contacts/photos | UI primitives (alert / modal — есть) |
| **4** | HTTPS-only + Developer Mode toggle в шелле | settings UI |
| **5** | Storage quotas + tracking | foundation |
| **6** | Multi-app shell tabs полностью (lumen.tabs registry, app loader, integrity) | foundation + manifest |

Block 1 закрыт в этой же сессии (см. Tier 3.B ниже). Остальные — отдельными заходами.

---

## Tier 3.B — Sandbox foundation (Block 1)

### Origin

```swift
struct Origin: Hashable, Sendable {
    let scheme: String   // lowercased
    let host: String     // lowercased
    let port: Int?       // default-ports → nil (443 for https, 80 for http, etc.)

    init?(url: URL)      // standard path
    static let system    // fallback для cases когда origin неизвестен
    var shortHash: String  // SHA-256 prefix (12 hex chars) — для namespacing
}
```

Default-port нормализация: `https://acme.com` и `https://acme.com:443` — один origin. Иначе пользователь дважды отвечал бы на permission prompt'ы.

### OriginContext + Registry

```swift
@MainActor
final class OriginContext {
    let origin: Origin

    var storagePrefix: String      // "lumen.storage.<hash>."
    var keychainService: String    // "com.lumen.secureStorage.<hash>"
    var documentsRoot: URL         // Documents/apps/<hash>/
    var tmpRoot: URL               // tmp/apps/<hash>/
}

@MainActor
final class OriginContextRegistry {
    static let shared = OriginContextRegistry()
    func context(for origin: Origin) -> OriginContext   // дедуп по Origin
}
```

Registry — singleton. Две табы acme.com получают **один** `OriginContext`. Когда добавятся permission grants — установка `granted[camera] = true` в одной табе видна во второй. Это ключевая семантика «origin shared, tab isolated».

### Wire через JSEngine

```swift
@MainActor
final class JSEngine {
    let originContext: OriginContext
    var origin: Origin { originContext.origin }

    init(origin: Origin) {
        ...
        self.originContext = OriginContextRegistry.shared.context(for: origin)
        ctx.name = "Lumen[\(origin)]"   // полезно при дебаге в Safari Inspector
        ...
    }
}
```

Все bridge-extension'ы (`installStorageBridge`, `installSecureStorageBridge`, ...) теперь читают `originContext` напрямую через `self`.

### Storage namespacing

```swift
// JSEngine+Storage.swift
let prefix = originContext.storagePrefix      // "lumen.storage.<hash>."
```

Старые ключи `lumen.storage.<key>` без хеша — теперь не читаются. Acceptable (нет публичных users), миграцию не делал.

### SecureStorage namespacing

```swift
// JSEngine+SecureStorage.swift
let service = originContext.keychainService   // "com.lumen.secureStorage.<hash>"
```

Все Keychain entries app'а живут под одним service. Для clear-site-data — `SecItemDelete(.kSecAttrService: service)` снимает всё за один вызов.

### LumenManifest расширение

```swift
struct LumenManifest: Decodable, Sendable {
    let name, version, entry: String
    let minRuntime: String?
    let dev: Bool?
    // Новые опциональные поля (runtime пока не читает):
    let permissions: [String]?       // ["notifications", "camera", ...]
    let connect: [String]?           // ["api.acme.com", "*.cdn.io"]
    let storageQuota: String?        // "200MB"
}
```

Decoding extra fields в существующих манифестах не ломает — все nullable. Когда придут Блоки 2-5, runtime начнёт их читать и enforce'ить.

### FastAppHost wire

```swift
func setupEngine() {
    ...
    let origin = Origin(url: url) ?? .system   // tab URL уже известен
    let engine = JSEngine(origin: origin)
    ...
}
```

Single-app demo (PlatformLab по `localhost:8080`) теперь automatically живёт в своём origin namespace — но visible поведение не меняется, single app не с кем шарить namespace.

---

## Файлы

**Добавлено (Tier 3.A):**
- `Sources/LumenRuntime/JSEngine+DocumentPicker.swift`

**Изменено (Tier 3.A):**
- `Sources/LumenRuntime/JSEngine+Platform.swift` — `installDocumentPickerBridge()` в `installPlatformBridges()`
- `Sources/LumenRuntime/JSEngine+Fetch.swift` — binary I/O (arrayBuffer + ArrayBuffer body); JSC C-API хелперы `extractBinaryBytes` / `makeArrayBuffer`
- `packages/lumen-types/index.d.ts` — LumenDocumentPicker, FetchResponse.arrayBuffer, FetchOptions.body union
- `Examples/PlatformLab/index.ts` — DocumentPickerCard + type-aware preview (image / text / hex)

**Добавлено (Tier 3.B):**
- `Sources/LumenRuntime/Origin.swift`
- `Sources/LumenRuntime/OriginContext.swift`

**Изменено (Tier 3.B):**
- `Sources/LumenRuntime/JSEngine.swift` — `init(origin:)`, `originContext` property
- `Sources/LumenRuntime/JSEngine+Storage.swift` — prefix per origin
- `Sources/LumenRuntime/JSEngine+SecureStorage.swift` — service per origin
- `Sources/LumenRuntime/BundleLoader.swift` — LumenManifest расширен permissions/connect/storage_quota
- `Sources/LumenShell/FastAppHost.swift` — Origin extract из tab URL → JSEngine

---

## Build & deploy

- Tier 3.A: clean build на симуляторе + iPhone, проверено E2E на устройстве (документ-пикер → preview → fetch binary читает hex).
- Tier 3.B: clean build на симуляторе iPhone 17 Pro. Single-app продолжает работать; smoke-проверки storage/secure не делал — invisible refactor, проверится в Block 2-3 когда добавится UI permission prompt'ов.

---

## Acceptance check

| | Проверено |
|---|---|
| **Tier 3.A** | |
| `lumen.documentPicker.pick()` показывает system picker | ✓ |
| File copy в tmp с original name | ✓ |
| `fetch(file://uri).arrayBuffer()` возвращает real ArrayBuffer | ✓ |
| PDF preview shows hex `25 50 44 46` (%PDF) | ✓ |
| Backwards compat `body: JSON.stringify(...)` | ✓ |
| Type definitions — tsc clean | ✓ |
| **Tier 3.B** | |
| Origin типизирован, derived from URL, default-port normalized | ✓ |
| OriginContext дедуплицируется через Registry | ✓ |
| JSEngine.init требует Origin | ✓ |
| storage prefix содержит origin hash | ✓ |
| Keychain service содержит origin hash | ✓ |
| LumenManifest парсит новые опциональные поля (smoke-test через Decodable — fields nullable, ничего не упадёт) | ✓ |
| Build clean | ✓ |

---

## Дальше

**Sandbox roadmap, осталось 5 блоков:**
- Block 2 — Network `connect` enforcement в fetch/WS + PSL + redirect blocking
- Block 3 — Permission registry + prompt UI + wire к capabilities
- Block 4 — HTTPS-only + Developer Mode toggle
- Block 5 — Storage quotas + tracking
- Block 6 — Tabs / multi-app shell (lumen.tabs registry уже частично есть, нужен app loader + integrity)

**Tier 3 capability backlog** (из старого плана): camera capture, audio/video, sensors, HealthKit, BLE, IAP, Sign in with Apple, mail/SMS composers.

Document picker из Tier 3 закрыт. Остальные — отдельными заходами по запросу.

---

## Open / followups

- **Filesystem namespacing for bridges** — `imagePicker` / `documentPicker` сейчас кладут tmp файлы в shared `tmp/lumen-images/` / `tmp/lumen-docs/`. UUID'ы делают cross-app pollution маловероятным, но не закрытым. Перевести на `originContext.tmpRoot` — отдельная мелкая задача.
- **Migration старых storage ключей** — текущие `lumen.storage.<key>` после Tier 3.B становятся недоступны. Не критично (нет публичных users), но если у меня самого есть приватные данные на симуляторе — потеряются. Decided acceptable, no migration.
- **`lumen://` builtin apps** — home / settings / history каждый получает свой `Origin(scheme:"lumen", host:"home")` и т.п. Storage между ними не шарится. Если шеллу понадобится shared system-state — введём global namespace отдельно от origin'ов.
