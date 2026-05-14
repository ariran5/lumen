# Session 015 — 2026-05-14: iOS 26 sheet polish + per-prop reactivity flicker fix + Sandbox Blocks 3/4/5

> Большая прокачка одной сменой. Сначала довели до ума iOS 26 bottom sheet, потом нашли и исправили flicker per-prop реактивности (был проявлен на TabBar BankApp'а). Под конец закрыли три блока Phase 6 sandbox roadmap'а: permissions, HTTPS-only, storage quotas.

---

## TL;DR

| Часть | Что | Файлы | Commit |
|---|---|---|---|
| iOS 26 sheet | VC.view прозрачен; контент рендерится ровно один раз на medium-bounds; sheet растёт вокруг застывшего контента — без рывков от explicit-CALayer-position snap'ов | BottomSheetViewController.swift, JSEngine+Platform.swift (убран preferredCornerRadius, prefersGrabberVisible=true), TopViewController.swift (walk через children) | `0141cdb` |
| Reactivity fix | Reconcile для same-id узла — `applyGeometryOnly` вместо `applyAll` (не переписываем визуальные стили из stale lastTree); `updateMountedNode` сохраняет mount.node для same-id; JSEngine+Patch обновляет `mount.node.style` для всех patch case'ов | Renderer.swift, JSEngine+Patch.swift | `0141cdb` |
| ReactivityTests | 13 тестов покрывают signal→thunk→patch→CALayer + регрессию TabBar flicker'а | Tests/ReactivityTests.swift | `0141cdb` |
| Block 3 — permissions | Capability + Grant + PermissionStore (UserDefaults sticky) + PermissionPrompt (UIAlertController) + JS API `lumen.permissions.{status,request,revoke}`; gate'нуты notifications / biometrics / imagePicker bridges | Permission.swift, PermissionStore.swift, PermissionPrompt.swift, JSEngine+Permissions.swift; modified JSEngine+{Notifications,Biometrics,ImagePicker}.swift; PermissionTests.swift (10) | `4910dc7` |
| Block 4 — HTTPS-only | SecurityPolicy.denyReason (HTTPS/lumen allow, HTTP только local: 127.x / *.local / RFC1918); Developer Mode flag (UserDefaults); BundleLoader.load бросает BundleLoadError.insecureScheme до network'а | SecurityPolicy.swift, BundleLoader.swift; SecurityPolicyTests.swift (9) | `b8a6f93` |
| Block 5 — Storage quotas | StorageQuota.parse + currentUsage + denyReason; JSEngine+Storage.set бросает JS exception при overflow; OriginContext.storageQuota из манифеста; 100MB default, 1GB hardMax | StorageQuota.swift, OriginContext.swift, JSEngine+Storage.swift; StorageQuotaTests.swift (12) | `b8a6f93` |

Всего за сессию **44 новых теста** (13 ReactivityTests + 10 PermissionTests + 9 SecurityPolicyTests + 12 StorageQuotaTests).

---

## iOS 26 bottom sheet polish

Юзер жаловался: sheet прыгает на drag'е, contents мелькают на threshold'е к .large detent'у. Проблема в нашем Renderer'е: explicit CALayer positions не умеют плавно follow'ить sheet morph — получаются snap'ы.

Зафиксили двумя путями:
1. **Render-once approach**: `BottomSheetViewController.viewDidLayoutSubviews` рендерит контент ровно один раз на первом valid bounds (medium detent). Sheet вырастает вокруг застывшего контента. Trade-off: на `.large` детенте под кнопкой остаётся пустое место — юзер согласился.
2. **iOS 26 morph artifacts**: исчезновение Liquid Glass touch halo + малый snap на threshold к `.large` — это **iOS, не наш bug**. Подтверждено через standalone SheetTest проект (`/Users/arian/Desktop/SheetTest/`) — чистый UIKit ведёт себя ИДЕНТИЧНО. Memory notes [project-ios26-sheet-threshold](.../memory/project_ios26_sheet_threshold.md) и [reference-sheettest-project](.../memory/reference_sheettest_project.md).

---

## Per-prop reactivity flicker fix

### Симптом

В BankApp нижний tab-bar: первый item (Home) **мелькал** при переключении на другие табы. Хак `activeTab.value` в TabBar body «решал» проблему, но непонятно почему.

### Root cause

`Renderer.reconcile` для same-kind же-id узла безусловно зовёт `applyAll(layer, mount, node: next, ...)`, который через `applyTextStyle` пересчитывает `layer.string` из **`next.style.color`**.

`next` приходит из `lastTree`. `lastTree.TabBar` зафиксирован с активным Home (когда TabBar строился впервые). Per-prop color thunk'и обновляют `mount.node.style.color` через `lumen._patchProp`, но **lastTree не трогается**.

Поток событий на тапе History:
1. activeTab signal меняется → 9 effect'ов в `pendingEffects` (Set, insertion-order).
2. First slot effect (tab content) fires first → `_replaceChildren` → `relayout()` → `reconcile` обходит **всё дерево**, в том числе tab-bar subtree.
3. Для tab-bar Text'ов `applyAll` ставит `layer.string` со СТАЛЫМ цветом (Home=#FFFFFF, остальные=inactive) — текущий visible state не меняется, но layer.string «фиксируется» на stale значении.
4. Color effect'ы фаерят `_patchProp(id, color, newColor)` → правильные цвета приземляются.
5. Между шагами 2-4 commit'ы CATransaction'ов могут попасть на разные display frame'ы → мелькание Home (он единственный кто «менялся» от active→inactive в layer.string).

### Fix

В `Renderer.reconcile`: для same-id узла (`mounted.node.id == next.id`) — вместо `applyAll` зовём новый `applyGeometryOnly`. Он применяет только geometry + gestures + text-content-sync (для patchText flow). **Визуальные стили (color/bg/opacity/border) НЕ переприменяются** — они либо положены mount'ом изначально, либо обновлены per-prop patch'ем; stale lastTree не fight'ит.

`updateMountedNode` для same-id больше не overwrite'ает `mount.node` целиком — синкает только `text` / `source`. Это сохраняет в `mount.node.style` patched значения между relayout'ами.

JSEngine+Patch теперь обновляет `mount.node.style.*` для ВСЕХ patch case'ов (раньше только `color` это делал) — чтобы будущие state-read'ы (например attributed string regeneration на color patch) видели current values.

### Tests

13 ReactivityTests:
- **testSiblingSlotRebuildPreservesPerPropPatchedColor** — точная регрессия на TabBar bug. Slot A пересобирается по signal'у, Slot B держит Text с color thunk. До фикса цвет переписывался.
- All-siblings, computed, batched changes, show/hide reattach, deep nested, mixed static+reactive, outer signal rebuild, text content patching.

Один грабь: bridge'и капчурят `[weak renderer]` — если в тесте `let (_, _, root) = makeFixture()` сделать с `_` вместо binding'а, renderer теряется и patches no-op'ятся.

---

## Sandbox Block 3 — Per-origin permission system

Двухслойная модель: OS → Lumen, Lumen → app per origin. Без Lumen-уровня untrusted origin мог бы триггерить системный Face ID prompt с произвольным текстом — phishing vector.

### Capability + Grant

```swift
enum Capability: String, CaseIterable {
    case notifications, biometric, camera, microphone, photos, location, contacts
}
enum Grant: String { case granted, denied, prompt }
```

`camera` / `microphone` раздельно — apps просящие только camera не получают mic бонусом (типичный mistake в браузерах).

### PermissionStore

UserDefaults-backed. Ключ `lumen.permissions.<origin.shortHash>.<capability>` → `"granted"` / `"denied"`. Отсутствие ключа = `.prompt`.

```swift
@MainActor final class PermissionStore {
    static let shared = PermissionStore()
    func status(origin:capability:) -> Grant
    func set(origin:capability:grant:)
    func revoke(origin:capability:)
    func clear(origin:)  // wipe всех grant'ов для origin'а
    func request(origin:capability:) async -> Grant  // show prompt if needed
}
```

### PermissionPrompt

UIAlertController через `TopViewController.find()`. Title: `"<origin.host> wants to <capability.displayName>"`. Buttons: «Allow» (default), «Don't Allow» (preferredAction — давит на cautious path при случайном Enter'е).

