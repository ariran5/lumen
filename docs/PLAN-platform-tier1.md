# Lumen — Platform Tier 1 (Phase 6)

Цель: дать fast-app'ам набор device-API без которого "хорошее приложение" не построишь. После закрытия — можно писать заметки, чат, профиль, любой контент-апп.

Подход: один заход, все 7 фич в одну сессию. Каждая ≤ ~80 строк Swift + JS-обёртка через `lumen.*`. Pattern уже устоявшийся (`JSEngine+*.swift` + `installFooBridge()` в `installPlatformBridges()`).

## Скоп

| # | API | Реализация | Сложность |
|---|---|---|---|
| 1 | `lumen.clipboard.{copy,paste,has}` | UIPasteboard.general | trivial |
| 2 | `lumen.linking.{open,canOpen}` | UIApplication.shared.open | trivial |
| 3 | `lumen.share({text,url})` | UIActivityViewController | small |
| 4 | `lumen.actionSheet({title,actions,onSelect})` | UIAlertController.actionSheet | small |
| 5 | `lumen.secureStorage.{get,set,remove}` | Security/SecItem | medium |
| 6 | `lumen.imagePicker.pick({source})` → `Promise<{uri,w,h}>` | PHPickerViewController, copy → tmp file | medium |
| 7 | `lumen.ws(url, {onOpen,onMessage,onClose,onError})` | URLSessionWebSocketTask | medium |

## Соглашения API

- **Promise-based для async** (image picker). Pattern из fetch: native принимает `(resolve, reject) -> Void`, JS обёртка строит Promise.
- **Callback-based для streams** (websocket). Возвращает handle с `send/close`.
- **Sync для простых** (clipboard, secure storage get) — `@convention(block) (String?) -> String?`.
- **UI-presentation** (share, action sheet, image picker) — через `TopViewController.find()`.
- **Permissions inline в JS** — если iOS просит permission, system prompt; ошибки рейзятся как reject в Promise или onError callback.

## Acceptance

- Все 7 API доступны как `lumen.*`
- В `packages/lumen-types/index.d.ts` есть типы
- `Examples/PlatformLab` использует каждое и показывает рабочий результат на симуляторе
- ROADMAP.md обновлён Phase 6 closure

## Что НЕ входит (отложено)

- Camera capture (отдельно от picker) — Tier 3
- Document picker (Files app) — Tier 3
- Audio/Video — Tier 3

---

# Tier 2 — Phase 9

Следующий заход. Без этого нельзя сделать "серьёзный" app (не demo).

## Скоп

| # | API | Реализация | Сложность | Статус |
|---|---|---|---|---|
| 1 | `lumen.appState` reactive (`'active'\|'background'\|'inactive'`) | UIApplication notifications → signal | small | ✓ done |
| 2 | `lumen.appearance.theme` reactive (`'dark'\|'light'`) | UIWindowScene.registerForTraitChanges (iOS 17+) | small | ✓ done |
| 3 | `lumen.network.{online, type}` reactive | NWPathMonitor → signal | small | ✓ done |
| 4 | `lumen.biometrics.authenticate(reason) → Promise<bool>` | LAContext.evaluatePolicy | small | ✓ done |
| 5 | `lumen.biometrics.available() → 'faceID'\|'touchID'\|'none'` | LAContext.canEvaluatePolicy | trivial | ✓ done |
| 6 | Pull-to-refresh на ScrollView (`onRefresh: () => Promise`) | UIRefreshControl + thenable-await на LumenScrollView | medium | ✓ done |
| 7 | `lumen.statusBar.style({theme, hidden})` | preferredStatusBarStyle override через UIViewController | small | ✓ done |
| 8 | `lumen.notifications.schedule({title, body, at}) → id` (local only) | UNUserNotificationCenter — request, add | medium | ✓ done |
| 9 | `lumen.notifications.requestPermission() → Promise<'granted'\|'denied'>` | UNUserNotificationCenter.requestAuthorization | small | ✓ done |
| 10 | `lumen.notifications.onTap.subscribe(fn)` | UNUserNotificationCenterDelegate didReceive | medium | ✓ done |
| 11 | Deep links — incoming URL → `lumen.linking.onIncoming.subscribe(fn)` | SwiftUI `.onOpenURL` → IncomingURLStore → NativeNotifier | medium | ✓ done |

## Группировка по подзаходам

