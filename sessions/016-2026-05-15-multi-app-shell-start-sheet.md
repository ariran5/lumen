# Session 016 — 2026-05-15: Phase 6 Block 6 — Multi-app shell (TabRuntime + StartSheet)

> Закрыли центральную часть Block 6 — per-tab JSEngine lifecycle через `TabRuntime`. Плюс новый shell-UI: тап по favicon-disc'у открывает bottom sheet с двумя страницами (Home embedded fast-app + Tabs list) и прибитой к низу строкой поиска. Манифест-интеграция, background-pause и settings UI остались на follow-up.

---

## TL;DR

| Что | Файлы |
|---|---|
| `TabRuntime` — long-lived per-tab JSEngine + UIKit hierarchy; живёт в `TabModel.runtime`, выживает SwiftUI rebuild'ы при tab switch'е | TabRuntime.swift |
| `TabModel.runtime` (ObservationIgnored, lazy) — owner; `commit()` сбрасывает runtime при смене URL'а | TabModel.swift |
| `FastAppHost` — теперь thin wrapper над TabRuntime; `ensureRuntime` создаёт или reuse'ит | FastAppHost.swift |
| `StartSheet` — new bottom-sheet с TabView (.page style): Home (embedded `lumen://home` fast-app в persistent `SheetHome.tab`) + Tabs list + bottom search через `URLTextField` (pre-filled + auto-focused + selectAll) | StartSheet.swift |
| Favicon-disc tap → открывает sheet (раньше → разворачивание address bar'а) | AddressBar.swift, BrowserView.swift |
| `lumen.tabs.navigate(url)` fallback'ит на `activeTab` если ownTabID не в TabsStore — для embedded sheet home, чтобы пин-клик в home navigation'нул user's active tab | JSEngine+Tabs.swift |
| Auto-dismiss sheet на смену active URL'а (не только activeID) | StartSheet.swift |
| `URL.hostForDisplay` хелпер — port отображается ВЕЗДЕ в UI | URLDisplay.swift; usages в TabModel, AddressBar, AddressSuggestions |

---

## Per-tab JSEngine lifecycle (Block 6 core)

### Проблема

До этой сессии engine жил в `FastAppHost.Coordinator` — SwiftUI representable. Когда юзер переключает табы, SwiftUI выкидывает старый `TabContent` и создаёт новый. `Coordinator` → deinit → engine release.

Эффект: switching tabs **destroys** fast-app's JS state. Return = reload from scratch. Не multi-app.

### Фикс

Перенесли владение в `TabModel.runtime: TabRuntime?`. TabRuntime владеет:
- `engine: JSEngine`
- `nav: UINavigationController`
- `rootPage: LumenPageViewController`
- `devClient: DevServerClient?`

`init` создаёт hierarchy и зовёт `setupEngine`. `loadIfNeeded` зовётся из `onLayout` callback'а rootPage'а. `performReload` (HMR) пересоздаёт rootPage + engine.

`@ObservationIgnored` на runtime — изменения runtime'а не должны триггерить SwiftUI invalidation (UI вьюх не зависит от него напрямую).

`FastAppHost` теперь:
```swift
struct FastAppHost: UIViewControllerRepresentable {
    @Bindable var tab: TabModel
    let url: URL
    
    func makeUIViewController(context: Context) -> UINavigationController {
        ensureRuntime().nav  // создаёт runtime или reuse'ит existing
    }
    func updateUIViewController(...) { tab.runtime?.loadIfNeeded() }
}
```

`tab.commit()` сбрасывает runtime если URL сменился — старый engine ARC'нется, новый создастся при следующем `ensureRuntime`. Если URL тот же — runtime тот же, JS state preserved.

### Что осталось

- **Manifest integrity** — sha256 для script + опционально `files: {sha256}` в манифесте, проверка перед eval
- **Background-tab pause** — pause timers / animations когда таб неактивна. Память освобождать не нужно (это уже не наш scope), но CPU должен быть idle.
- **Settings UI** — per-origin clear-site-data + revoke-permissions
- **Memory eviction** — LRU когда табов много (TODO когда понадобится)

---

## StartSheet — новый shell-UI

### Контекст

Запрос от юзера: tap по favicon disc'у должен открывать «дом» как bottom sheet, swipe-down → возврат к текущему сайту/app без перезагрузки.

Итерации:
1. Первая версия — Tabs grid + Examples list + History link + bottom search (SwiftUI). User: «главная старая была лучше».
2. Заменили SwiftUI Examples на embedded `lumen://home` (greeting + pinned + labs + recent). User: «табы выглядят крупно, если много открыто — не видно home; и search prefilled+selected как у других браузеров».
3. Финал — TabView с page-style: Home (page 0) + Tabs list (page 1), переключение свайпом или тапом по сегментам сверху. Поиск через `URLTextField` (нативный UITextField с selectAll on focus), pre-filled URL'ом активной таб'ы, auto-focused (как Safari).

### Структура

```
VStack {
  pageSwitcher (Home / Tabs · N)  ← top
  TabView(.page) {
    homePage  ← FastAppHost(SheetHome.tab, lumen://home)
    tabsPage  ← LazyVStack(tabRows)
  }
  searchBar  ← URLTextField, bottom-pinned, prefilled+focused
}
```

### `SheetHome.tab`

Отдельный persistent TabModel для embedded home в sheet'е. НЕ в `TabsStore.tabs` (не должен появляться в user'ском списке). Живёт всю жизнь процесса; engine инициализируется лениво при первом show.