### JS API

```ts
lumen.permissions.status(capability): 'granted' | 'denied' | 'prompt'
lumen.permissions.request(capability): Promise<'granted' | 'denied'>
lumen.permissions.revoke(capability): void
```

### Gated bridges

- **JSEngine+Notifications.requestPermission** — `PermissionStore.request(.notifications)` → если denied, return 'denied' без OS-вызова. Если granted → `UNUserNotificationCenter.requestAuthorization` (OS может всё ещё отказать — это отдельный layer).
- **JSEngine+Biometrics.nativeAuth** — gate перед `LAContext.evaluatePolicy`. Защищает от phishing-промптов с произвольным reason.
- **JSEngine+ImagePicker.nativePick** — gate `.photos` перед PHPickerViewController. PHPicker технически работает без NSPhotoLibraryUsageDescription (out-of-process), но мы всё равно gate'им — origin должен явно подтвердить.

### Tests (10)

Fresh-origin defaults / set+get roundtrip / per-origin isolation / scheme не leak'ает (http vs https — разные origin'ы) / revoke возвращает в .prompt / clear wipes per-origin / request shortcuts on existing decision.

---

## Sandbox Block 4 — HTTPS-only + Developer Mode

`SecurityPolicy.denyReason(forBundleURL:)` allow-list'ит:
- `https://` всегда
- `lumen://` (builtin fast-apps)
- HTTP — **только** local: `localhost` / `127.0.0.0/8` / `*.local` (mDNS) / RFC1918 (`10/8` / `172.16-31` / `192.168/16`)