**Заход A — reactive signals (1-3):** lifecycle + theme + network. Все три читаются как signal'ы, инфра `NativeNotifier` готова, делается одним коммитом. ~150 LOC, ~3 файла. ✓ **закрыт (2026-05-13, session 011)** — JSEngine+{Lifecycle,Appearance,Network}.swift; signal-backed getters в CoreFramework (по образцу `safeArea`, не через subscribe-канал — скаляры читаются как `lumen.appState` без явного subscribe); PlatformLab карточки AppState/Theme/Network реактивно обновляются на устройстве. См. [sessions/011-2026-05-13-tier2-zahod-a-reactive-signals.md](../sessions/011-2026-05-13-tier2-zahod-a-reactive-signals.md).

**Заход B — biometrics + pull-to-refresh + status bar (4-7):** UX-апгрейд для типичных app'ов. Не блокеры друг друга, но размер сопоставимый. ~250 LOC. ✓ **закрыт (2026-05-13, session 012)** — JSEngine+{Biometrics,StatusBar}.swift + onRefresh/refreshing на LumenScrollView через UIRefreshControl. NSFaceIDUsageDescription добавлен в Info.plist. PlatformLab карточки Biometrics / Pull-to-refresh / StatusBar работают. См. [sessions/012-2026-05-13-tier2-zahod-b-biometrics-refresh-statusbar.md](../sessions/012-2026-05-13-tier2-zahod-b-biometrics-refresh-statusbar.md).

**Заход C — local notifications + deep links (8-11):** ✓ **закрыт (2026-05-14, session 013)** — JSEngine+Notifications.swift (singleton UNUserNotificationCenterDelegate; `_consumeTaps` drain в JS), IncomingURLStore + SwiftUI `.onOpenURL` (без AppDelegate/SceneDelegate); `lumen://` URL scheme в Info.plist; CoreFramework JS-обёртки `notifications.{requestPermission,schedule}` Promise + `onTap.subscribe` / `linking.onIncoming.subscribe` через generic notify-каналы. APNS (remote push) и Universal Links (https://) **отложены до Tier 2.5** — требуют entitlements / certs / associated-domains, отдельная Apple-side инфра. См. [sessions/013-2026-05-14-tier2-zahod-c-notifications-deep-links.md](../sessions/013-2026-05-14-tier2-zahod-c-notifications-deep-links.md).

## Acceptance

- Tier 2 Lab — `Examples/Tier2Lab/` (или расширить PlatformLab) — карточка per API
- Type definitions в `packages/lumen-types/index.d.ts`
- ROADMAP.md обновлён P9 closure
- E2E проверено на iPhone

## Рекомендуемая последовательность

A → B → C. После A появляется реактивный системный context, который дальше использует всё остальное (например biometrics диалог проверяет theme, и т.п.). C последним потому что инфра-зависимостей больше (entitlements/delegates).

---

# Tier 2.5 — Apple-side infra (backlog)

Фичи, которые блокируются capability/entitlement/сертификат-возня на стороне Apple. Код в самом app'е дешёвый — основной cost ops/devops.

| API | Что нужно | Когда делать |
|---|---|---|
| **APNS (remote push)** | `aps-environment` entitlement, APNS .p8 на сервере, `UIApplicationDelegate.didRegister...DeviceToken`, JS API `lumen.notifications.deviceToken()` / `onDeviceTokenChange.subscribe(fn)`, background fetch | Когда конкретный fast-app нуждается в server push'ах |
| **Universal Links (https://)** | `applinks:domain` entitlement, `apple-app-site-association` JSON на target домене, тот же `linking.onIncoming.subscribe` ловит UL | Когда нужен seamless web→app переход (например shared link открывается в native app'е) |

---

# Tier 3 (на потом)

Не блокеры реального продакшена, но добавляют классы приложений:

- **Camera capture** (отдельно от picker) — для сканеров/QR. `AVCaptureSession` или `UIImagePickerController(camera)`. Требует `NSCameraUsageDescription`.
- **Document picker** — `UIDocumentPickerViewController`. Files app, iCloud Drive, sharing с другими app'ами.
- **Audio player** — `AVAudioPlayer` через `lumen.audio.play(uri)`. Recorder — `AVAudioRecorder`.
- **Video player** — `<Video src=…/>` primitive поверх `AVPlayerLayer`.
- **Sensors** — `CMMotionManager` (gyro / accelerometer / motion). Для AR/игр.
- **HealthKit** — `HKHealthStore`. Узкий сегмент, но без альтернативы.
- **Bluetooth/BLE** — `CBCentralManager`.
- **In-App Purchase** — `StoreKit 2`. Required для платных fast-app'ов.
- **Sign in with Apple** — `ASAuthorizationController`. Иногда обязателен по App Store guidelines.
- **Mail/SMS/Phone composers** — `MFMailComposeViewController` / `MFMessageComposeViewController` / `tel:` через linking уже работает.
