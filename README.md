# Lumen

Альтернативный браузер для iOS с двумя движками внутри одной оболочки:

1. **WKWebView** — обычный веб, как в Safari.
2. **Native Runtime** — «быстрые сайты» (fast-apps) рендерятся напрямую через CALayer, layout через свой Flexbox, JS на JavaScriptCore.

Браузер определяет какой движок использовать по манифесту `/.well-known/lumen.json`. Для пользователя — прозрачно, для разработчика fast-app'а — отдельный SDK.

Цель: 120 fps на ProMotion, ощущение нативного приложения, при сохранении возможности открывать любой обычный сайт через WebView.

Подробнее про мотивацию и архитектуру — [docs/IDEA.md](docs/IDEA.md), [docs/PLAN.md](docs/PLAN.md), [docs/ROADMAP.md](docs/ROADMAP.md).

## Структура репозитория

```
.
├── App/                       SwiftUI entry point — LumenApp, ContentView, Info.plist
├── Sources/
│   ├── LumenRuntime/          Fast-app runtime (~50 файлов)
│   │   ├── JSEngine.swift            JavaScriptCore context + bridges
│   │   ├── JSEngine+*.swift          per-domain bridges (Render, Patch, Fetch, …)
│   │   ├── Renderer.swift            CALayer mount/reconcile
│   │   ├── RenderNode.swift          immutable tree representation
│   │   ├── CoreFramework.swift       JS-side @lumen/core: View/Text/signal/mount/Slot/...
│   │   ├── ViewStyle.swift           layer-style → CGColor/borderRadius/...
│   │   ├── ScrollView.swift, VirtualList.swift, BlurView.swift, MapView.swift,
│   │   │   TextInputView.swift       native-view embeds
│   │   ├── BottomSheetViewController.swift, GestureRouter.swift,
│   │   │   AnimationManager.swift    UIKit integration
│   │   ├── Origin.swift, NetworkPolicy.swift, OriginContext.swift
│   │   │                             sandbox / per-origin isolation
│   │   └── BundleLoader.swift        манифест + entry script fetcher
│   ├── LumenShell/            Browser UI поверх Runtime
│   │   ├── BrowserView.swift         SwiftUI shell: address bar + tabs + page host
│   │   ├── FastAppHost.swift         монтирует fast-app в UIViewController
│   │   ├── WebTabView.swift          WKWebView host для обычных сайтов
│   │   ├── TabModel.swift, TabsStore.swift, HistoryStore.swift
│   │   └── AddressBar.swift, AddressSuggestions.swift, URLTextField.swift
│   └── LumenLayout/
│       └── FlexLayout.swift          self-contained Flexbox в Swift (без Yoga deps)
├── Tests/
│   ├── ReactivityTests.swift         signal → thunk → patch → CALayer end-to-end
│   ├── ReconcilerTests.swift         CALayer mount/diff/append/remove
│   ├── FlexLayoutTests.swift         flex layout regressions
│   └── NetworkPolicyTests.swift      sandbox / origin / manifest connect
├── Examples/                  Fast-apps (TS, грузятся через dev-server в Lumen)
│   ├── HelloApp/                     минимальный пример, один файл
│   ├── BankApp/                      средне-большое app с роутером + ScrollView + Sheet
│   ├── BankLab/                      lab-вариант BankApp
│   ├── HN/                           Hacker News reader (real-world demo)
│   ├── BlurLab, DragLab, InputLab, MapLab, PlatformLab,
│   │   ScrollLab, SheetLab, TabsLab  узкие лабы под отдельные API
├── packages/
│   ├── lumen-cli/                    @lumen/cli — bun-based init/dev/build
│   └── lumen-types/                  @lumen/types — TS definitions для runtime API
├── tools/
│   └── dev-server.ts                 shim: `bun tools/dev-server.ts <path> <port>`
├── docs/                      IDEA / PLAN / ROADMAP + UI prototypes
├── sessions/                  Журнал работ (один .md за смену)
├── project.yml                xcodegen spec — источник истины
└── Lumen.xcodeproj            генерируется из project.yml
```

## Требования

- macOS с Xcode 15+ (iOS SDK 17+).
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`.
- [Bun](https://bun.sh) — `brew install bun`. Используется для dev-server и CLI.
- Apple Developer account (бесплатный достаточно) для запуска на физическом девайсе.

## Регенерация Xcode-проекта

`project.yml` — источник истины. При добавлении файлов в `Sources/` или `Tests/` обычно достаточно:

```sh
xcodegen generate
```

Без этого Xcode не видит новые файлы.

## Сборка и запуск

### iOS Simulator

Через Xcode (рекомендуется):

1. Открой `Lumen.xcodeproj`.
2. Выбери симулятор (например, iPhone 17 Pro) → Run (⌘R).

Через CLI:

```sh
xcodebuild -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build
```

### Физическое устройство

```sh
xcrun devicectl list devices                                   # получи UDID
xcodebuild -scheme Lumen -showdestinations | grep <твой iPhone>  # xcodebuild-формат id
xcodebuild -scheme Lumen -destination 'id=<xcodebuild-id>' \
  -derivedDataPath build build