`isPrivateIPv4` тщательно: не путает `172.15.x` / `172.32.x` (не RFC1918) с `172.16-31` (RFC1918). `169.254.x` (link-local) не allow'ится — не RFC1918, риски не нужны.

`SecurityPolicy.isDeveloperMode` — `UserDefaults.bool(forKey: "lumen.developerMode")`. Когда true — полностью отключает gate (для ngrok / preview-доменов с самоподписанными сертификатами). Settings UI добавится в Block 6.

`BundleLoader.load` зовёт `SecurityPolicy.denyReason` ДО любого network request'а — даже probe не делаем по untrusted URL. Бросает `BundleLoadError.insecureScheme(reason)` с human-readable сообщением для шелла.

### Tests (9)

HTTPS / lumen pass, public HTTP denied, local exceptions (localhost / 127.x / *.local / RFC1918), public lookalikes still denied (172.15.x / 172.32.x / 169.254.x), Developer Mode override.

---

## Sandbox Block 5 — Per-origin storage quotas

### Tracking + parsing

```swift
enum StorageQuota {
    static let defaultBytes = 100 * 1024 * 1024  // 100MB per origin
    static let hardMaxBytes = 1 * 1024 * 1024 * 1024  // 1GB cap для manifest override
    
    static func parse(_ raw: String?) -> Int?  // "100MB" / "1GB" / "1024" / raw bytes
    static func currentUsage(prefix:) -> Int   // UTF-8 bytes по UserDefaults prefix
    static func denyReason(prefix:keyWithPrefix:newValue:limit:) -> String?
    @MainActor static func limit(for context: OriginContext) -> Int
}
```

`denyReason` учитывает overwrite: если ключ уже занят, его старые байты считаются освобождёнными при записи нового значения. Без этого `set('k', 'a' * 50)` потом `set('k', 'a' * 60)` ложно превышало бы лимит дважды.

### Enforcement

`JSEngine+Storage.set` зовёт `StorageQuota.denyReason`. При overflow — `ctx.exception = JSValue(newErrorFromMessage:...)` → JS получает обычный `try/catch`'абельный error, данные **не сохраняются молча**.

### OriginContext.storageQuota

Парсится в `applyManifest` из `manifest.storage_quota`. Manifest может попросить только до 1GB; больше — будущий permission upgrade flow (TODO для Block 3 enhanced).

### Tests (12)

Parser (suffixes / raw / garbage / cap), usage (zero / sum-key+value / multiple entries / prefix isolation), denyReason (allow within / reject over / overwrite math / new-key overflow).

---

## Test isolation flake

`testAllSiblingThunksOnSameSignalFire` иногда падает в полном test suite, но всегда зелёный в isolation. Корень: `Renderer.nodeIndex` — process-global static. Lumen app launches как XCTest host, его renderer тоже популирует nodeIndex параллельно с тестовым → редкая race. Не блокирует, отмечено для будущего разбора.

---

## Что осталось в Phase 6

- ✓ Block 1: Foundation (Origin + OriginContext) — session 014
- ✓ Block 2: Network policy — commit `89d79ea`
- ✓ Block 3: Permission system — **session 015**
- ✓ Block 4: HTTPS-only + Developer Mode — **session 015**
- ✓ Block 5: Storage quotas — **session 015**
- ⏳ Block 6: Multi-app shell — частично в session 016 (TabRuntime + StartSheet), остаются manifest integrity / background pause / settings UI / memory eviction
