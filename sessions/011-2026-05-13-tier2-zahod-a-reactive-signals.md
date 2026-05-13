# Session 011 — 2026-05-13: Platform Tier 2 / Заход A — reactive system signals

> Закрыт Заход A из Tier 2 плана: `lumen.appState`, `lumen.appearance.theme`, `lumen.network.{online,type}` — все три как реактивные signal-backed getters. Чтение из thunk-prop'а делает узел подписчиком, Vapor-effect перерисует только этот узел при transition'е foreground↔background / смене темы / network change.

---

## TL;DR

| ID | Что | Файлы |
|---|---|---|
| P9.A.1 | `lumen.appState` ('active'\|'inactive'\|'background') | JSEngine+Lifecycle.swift |
| P9.A.2 | `lumen.appearance.theme` ('dark'\|'light') | JSEngine+Appearance.swift |
| P9.A.3 | `lumen.network.{online, type}` (NWPathMonitor) | JSEngine+Network.swift |
| Wrappers | Signal-backed getters в CoreFramework, по образцу `safeArea` | CoreFramework.swift |
| Types | LumenAPI расширен `appState` / `appearance` / `network` | packages/lumen-types/index.d.ts |
| Demo | PlatformLab: 3 новые карточки наверху скролла | Examples/PlatformLab/index.ts |
| Roadmap | P9.A row в ROADMAP, Заход A помечен как closed в PLAN | docs/ROADMAP.md, docs/PLAN-platform-tier1.md |

Деплой проверен на устройстве: `xcrun devicectl device install + process launch` — все три карточки реактивно обновляются.

---

## Архитектура signal-push pattern

Использован паттерн `safeArea` (см. P5.3), а не `subscribe`-канал на `NativeNotifier`:

- Native реагирует на системное событие → вызывает `lumen._updateXxx(value)`
- В CoreFramework `_updateXxx` пишет в JS-signal
- `lumen.foo` — `Object.defineProperty` с getter'ом, читающим `_signal.value`
- Thunk `() => lumen.foo === 'X' ? A : B` в style-slot'е → Vapor effect подписан на тот же signal → patch при изменении

Чем `safeArea`-pattern лучше `subscribe`-канала для скаляров:
- Не нужен явный `subscribe()`+`unsubscribe()` на стороне пользователя
- Per-prop effect автоматически — никакой инфраструктуры в user-code
- Symmetric с другими reactive lumen-полями

`NativeNotifier`-pattern (`tabs`, `history`) остаётся для коллекций — там нужен явный `subscribe(fn)` потому что callback вызывает getter `lumen.tabs.list()` для свежей копии массива.

---

## P9.A.1 — Lifecycle

```ts
View({opacity: () => lumen.appState === 'active' ? 1 : 0.5})
```

Native:
- `NotificationCenter.default.addObserver` на три UIApplication notifications:
  - `didBecomeActiveNotification` → `'active'`
  - `willResignActiveNotification` → `'inactive'`
  - `didEnterBackgroundNotification` → `'background'`
- Initial state читается синхронно через `UIApplication.shared.applicationState`
- Observer tokens хранятся в `static [ObjectIdentifier: LifecycleObservers]` — каждый JSEngine держит свой набор, GC'ится вместе с движком

Swift 6 strict concurrency quirk: `[NSObjectProtocol]` — non-Sendable, поэтому в `deinit` его трогать нельзя. Сделал holder без deinit'а — JSEngine живёт до конца процесса, observer'ы выживут.

`willEnterForeground` намеренно НЕ перехвачен — он симметричен `willResignActive` (приходит до `didBecomeActive`). Текущая модель: 'active' = ready to process events, 'inactive' = transient (incoming call, control center), 'background' = ушли. Стандартный iOS lifecycle.

---

## P9.A.2 — Appearance

```ts
Text({color: () => lumen.appearance.theme === 'dark' ? '#fff' : '#000'}, 'hi')
```

Native (iOS 17+):
- `UIWindowScene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { scene, _ in ... }`
- Registration token хранится в holder dict, чтобы scene не "забыл" подписчика
- Initial — `scene.traitCollection.userInterfaceStyle`

iOS 17 deployment target (см. project.yml `deploymentTarget: iOS: "17.0"`) → `registerForTraitChanges` доступен без guard'а. Старый `traitCollectionDidChange(_:)` override не понадобился.

Если будут случаи когда window scene ещё не создан на момент install (theoretically — fast-app загружается до scene attach), bridge будет жить с initial значением и без observer'а. Не воспроизводится в текущем потоке — fast-app грузится после рута, scene уже есть.

---

## P9.A.3 — Network

```ts
Slot({}, () => Text({color: lumen.network.online ? 'green' : 'red'},
                    () => `${lumen.network.online ? 'online' : 'offline'} · ${lumen.network.type}`))
```

Native:
- `NWPathMonitor` стартует на отдельной очереди `com.lumen.network.monitor`
- `pathUpdateHandler` приходит off-main → `DispatchQueue.main.async + MainActor.assumeIsolated`
- `classify(path:online:)` помечен `nonisolated` — он чистая функция и зовётся из off-main замыкания

Path types → string:
- `.wifi` → `'wifi'`
- `.cellular` → `'cellular'`
- `.wiredEthernet` → `'wired'`
- иначе → `'other'`
- не satisfied → `'none'`

