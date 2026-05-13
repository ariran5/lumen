# Session 010 — 2026-05-13: Strategy pivot + Platform Tier 1

> Стратегический pivot: shell-rewrite-on-Lumen деприоритизирован. Фокус смещён на расширение device-API. За одну сессию закрыт Platform Tier 1 — 7 bridges (clipboard, linking, share, actionSheet, secureStorage, imagePicker, websocket), PlatformLab demo, секция LUMEN на home, фикс критического бага в `_patchProp text` (текст не обновлялся из-за value-type RenderNode), локальный ws-echo сервер.

---

## TL;DR

| ID | Что | Файлы |
|---|---|---|
| **Strategy** | Shell-rewrite-on-Lumen деприоритизирован — нативный shell уже хорош, dogfood не даёт user value | [memory/browser_shell_direction.md](../...memory/browser_shell_direction.md) |
| **Strategy** | DX-инфра (HMR, npm, @lumen/ui, DevTools) отложена в backlog | [docs/backlog-infra.md](../docs/backlog-infra.md) |
| P8.1 | `lumen.clipboard.{copy,paste,has}` — UIPasteboard | JSEngine+Clipboard.swift |
| P8.2 | `lumen.linking.{open,canOpen}` — UIApplication.shared.open | JSEngine+Linking.swift |
| P8.3 | `lumen.share({text,url,onDone})` — UIActivityViewController | JSEngine+Share.swift |
| P8.4 | `lumen.actionSheet({title,actions,onSelect,onCancel})` — UIAlertController.actionSheet | JSEngine+ActionSheet.swift |
| P8.5 | `lumen.secureStorage.{get,set,remove}` — Keychain через SecItem* | JSEngine+SecureStorage.swift |
| P8.6 | `lumen.imagePicker.pick({limit}) → Promise<Asset\|Asset[]\|null>` — PHPickerViewController | JSEngine+ImagePicker.swift |
| P8.7 | `lumen.ws(url, callbacks) → handle` — URLSessionWebSocketTask | JSEngine+WebSocket.swift |
| P8.8 | Types для всех Tier 1 API | packages/lumen-types/index.d.ts |
| P8.9 | PlatformLab demo (карточка per API) + ws-echo сервер | Examples/PlatformLab/, tools/ws-echo.ts |
| P8.10 | Секция LUMEN на home — 4×2 chip-сетка к Lab'ам | BuiltinFastApps.swift homeJS |
| **Bug fix** | `_patchProp text` → relayout через `Renderer.patchText` (RenderNode = struct, надо мутировать lastTree) | Renderer.swift, JSEngine+Patch.swift |

---

## Strategy pivot (контекст)

Пользователь поднял ключевой вопрос: *«мы же уже сделали оболочку, зачем наш шелл? что он даст?»*