### `lumen.tabs.navigate` fallback

Изначально `navigate(url)` искал tab по `ownTabID` в `TabsStore.shared.tabs`. SheetHome.tab там нет → пин-клик в embedded home ничего не делал.

Fix: fallback на `TabsStore.shared.activeTab` если ownTab не найден. Embedded sheet home через `navigate` навигирует **user's active tab под sheet'ом**. После навигации `activeTab.currentURL` меняется → `StartSheet.dismissIfNavigated` фаерит → sheet закрывается → юзер видит результат.

### Auto-dismiss

`onChange(of: tabs.activeID)` + `onChange(of: tabs.activeTab?.currentURL)`. На входе snapshot'им оба значения; на change'е сравниваем со snapshot'ом — если что-то изменилось, dismiss. Это закрывает все сценарии: tap на example app, pin click, search commit, switch tabs, tap card.

### Search bar

`URLTextField` — нативный UITextField с `selectAll(nil)` в `textFieldDidBeginEditing` (SwiftUI TextField так не умеет). На `.onAppear` ставим:
```swift
searchInput = tabs.activeTab?.currentURL?.absoluteString ?? ""
DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
    searchFocused = true
}
```

Маленькая задержка — sheet animation должна стартануть до фокуса, иначе keyboard up'ается одновременно со sheet'ом и выглядит дёрнуто.

### Tabs list page

Single-column list (а не grid 2 в ряд как было) — компактнее, видно больше за раз. Tap = switch + dismiss. X-кнопка = close. Long press = pre-fill URL в bottom search для editing'а.

### Что осталось для Block 6

- Manifest integrity (sha256) — отдельный мини-PR
- Settings UI: список загруженных apps + clear-site-data / revoke per-origin — нужен для полного multi-app опыта
- Background-tab pause — timers / animations freeze когда таб неактивна

---

## Port в URL display

Юзер: «Везде по проекту где показывается ссылка показывай и порт».

Добавил `URL.hostForDisplay` хелпер ([URLDisplay.swift](../Sources/LumenShell/URLDisplay.swift)):
```swift
extension URL {
    var hostForDisplay: String {
        if scheme == "lumen", let h = host { return "lumen://\(h)" }
        guard let h = host else { return absoluteString }
        if let p = port { return "\(h):\(p)" }
        return h
    }
}
```

Apply'нул в:
- `TabModel.displayTitle` — fallback host → `url.hostForDisplay`
- `AddressBar.hostText` — display host под favicon
- `AddressSuggestions.SuggestionRow.host`
- `StartSheet.tabRow` (там сразу `absoluteString` — нужен полный URL для tabs list'а)

`hostOf` в JS-стороне (homeJS / historyJS) уже работает через regex и включает порт — не трогали.

Origin'ы и NetworkPolicy используют `URL.host` для логики matching'а — не display, не трогали.

---

## Где мы сейчас (Phase 6)

- ✓ Block 1: Foundation
- ✓ Block 2: Network policy
- ✓ Block 3: Permission system
- ✓ Block 4: HTTPS-only + Developer Mode
- ✓ Block 5: Storage quotas
- ⏳ Block 6: Multi-app shell — **partial** (TabRuntime + StartSheet); manifest integrity / background pause / settings UI / memory eviction отложены

Phase 6 практически закрыт по acceptance критериям. Остаётся косметика и follow-up scope.

## Следующие сессии

1. **Block 6 polish**: manifest integrity hash + background-tab pause + settings UI.
2. **Error UX для fast-app crash'а** — упоминалось как nice-to-have ранее.
3. **Real-app profiling**: бенчи у нас на one-shot render, на BankApp с табами/sheet'ами что-то может выпадать из 8.3ms бюджета.