xcrun devicectl device install app --device <devicectl-id> \
  build/Build/Products/Debug-iphoneos/Lumen.app
xcrun devicectl device process launch --device <devicectl-id> com.lumen.browser
```

xcodebuild и devicectl используют **разные форматы** device id — см. [reference_device_debug](#) memory note.

## Разработка fast-app'ов

Каждый пример в `Examples/` — самостоятельный fast-app: `manifest.json` + entry-скрипт. Lumen грузит их через HTTP по адресу `http://<host>:<port>/` (манифест по `/.well-known/lumen.json`).

### Запуск dev-server

```sh
bun tools/dev-server.ts Examples/HelloApp 8080
```

Сервер раздаёт файлы, on-the-fly транспилит `.ts/.tsx` через `Bun.Transpiler`, и пушит `reload` по WebSocket при изменениях (HMR).

В `BrowserView.swift` на стартовой странице список встроенных примеров с адресами вида `http://192.168.0.107:80XX` — поправь IP под свою сеть.

### Свой fast-app

```sh
bunx @lumen/cli init my-app
cd my-app
bun ../tools/dev-server.ts . 8090
# открой http://<host>:8090 в Lumen
```

Структура:

```
my-app/
├── manifest.json        name, version, entry, permissions, connect-rules
├── tsconfig.json        strict TS, без DOM lib (Text/Image глобальны)
└── index.ts             entry, начни с mount(() => View(...))
```

API runtime'а описан типами в [packages/lumen-types/index.d.ts](packages/lumen-types/index.d.ts). Основные: `View / Text / Pressable / Image / ScrollView / Glass / VirtualList / TextInput / MapView / Slot`, `signal / computed / effect / mount`, `lumen.fetch / lumen.bottomSheet / lumen.haptics / lumen.alert / lumen.router / …`.

## Тесты

Юнит-тесты на симуляторе:

```sh
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Конкретный класс или метод:

```sh
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:LumenTests/ReactivityTests
```

Покрытие:

- **ReactivityTests** — fine-grained per-prop реактивность (signal → thunk → `lumen._patchProp` → CALayer). Ловят tab-bar-flicker bug: sibling slot rebuild перетирает per-prop patch'и stale `lastTree.style` через reconcile/applyAll.
- **ReconcilerTests** — mount/reconcile инвариант: same-kind reuse layer, kind change replaces layer, append/remove children, detach clears tree.
- **FlexLayoutTests** — flex regression suite (`row` / `column` / `flex` / `padding` / `justify` / `align` / intrinsic measure).
- **NetworkPolicyTests** — fetch sandbox: own-origin allow, cross-origin block, manifest connect whitelist (exact host / subdomain wildcard / scheme normalization).

## Архитектурные заметки

- **Fast-app никогда не блокирует main thread**. JS живёт в JSContext, рендерер ставит explicit CALayer positions внутри `CATransaction.setDisableActions(true)` — render server анимирует поверх этого независимо.
- **Vapor-style fine-grained реактивность**. Thunk в style-слоте (`opacity: () => sig.value`) превращается в per-prop effect через `lumen._patchProp`. Mount-tree пересобирается только если component-функция сама читает `.value` напрямую (обычно — нет).
- **Reconcile инвариант**. Same-id node = JS не пересобирал поддерево → `applyGeometryOnly` (geometry + text/image content sync + gestures), визуальные стили НЕ переписываются. Это критично: иначе sibling-slot rebuild перетирал бы только что положенные per-prop patch'и (см. `applyGeometryOnly` в `Renderer.swift` + `ReactivityTests.testSiblingSlotRebuildPreservesPerPropPatchedColor`).
- **Sandbox-модель**: per-origin storage / keychain / FS / network policy. Origin = scheme+host+port. Default-deny на cross-origin fetch'и, манифест может расширить через `connect`.
- **Bottom sheet** — UIKit `UISheetPresentationController`. Glass/Liquid Glass на iOS 26 — нативный, через `UIGlassEffect`. Контент в sheet'е рендерится через nested Renderer, layout фиксируется на medium-detent bounds (см. `BottomSheetViewController.swift`).

## Журнал работ

`sessions/NNN-YYYY-MM-DD-topic.md` — снепшоты решений по дням. Если копаешься в чём-то странном — поищи там; часто там объяснение «почему так» вместо «как».