Память [browser_shell_direction](../...memory/browser_shell_direction.md) хранила старый план: dogfood — переписать shell на Lumen, ordered блокеры `TextInput → ScrollView → Blur → lumen.tabs → shell-as-fast-app`. Все блокеры по факту закрыты (TextInput, ScrollView, Blur — отдельные Lab'ы есть; lumen.tabs.subscribe + navigate — в P7).

Решение: shell-rewrite остаётся возможной side-quest'ой, но **не приоритет**. Реальная ценность Lumen — в фастаппах, и им не хватает device-API: clipboard, share, push, picker, keychain, websocket, …

Запросы пользователя:
1. Запиши DX-инфру (HMR, npm bundling, @lumen/ui, DevTools, FPS overlay) в бэклог — [docs/backlog-infra.md](../docs/backlog-infra.md)
2. Расширь платформу — что не хватает для «хорошего приложения»

Аудит API surface дал три tier'а:
- **Tier 1** (без этого ни одно реальное app не построить): clipboard, linking, share, actionSheet, secureStorage, imagePicker, ws → **закрыли в этой сессии**
- **Tier 2**: push notifications, biometrics, lifecycle, theme detection, network info, deep links, status bar style, pull-to-refresh → **следующая сессия**
- **Tier 3** (нишевые): camera capture, document picker, audio/video, sensors, HealthKit, IAP

План задокументирован в [docs/PLAN-platform-tier1.md](../docs/PLAN-platform-tier1.md).

---

## Tier 1 — 7 bridges за один заход

Pattern для каждого моста: отдельный `Sources/LumenRuntime/JSEngine+*.swift`, метод `installFooBridge()` вызывается из `installPlatformBridges()` в [JSEngine+Platform.swift](../Sources/LumenRuntime/JSEngine+Platform.swift).

### P8.1 — Clipboard

`UIPasteboard.general.string` getter/setter обёрнут в `@convention(block)`. 33 LOC.

```ts
lumen.clipboard.copy('text')
lumen.clipboard.paste() // string | null
lumen.clipboard.has()   // bool
```

### P8.2 — Linking

`UIApplication.shared.open` + `canOpenURL`. Поддерживает http(s), mailto:, tel:, sms: + custom schemes. Для `canOpen` non-http схем нужен `LSApplicationQueriesSchemes` в Info.plist (не делали, можно добавить когда понадобится).

### P8.3 — Share

`UIActivityViewController` через `TopViewController.find()`. Поддерживает text + url + onDone(completed, activityType). iPad popover anchored по центру с `permittedArrowDirections = []`.

### P8.4 — ActionSheet

`UIAlertController.actionSheet` с массивом actions (`label`, `style: default|destructive|cancel`). Cancel-кнопка добавляется автоматом если в actions её нет. `onSelect(index)` приходит с 0-based индексом (без учёта Cancel).

### P8.5 — SecureStorage (Keychain)

`SecItem*` API, kSecClassGenericPassword, service `com.lumen.secureStorage`, accessibility `kSecAttrAccessibleAfterFirstUnlock`. Idempotent set: SecItemDelete → SecItemAdd. ~75 LOC.

### P8.6 — ImagePicker (самая сложная)

`PHPickerViewController` (не требует `NSPhotoLibraryUsageDescription` — out-of-process picker). Async Promise-based:

```ts
lumen.imagePicker.pick({limit: 1}) // Promise<{uri, width, height} | null>
lumen.imagePicker.pick({limit: 5}) // Promise<Array<{uri,width,height}>>
```

- `PHPickerResult.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.image", ...)` копирует файл в `NSTemporaryDirectory/lumen-picker/<uuid>.<ext>`, возвращаемый `uri` — `file://`-URL
- Dimensions через `CGImageSourceCopyPropertiesAtIndex` (`kCGImagePropertyPixelWidth/Height`)
- Аккумулятор результатов — отдельный `@unchecked Sendable` class с NSLock: Swift 6 strict concurrency отвергает захват `var [Any]` в `@Sendable` closure'ах от `loadFileRepresentation`
- Coordinator (PHPickerViewControllerDelegate) хранится в `static [ObjectIdentifier: ImagePickerCoordinator]` dict пока пользователь не закроет picker; `nonisolated picker(...)` диспатчит обратно на main через `DispatchQueue.main.async + MainActor.assumeIsolated`

### P8.7 — WebSocket

`URLSessionWebSocketTask`, recursive `receive` loop. API колбэк-based, не WHATWG `WebSocket`-style (под npm-либы добавим shim когда дойдём до bundler'а):

```ts
const h = lumen.ws('ws://host:port', {
  onOpen: () => ...,
  onMessage: (text) => ...,  // text+binary оба сюда (decoded UTF-8)
  onClose: () => ...,
  onError: (msg) => ...,
})
h.send('ping')
h.close()
```

`WebSocketBridge` хранится в `static [ObjectIdentifier: WebSocketBridge] alive` dict, держит strong refs на JSValue callbacks. `onOpen` фаерится в `DispatchQueue.main.async` после `task.resume()` — URLSessionWebSocketTask не даёт явного onOpen-делегата, handshake-ошибка ловится receive loop'ом и пойдёт в `onError`.

---

## PlatformLab demo

[Examples/PlatformLab/](../Examples/PlatformLab/), порт **8089** в dev-server'е. 7 карточек, по одной на API. Конечный layout (после редизайна по фидбеку юзера — он жаловался что не понятно куда смотреть, статус был мелким в top-right):

```
┌─────────────────────────────────────┐
│ CLIPBOARD                           │
│ pasted: Lumen rocks                 │  ← Status — большой моноширинный
│ [Copy "Lumen rocks"]    [Paste]     │  ← Actions
└─────────────────────────────────────┘
```

WS-карточка дополнительно содержит log-блок (тёмная панель с последними 6 сообщениями) между статусом и кнопками.

Каждая карточка self-contained: per-card signal'ы (`clipboardSeen`, `secretValue`, `pickedAsset`, `wsStatus`, `wsLog`, `wsConnected`, `linkingResult`, `shareResult`, `actionResult`). Глобального event-feed'а сверху нет (был, убран — два источника информации запутывали).

Button label через thunk: `PrimaryButton(() => wsConnected.value ? 'Disconnect' : 'Connect', ...)` — реактивно меняется при connect/disconnect.

---

## Local ws-echo сервер ([tools/ws-echo.ts](../tools/ws-echo.ts))

Изначально PlatformLab целился в `wss://echo.websocket.events` — Heroku-app retired, DNS возвращает CNAME без A-record. Heroku снял приложение, сервис мёртв.

Заменили на локальный `Bun.serve` echo:
- `ws://192.168.0.107:9000` (для phone в той же Wi-Fi)
- На open шлёт `hello from lumen ws-echo`
- На любое сообщение отвечает `echo: <msg>`
- ATS: разрешено через `NSAllowsLocalNetworking: true` (уже в project.yml)

Запуск: `bun tools/ws-echo.ts 9000`. Должен крутиться параллельно с dev-server'ами Lab'ов.

---

## Секция LUMEN на home

Добавлено в [BuiltinFastApps.swift homeJS](../Sources/LumenRuntime/BuiltinFastApps.swift): между Pinned и Recent — секция `LUMEN`, 4×2 chip-grid из 8 Lab'ов:

| | | | |
|---|---|---|---|
| Tabs (8080) | Drag (8082) | Glass (8083) | Scroll (8084) |
| Inputs (8085) | Sheets (8086) | Maps (8088) | **Platform (8089)** |

Tap chip → `lumen.haptics('light') + lumen.tabs.navigate(url)`. URL'ы захардкожены `http://192.168.0.107:80xx` (с поправкой IP, см. ниже).

---

## Bug fix — `_patchProp text` без relayout

**Симптом:** в карточках Clipboard / SecureStorage / WS статус-текст «пропадал» после нажатия кнопки. Длинная новая строка обрезалась.

**Диагноз:**
- `RenderNode` — **struct** (value type). При `_patchProp("text", ...)` мы делали `textLayer.string = ...` + `mount.node.text = s`. `mount.node` — копия в MountedNode, lastTree держал старый текст
- CATextLayer обновил содержимое, но его frame считался при initial mount по старому intrinsic measure → новая строка не помещается, текст обрезан или невидим

**Первая (неправильная) попытка:** добавил `renderer.relayout()` сразу в `_patchProp`. Поломалось ВСЁ — потому что reconcile видел `mounted.node.text` = новый, а `tree.node.text` (из lastTree) = старый, и применял к layer'у старый текст обратно. Текст никогда не обновлялся.

**Правильный фикс:**
```swift
// Renderer.swift
func patchText(id: Int, text: String) {
    guard var tree = lastTree else { return }
    if Self.mutateText(&tree, id: id, text: text) {
        lastTree = tree
        relayout()
        onAfterLayout?()
    }
}

private static func mutateText(_ node: inout RenderNode, id: Int, text: String) -> Bool {
    if node.id == id { node.text = text; return true }
    for i in 0..<node.children.count {
        if mutateText(&node.children[i], id: id, text: text) { return true }
    }
    return false
}
```

```swift
// JSEngine+Patch.swift
case "text":
    if value.isString, let s = value.toString() {
        ref.renderer?.patchText(id: id, text: s)
    }
```

Это аналогично паттерну `replaceChildren(id:newChildren:)`: мутируем lastTree → relayout → reconcile применяет к layer'у. Reconcile рассчитывает frame по новому intrinsic measure через `buildFlex(tree)`.

**Цена:** каждый text-patch теперь = полный relayout. Для HN-cell'а с реактивным title — ок (одна перерисовка per visit, изредка). Если упрёмся в perf-проблему на high-frequency text update'ах — оптимизируем до subtree-relayout.

---

## IP fragility (followup)

Mac DHCP отдал `192.168.0.107` вместо `.108`. Все URL'ы Lab'ов оказались битыми. Захардкожено в:
- [Sources/LumenRuntime/BuiltinFastApps.swift](../Sources/LumenRuntime/BuiltinFastApps.swift) (labs grid)
- [Sources/LumenShell/BrowserView.swift](../Sources/LumenShell/BrowserView.swift) (StartPage fallback list)

Один `sed -i ''` поправил, но это хрупко — DHCP может переназначить в любой момент. **TODO в backlog:** вытащить dev-server host в одно место (manifest `lumen.dev.host`, env-flag в FastAppHost, или авто-discovery `localhost:8080` от текущего IP роутера).

---

## Файлы

**Добавлено:**
- `Sources/LumenRuntime/JSEngine+Clipboard.swift`
- `Sources/LumenRuntime/JSEngine+Linking.swift`
- `Sources/LumenRuntime/JSEngine+Share.swift`
- `Sources/LumenRuntime/JSEngine+ActionSheet.swift`
- `Sources/LumenRuntime/JSEngine+SecureStorage.swift`
- `Sources/LumenRuntime/JSEngine+ImagePicker.swift`
- `Sources/LumenRuntime/JSEngine+WebSocket.swift`
- `Examples/PlatformLab/{index.ts, manifest.json, tsconfig.json}`
- `tools/ws-echo.ts`
- `docs/PLAN-platform-tier1.md`
- `docs/backlog-infra.md`

**Изменено:**
- `Sources/LumenRuntime/JSEngine+Platform.swift` — install* вызовы
- `Sources/LumenRuntime/Renderer.swift` — `patchText` + `mutateText`
- `Sources/LumenRuntime/JSEngine+Patch.swift` — делегация text в Renderer
- `Sources/LumenRuntime/BuiltinFastApps.swift` — LabsSection
- `Sources/LumenShell/BrowserView.swift` — example list IP
- `packages/lumen-types/index.d.ts` — Tier 1 API types
- `docs/ROADMAP.md` — P8 closure + decision log
- `~/.claude/projects/.../memory/browser_shell_direction.md` — strategy update

---

## Open / followups

- **Tier 2** (next session): push notifications, biometrics, app lifecycle, theme reactive, network info, deep links, status bar style, pull-to-refresh
- **patchText perf** — текущая реализация relayout-on-every-text-change. Если упрёмся в реальном app — оптимизируем до subtree relayout
- **IP/host configuration** — выкорчевать хардкод `192.168.0.107` в одно место (manifest или auto-discovery)
- **WebSocket** — нет `binary` режима (всё декодится UTF-8 строкой). Добавим если упрёмся в реальный use-case
- **ImagePicker** — нет `camera` source. Tier 3 фича, отдельная
- **Linking.canOpen** — для tel/mailto/sms работает; для деривативных схем (instagram://, twitter://) нужен `LSApplicationQueriesSchemes` в Info.plist
- **Share** — поддерживает text+url, не файл/image. Добавим если понадобится

## Deploy commands

Build for device:
```sh
xcodebuild -project Lumen.xcodeproj -scheme Lumen -configuration Debug \
  -destination 'id=00008130-001C21593CC0001C' -allowProvisioningUpdates build

xcrun devicectl device install app --device 3C968EEF-1505-5987-B4E8-FF7CD6C260F6 \
  "/Users/arian/Library/Developer/Xcode/DerivedData/Lumen-faxjlouniqfhksbtqnrbcjymwgmf/Build/Products/Debug-iphoneos/Lumen.app"

xcrun devicectl device process launch --device 3C968EEF-1505-5987-B4E8-FF7CD6C260F6 com.lumen.browser
```

Dev servers (Mac):
```sh
bun packages/lumen-cli/bin/lumen.js dev Examples/PlatformLab 8089 &
bun tools/ws-echo.ts 9000 &
# ... + остальные lab'ы по нужным портам
```
