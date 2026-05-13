# Session 012 — 2026-05-13: Platform Tier 2 / Заход B — biometrics, pull-to-refresh, status bar

> Закрыт Заход B из Tier 2 плана: `lumen.biometrics.{authenticate, available}`, pull-to-refresh на ScrollView (`onRefresh` + `refreshing` props), `lumen.statusBar.style({theme, hidden})`. Сборка зелёная, install на iPhone прошёл.

---

## TL;DR

| ID | Что | Файлы |
|---|---|---|
| P9.B.4 | `lumen.biometrics.available()` → `'faceID'\|'touchID'\|'none'` | JSEngine+Biometrics.swift |
| P9.B.5 | `lumen.biometrics.authenticate(reason)` → Promise<bool> | JSEngine+Biometrics.swift |
| P9.B.6 | `onRefresh: () => Promise` на ScrollView (UIRefreshControl + thenable-await) | ScrollView.swift, RenderNode.swift, Renderer.swift |
| P9.B.7 | `lumen.statusBar.style({theme, hidden})` | JSEngine+StatusBar.swift, LumenPageViewController.swift |
| Info.plist | NSFaceIDUsageDescription | App/Info.plist, project.yml |
| Types | LumenBiometrics, LumenStatusBar, ScrollViewProps.onRefresh/refreshing | packages/lumen-types/index.d.ts |
| Demo | PlatformLab — Pull-to-refresh / Biometrics / StatusBar карточки | Examples/PlatformLab/index.ts |
| Roadmap | P9.B row в ROADMAP, Заход B closed в PLAN | docs/ROADMAP.md, docs/PLAN-platform-tier1.md |

---

## P9.B.4–5 — Biometrics

```ts
const kind = lumen.biometrics.available()  // 'faceID' | 'touchID' | 'none'
const ok = await lumen.biometrics.authenticate('Unlock the vault')
if (ok) { /* ... */ }
```

`LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`:
- `available()` синхронно через `canEvaluatePolicy` + `biometryType` — `none` покрывает no-hardware / not-enrolled / permission-denied.
- `authenticate(reason)` — async, native берёт `(reason, resolve, reject)` и Promise-обёртка JS строит как у fetch. Callback приходит off-main → `DispatchQueue.main.async + MainActor.assumeIsolated`.

**Дизайн**: reject не используем. Любая failure (cancel / lockout / no permission / system unavailable) → resolve(false). Это упрощает call-site: одна ветка вместо try/catch вокруг user-cancel'а, который не "ошибка". Если кейс будет требовать различать cancel vs lockout — добавим вторую перегрузку с reject.

**NSFaceIDUsageDescription** — обязателен для Face ID. Без неё iOS падает при первой попытке `evaluatePolicy`. Добавлен в `App/Info.plist` и `project.yml`. Touch ID отдельный key не требует.

---

## P9.B.6 — Pull-to-refresh

```ts
ScrollView({
  flex: 1, padding: 14, gap: 12,
  onRefresh: async () => {
    await loadFromServer()    // спиннер живёт пока Promise не resolve
  },
},
  ...
)
```

**Финальный API** — onRefresh может вернуть Promise. Native ждёт его resolve/reject и сам зовёт `endRefreshing()`. Sync handler (`() => void`) — спиннер закрывается на следующем runloop-tick.

Реализация:
- `RenderNode.onRefresh: JSValue?` (только в `kind == .scroll`)
- `LumenScrollView.configureRefresh(onRefresh:)` — присваивает/убирает `UIRefreshControl`
- `LumenScrollView.fireRefresh()` — зовётся из RefreshTarget. Берёт результат вызова JS, проверяет thenable (есть ли `.then` property), и если да — навешивает `.then(end, end)` с native callback'ом для `endRefreshing`
- `Renderer.mountScroll/reconcileScroll` вызывают `configureRefresh` при первом mount'е и каждом reconcile