Initial — `(online: true, type: 'unknown')`. NWPathMonitor сразу шлёт первый pathUpdate после `.start()`, так что 'unknown' живёт миллисекунды. Не пытался читать синхронно — `NWPathMonitor.currentPath` есть, но требует чтоб мониторинг уже шёл, и pathUpdate так и так перепишет.

---

## JS-обёртки в CoreFramework

Все три блока в [CoreFramework.swift](../Sources/LumenRuntime/CoreFramework.swift), сразу после `safeArea`:

```js
// app lifecycle
const _appState = signal(typeof lumen._appStateInitial === 'string'
                         ? lumen._appStateInitial : 'active')
Object.defineProperty(lumen, 'appState', {
  get: function () { return _appState.value },
  configurable: false
})
lumen._updateAppState = function (s) { _appState.value = String(s) }

// appearance
const _theme = signal(...)
Object.defineProperty(lumen, 'appearance', {
  value: Object.freeze({
    get theme() { return _theme.value },
  }),
  writable: false, configurable: false
})
lumen._updateTheme = function (t) { _theme.value = String(t) }

// network
const _netOnline = signal(...)
const _netType   = signal(...)
Object.defineProperty(lumen, 'network', {
  value: Object.freeze({
    get online() { return _netOnline.value },
    get type()   { return _netType.value },
  }),
  writable: false, configurable: false
})
lumen._updateNetwork = function (online, type) {
  _netOnline.value = !!online
  _netType.value = String(type)
}
```

Frozen objects + non-configurable property descriptors — попытка вызвать `lumen.appearance = {}` или `delete lumen.appState` выбросит TypeError в strict mode. Хороший defensive default для public surface.

---

## PlatformLab — 3 новые карточки

В [Examples/PlatformLab/index.ts](../Examples/PlatformLab/index.ts) — наверху скролла (перед Tier 1 cards). Самая минимальная Card обёртка, status — thunk:

```ts
function AppStateCard() {
  return Card('APP STATE',
    () => `state: ${lumen.appState}`,
    Text({fontSize: 11, color: COLORS.textMuted},
         'Background app → выйди на home, вернись. Inactive — pull-down notification center.'),
  )
}
```

Без дополнительных Pressable — реактивность сама фаерится при системных событиях. Никаких `subscribe(fn)` в user-code, тонкий и читаемый.

---

## Файлы

**Добавлено:**
- `Sources/LumenRuntime/JSEngine+Lifecycle.swift`
- `Sources/LumenRuntime/JSEngine+Appearance.swift`
- `Sources/LumenRuntime/JSEngine+Network.swift`

**Изменено:**
- `Sources/LumenRuntime/JSEngine+Platform.swift` — `installLifecycleBridge/AppearanceBridge/NetworkBridge` calls
- `Sources/LumenRuntime/CoreFramework.swift` — `appState/appearance/network` reactive blocks
- `packages/lumen-types/index.d.ts` — `appState`, `appearance`, `network` поля в LumenAPI
- `Examples/PlatformLab/index.ts` — `AppStateCard`, `ThemeCard`, `NetworkCard`
- `docs/ROADMAP.md` — P9.A row (Tier 2 / reactive signals)
- `docs/PLAN-platform-tier1.md` — Заход A помечен как closed

---

## Swift 6 strict concurrency — заметки

| Проблема | Fix |
|---|---|
| `classify(path:online:)` зовётся из off-main handler'а; @MainActor isolation отвергается | пометил `nonisolated` — чистая функция, race-free |
| `[NSObjectProtocol]` non-Sendable в `deinit` LifecycleObservers | убрал deinit (JSEngine процесс-длительный), tokens живут с холдером |
| NotificationCenter блок-handler ждёт Sendable closure | `MainActor.assumeIsolated { push(...) }` внутри блока — стандартный паттерн |

---

## Acceptance check

| | Проверено |
|---|---|
| `lumen.appState` обновляется | ✓ home → background, return → active |
| `lumen.appearance.theme` обновляется | ✓ Control Center → toggle dark mode |
| `lumen.network.{online,type}` обновляется | ✓ airplane mode → 'none', wifi off → 'cellular' |
| Build clean | ✓ (warnings — pre-existing, не наши) |
| Deploy to phone | ✓ via `xcrun devicectl` |
| Types tsc clean | ✓ |

---

## Дальше по плану

Tier 2 **Заход B** — biometrics + pull-to-refresh + status bar. ~250 LOC. Описано в [docs/PLAN-platform-tier1.md](../docs/PLAN-platform-tier1.md):

- `lumen.biometrics.{authenticate(reason), available()}` — LAContext.evaluatePolicy
- Pull-to-refresh на ScrollView (`onRefresh`, `refreshing` props) — UIRefreshControl
- `lumen.statusBar.style({theme, hidden})` — preferredStatusBarStyle override

После B — **Заход C** (local notifications + deep links). APNS отложен в Tier 2.5.

## Open / followups

- **Edge case appearance**: bridge install до window scene attach. Не воспроизводится сейчас, но если столкнёмся — добавить deferred retry через `didBecomeActive`.
- **Network type для `.satellite` интерфейса** (iPhone 14+) — NWInterface.InterfaceType не имеет `.satellite`, попадает в `'other'`. На реальных iPhone'ах со starlink будет так.
- **NWPathMonitor cancel** — `NetworkHolder.deinit` зовёт monitor.cancel(), но JSEngine процесс-длительный, обычно не сработает. Достаточно.
