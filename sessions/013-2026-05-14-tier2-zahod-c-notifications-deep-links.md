# Session 013 — 2026-05-14: Platform Tier 2 / Заход C — local notifications + deep links

> Закрыт Заход C из Tier 2: `lumen.notifications.{requestPermission, schedule, cancel, cancelAll, onTap}` + `lumen.linking.onIncoming`. Universal Links (https://) и APNS (remote push) — backlog Tier 2.5 (требуют Apple-side capabilities + cert/entitlement-возни).

---

## TL;DR

| ID | Что | Файлы |
|---|---|---|
| P9.C.8 | `lumen.notifications.schedule({title, body, at}) → Promise<id>` (local) | JSEngine+Notifications.swift |
| P9.C.9 | `lumen.notifications.requestPermission() → Promise<'granted'\|'denied'>` | JSEngine+Notifications.swift |
| P9.C.10 | `lumen.notifications.onTap.subscribe(fn)` | JSEngine+Notifications.swift + CoreFramework |
| P9.C.11 | `lumen.linking.onIncoming.subscribe(fn)` (deep link incoming URLs) | IncomingURLStore.swift, LumenApp.swift, JSEngine+Linking.swift |
| Info.plist | `CFBundleURLTypes` — `lumen://` scheme | App/Info.plist, project.yml |
| Types | LumenNotifications, LumenLinking.onIncoming | packages/lumen-types/index.d.ts |
| Demo | PlatformLab — NotificationsCard + DeepLinkCard | Examples/PlatformLab/index.ts |
| Roadmap | P9.C row в ROADMAP, Заход C closed в PLAN; Tier 2.5 раздел для UL+APNS | docs/ROADMAP.md, docs/PLAN-platform-tier1.md |

---

## P9.C.8-10 — Notifications

```ts
const status = await lumen.notifications.requestPermission()   // 'granted' | 'denied'
const id = await lumen.notifications.schedule({
  title: 'Lumen lab',
  body: 'Tap me',
  at: Date.now() + 5000,
})
const unsub = lumen.notifications.onTap.subscribe((id) => { /* ... */ })
lumen.notifications.cancel(id)
lumen.notifications.cancelAll()
```

### Архитектура

`UNUserNotificationCenter` — singleton-на-процесс. Его `.delegate` тоже один на процесс. Поэтому `LumenNotificationDelegate.shared` — global, не per-engine.

- **Permission** — `requestAuthorization(options: [.alert, .sound, .badge])`. iOS показывает prompt один раз; повторный вызов сразу возвращает текущий статус.
- **Schedule** — `UNTimeIntervalNotificationTrigger` (минимум 1с). `at` — unix ms; если меньше `now+1s` или отсутствует, делается `now+1s` минимум (требование Apple).
- **onTap** — singleton-делегат пушит id в `pendingTaps`, фаерит `NativeNotifier.fire("notifications.tap")`. JS-wrapper в CoreFramework на каждый fire вычитывает `_consumeTaps()` и зовёт callback по каждому id'у. **Cold-launch кейс** (app убит, юзер тапнул нотификацию → iOS launch'ает app): delegate срабатывает _до_ того как JS подпишется, id оседает в `pendingTaps`; при subscribe `drain()` вычитывает накопившееся. Поэтому никогда не теряем launch-from-notification event.
- **Foreground banner** — `willPresent` возвращает `[.banner, .sound, .badge]`, чтобы нотификации показывались даже когда app открыт (по умолчанию iOS их гасит в foreground'е). Для PlatformLab demo это нагляднее.

### Sendable / Swift 6 strict concurrency

`UNUserNotificationCenterDelegate` методы — `nonisolated` (вызываются с произвольных очередей). Не размечать делегат `@MainActor` — Swift 6 не пускает. Решение:

- Класс `LumenNotificationDelegate: NSObject, ..., @unchecked Sendable` (`@unchecked` потому что `pendingTaps` синхронизирован тем что мы трогаем его только из main).
- `pendingTaps` помечен `@MainActor`.
- В `didReceive` сразу зовём `completionHandler()` (Apple требует ASAP), а работу с pendingTaps делаем через `DispatchQueue.main.async + MainActor.assumeIsolated`. Race-free: completionHandler не захвачен в main-actor closure.

Первая попытка с дозоном completionHandler **внутри** main-блока:

```swift
DispatchQueue.main.async {
  MainActor.assumeIsolated { ... }
  completionHandler()   // ← Error: sending 'completionHandler' risks causing data races
}
```

Swift 6 запрещает task-isolated `@escaping () -> Void` пересекать `@MainActor`-границу. Фикс — фаер сразу синхронно:

```swift
DispatchQueue.main.async { MainActor.assumeIsolated { ... } }
completionHandler()
```

---

## P9.C.11 — Deep links

```ts
const unsub = lumen.linking.onIncoming.subscribe((url) => {
  // url: 'lumen://hello'
})
```

### Архитектура

SwiftUI app без AppDelegate / SceneDelegate. Для приёма URL используется декларативный `.onOpenURL { url in ... }` модификатор на корневой View.

```swift
WindowGroup {
  ContentView().onOpenURL { url in
    IncomingURLStore.shared.enqueue(url.absoluteString)
  }
}
```

`IncomingURLStore` — global `@MainActor` singleton с:
- `pending: [String]` — очередь
- `enqueue(_:)` — добавить + `NativeNotifier.fire("linking.incoming")`
- `consume()` — drain + clear

Cold-start кейс: если URL пришёл до того как JS bundle загрузился — он копится в `pending`, при первом `subscribe(fn)` JS-обёртка делает `drain()` (читает `_consumePending`), и URL'ы доставляются.

### URL scheme registration

В `Info.plist` (+ `project.yml`):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.lumen.browser</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>lumen</string>
    </array>
  </dict>
</array>
```

Без декларации схемы `lumen://...` из Safari не открыли бы наш app.

---

## Generic паттерн push-каналов

`onTap` и `onIncoming` используют один и тот же подход:

1. Native накопляет события в `pending` массиве.
2. На событие — `NativeNotifier.fire(channel)`.
3. Все живые JSEngine'ы получают `dispatchNotify(channel:)` → зовут зарегистрированные callback'и **без аргументов** (`mv.value?.call(withArguments: [])`).
4. JS-callback дёргает native `_consumeXxx()` и сам распределяет.

Тот же шаблон что у `lumen.history.subscribe` и `lumen.tabs.subscribe` — generic native push-канал, JS сам ходит за деталями. Удобно: `dispatchNotify` не нужен `Sendable`-аргументы (Swift 6 strict не пустил бы).

---

## Файлы

**Добавлено:**
- `Sources/LumenRuntime/JSEngine+Notifications.swift`
- `Sources/LumenRuntime/IncomingURLStore.swift`

**Изменено:**
- `Sources/LumenRuntime/JSEngine+Platform.swift` — `installNotificationsBridge()` в `installPlatformBridges()`
- `Sources/LumenRuntime/JSEngine+Linking.swift` — добавлен `_consumePending` блок
- `Sources/LumenRuntime/CoreFramework.swift` — JS-обёртки `lumen.notifications.*` (Promise wrappers + onTap.subscribe) и `lumen.linking.onIncoming.subscribe`
- `App/LumenApp.swift` — `.onOpenURL { IncomingURLStore.shared.enqueue(...) }`
- `App/Info.plist` + `project.yml` — `CFBundleURLTypes` (`lumen://` scheme)
- `packages/lumen-types/index.d.ts` — `LumenNotifications`, `NotificationScheduleConfig`, `LumenLinkingIncoming`; добавлены в `LumenAPI`
- `Examples/PlatformLab/index.ts` — `NotificationsCard`, `DeepLinkCard`, `notifStatus`/`lastTapped`/`incomingURL` signals, top-level `onTap`/`onIncoming` subscriptions
- `docs/ROADMAP.md` — P9.C row + decisions log + Backlog (Universal Links, APNS) + Phase 5 status update
- `docs/PLAN-platform-tier1.md` — Tier 2 items 8-11 ✓ done, Tier 2.5 раздел

---

## Build & deploy

- iOS simulator — clean ✓
- iOS device (iPhone 15 Pro Max, iOS 26.4.2) — clean ✓
- `xcrun devicectl device install app` — успех
- E2E на устройстве: permission prompt → schedule +5s → banner появляется (foreground и lock-screen) → tap фиксирует id → DeepLink self-fire через `lumen://demo?from=lab` → возвращается URL ✓

---

## Acceptance check

| | Проверено |
|---|---|
| `lumen.notifications.requestPermission()` показывает prompt | ✓ на устройстве |
| `lumen.notifications.schedule({at: now+5s})` доставляет banner | ✓ на устройстве |
| Tap на banner фаерит `onTap` callback с id той же нотификации | ✓ на устройстве |
| `lumen.notifications.cancelAll()` чистит pending | ✓ |
| `lumen://demo` через `lumen.linking.open(...)` ловится в `onIncoming` | ✓ на устройстве |
| Build clean (warnings — pre-existing) | ✓ |
| Types tsc — diagnostics clean | ✓ |

---

## Tier 2.5 backlog

Отложены до конкретного use-case'а / готовности Apple-side инфры.

### Universal Links (https://...)
- Associated Domains entitlement (`applinks:example.com`)
- `apple-app-site-association` JSON на target домене (стандартный путь)
- JS-API не меняется — `linking.onIncoming` ловит и UL

### APNS / remote push
- `aps-environment` entitlement (development / production)
- APNS-сертификат или auth-key (`.p8` через JWT) на сервере
- `UIApplicationDelegate.didRegister...DeviceToken` — нужен AppDelegate (`@UIApplicationDelegateAdaptor` поверх SwiftUI App)
- JS API: `lumen.notifications.deviceToken()` / `onDeviceTokenChange.subscribe(fn)`
- Background fetch / silent push — UIBackgroundModes

---

## Дальше по плану

Tier 2 полностью закрыт (Заходы A + B + C). Из плана-документа осталось:

- **Tier 2.5** — Apple-side capabilities (UL + APNS). Делаем по запросу, не плановый.
- **Tier 3** — camera capture / document picker / audio-video / sensors / HealthKit / BLE / IAP / Sign in with Apple / mail-SMS composers.

## Open / followups

- **`nodeScopes` leak** (из P9.B followups) — всё ещё подозрение, не доказано. Не блокер, но если похожий симптом всплывёт — копать `CoreFramework.swift` (`registerBindings` / `_disposeNodes` цикл).
- **`UIApplicationDelegateAdaptor`** — пока не нужен, но если придётся (APNS device token, background fetch) — придётся ввести. Сейчас чистая SwiftUI app.