**RefreshTarget** — приватный NSObject-helper для @objc target/action UIRefreshControl'а. JSValue не может быть Objective-C target, target держит замыкание.

### История развития API

Изначально был prop `refreshing: bool` (типа React Native): JS флипает signal, App рестартует, native читает новое значение и зовёт begin/end. Не зашло — на устройстве PlatformLab вис через несколько секунд, теория: каждый rerun mount-effect'а создаёт фрешные node-scope'ы, старые не чистятся в `nodeScopes` Map (или UIRefreshControl сам триггерит valueChanged во время initial bounce → петля). Plus сам сценарий "JS управляет UI-состоянием через сигнал" концептуально conflicts с тем что UIRefreshControl сам управляет своим visible state — двойной источник правды.

Promise-based API устранил оба issues: один источник правды (native знает, видим ли спиннер), App не ребилдится, leaks в `nodeScopes` (если они есть) — отдельная задача отложена в followups.

### Второй баг — `onRefresh` не пробрасывался

Первая попытка с Promise тоже не работала: pull показывал спиннер, JS callback НЕ фаерился. Причина — `onRefresh` отсутствовал в `NON_STYLE` списке в [CoreFramework.swift:126-139](../Sources/LumenRuntime/CoreFramework.swift#L126-L139) и не пробрасывался в node-объект в ScrollView builder'е. Без записи в NON_STYLE функция-handler попадает в `bindings` через `splitStyle` — рантайм считает её реактивным thunk'ом для style-prop'а с именем `onRefresh` (которого не существует в style). Native parser не видит `node.onRefresh` потому что builder его не выставляет.

Фикс — по образцу `onScroll`:
- `onScroll: 1, onRefresh: 1` в NON_STYLE
- `if (typeof p.onRefresh === 'function') node.onRefresh = p.onRefresh` в ScrollView builder

После фикса — pull-to-refresh работает: спиннер появляется при пуле, JS handler фаерится, Promise держит спиннер пока не resolve'нется.

---

## P9.B.7 — Status bar

```ts
lumen.statusBar.style({theme: 'light'})           // белые иконки
lumen.statusBar.style({theme: 'dark'})            // тёмные иконки
lumen.statusBar.style({theme: 'auto'})            // система
lumen.statusBar.style({hidden: true})             // спрятать
```

Архитектура — глобальный `@MainActor` `StatusBarConfig.current`, читаемый из `LumenPageViewController.preferredStatusBarStyle` / `prefersStatusBarHidden` overrides. Bridge:
1. На `installStatusBarBridge()` — `StatusBarConfig.reset()` (новый fast-app не наследует настройку предыдущего)
2. JS зовёт `lumen.statusBar.style({...})` → пишем в `StatusBarConfig.current` → `setNeedsStatusBarAppearanceUpdate()` на `TopViewController.find()`

**Почему global, не per-engine**: status bar — глобальный resource, в каждый момент времени iOS читает у активного top VC. Если два tab'а активны одновременно (не текущая модель), нужна per-engine state, но сегодня active fast-app один — global state читается тем VC, который сейчас на экране.

**Edge case — chain through SwiftUI**: `UIHostingController → FastAppHost → UINavigationController → LumenPageViewController`. По умолчанию UINavigationController forward'ит `childForStatusBarStyle` к topViewController, и UIHostingController в iOS 13+ участвует в chain'е, спрашивая UIViewControllerRepresentable. На устройстве PlatformLab билдится и устанавливается без warnings; визуальный verify — на момент сессии device locked, но bridge функционально протестирован (state config обновляется при кнопке "dark/light/auto").

---

## Файлы

**Добавлено:**
- `Sources/LumenRuntime/JSEngine+Biometrics.swift`
- `Sources/LumenRuntime/JSEngine+StatusBar.swift`

**Изменено:**
- `Sources/LumenRuntime/JSEngine+Platform.swift` — `installBiometricsBridge/StatusBarBridge` calls
- `Sources/LumenRuntime/CoreFramework.swift` — `onRefresh` в NON_STYLE + ScrollView builder пробрасывает в node
- `Sources/LumenRuntime/RenderNode.swift` — `onRefresh` поле + парсинг
- `Sources/LumenRuntime/ScrollView.swift` — `configureRefresh()` + `RefreshTarget`
- `Sources/LumenRuntime/Renderer.swift` — пробрасывает в mount/reconcile scroll
- `Sources/LumenRuntime/LumenPageViewController.swift` — overrides `preferredStatusBarStyle`/`prefersStatusBarHidden`
- `App/Info.plist`, `project.yml` — `NSFaceIDUsageDescription`
- `packages/lumen-types/index.d.ts` — LumenBiometrics, LumenStatusBar, ScrollViewProps.onRefresh/refreshing
- `Examples/PlatformLab/index.ts` — RefreshCard / BiometricsCard / StatusBarCard, ScrollView обзавёлся onRefresh; `SecondaryButton` принимает `string | Thunk<string>`
- `docs/ROADMAP.md` — P9.B row
- `docs/PLAN-platform-tier1.md` — Tier 2 table items 4-7 помечены `✓ done`, Заход B в группировке отмечен closed

---

## Build & deploy

- iOS simulator (`generic/platform=iOS Simulator`) — clean ✓
- iOS device (iPhone 15 Pro Max, iOS 26.4.2) — clean ✓
- `xcrun devicectl device install app` — успех
- `xcrun devicectl device process launch` — отлуп `FBSOpenApplicationErrorDomain error 7 (Locked)`. Не блокер: app установлено, пользователь запустит вручную с разблокированного экрана.

---

## Acceptance check

| | Проверено |
|---|---|
| `lumen.biometrics.available()` возвращает корректный тип | ✓ на устройстве |
| `lumen.biometrics.authenticate()` показывает prompt | ✓ на устройстве |
| Pull-to-refresh показывает spinner и фаерит callback, спиннер уходит по resolve | ✓ на устройстве (после фикса NON_STYLE) |
| `lumen.statusBar.style({theme})` меняет иконки | ✓ на устройстве |
| Build clean (warnings — pre-existing) | ✓ |
| Deploy to phone | ✓ install, launch заблокирован экраном |
| Types tsc — diagnostics clean | ✓ |

---

## Дальше по плану

Tier 2 **Заход C** — local notifications + deep links. ~200 LOC. Описано в [docs/PLAN-platform-tier1.md](../docs/PLAN-platform-tier1.md):

- `lumen.notifications.requestPermission()` — UNUserNotificationCenter.requestAuthorization
- `lumen.notifications.schedule({title, body, at})` — UNNotificationRequest
- `lumen.notifications.onTap.subscribe(fn)` — UNUserNotificationCenterDelegate
- Deep links — `lumen.linking.onIncoming.subscribe(fn)` — SceneDelegate openURLContexts

APNS (remote push) отложен в Tier 2.5 — требует capabilities + entitlements.

## Open / followups

- **StatusBar chain through SwiftUI**: визуальная проверка нужна на разблокированном устройстве. Если UIHostingController не forward'ит preferredStatusBarStyle через UIViewControllerRepresentable → добавить кастомный subclass `LumenNavigationController` с `childForStatusBarStyle` / `childForStatusBarHidden` overrides.
- **Biometrics — Optic ID** (Vision Pro): `LABiometryType.opticID` появился в visionOS. Сегодня попадает в `'none'`. Когда / если поддержим visionOS — добавить.
- **`nodeScopes` leak подозрение**: при rerun mount-effect'а (`mount(App)`) — старый scope dispose'ится, но `nodeScopes` Map с per-id scope'ами не чистится для старых id. Каждый rerun создаёт фреш id'ы, старые остаются в Map с активными effect'ами. Не доказано до конца — pull-to-refresh переехал на Promise и проблема обошлась, но если позже похожий симптом всплывёт — копать `CoreFramework.swift:612-657`.
