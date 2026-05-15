# Lumen — Guide

Пошаговое руководство по разработке **fast-app'ов** под Lumen — альтернативный
рантайм для iOS, где JS пишет в реальные `CALayer`, layout считает Flexbox
на Swift, а API нативные (UISheetPresentationController, UIFeedbackGenerator,
MKMapView, Face ID, …).

Если ты впервые видишь проект — начни с [01](01-getting-started.md).
Если уже что-то писал — смотри [13-cheatsheet.md](13-cheatsheet.md) как
быструю шпаргалку.

> Этот гайд — **про написание приложений поверх Lumen**, не про устройство
> рантайма. Внутренности (Renderer, Reconciler, JSEngine) описаны в
> [../IDEA.md](../IDEA.md), [../PLAN.md](../PLAN.md) и журнале
> [../../sessions/](../../sessions/).

---

## Оглавление

| # | Глава | О чём |
|---|---|---|
| 01 | [Getting started](01-getting-started.md) | Установка, запуск браузера, первый dev-server |
| 02 | [Your first app](02-your-first-app.md) | `lumen init`, `mount`, первый счётчик, HMR |
| 03 | [Views & styling](03-views-and-styling.md) | View / Text / Pressable / Image + FlexProps + дизайн-токены |
| 04 | [Reactivity](04-reactivity.md) | signal / computed / effect / Slot / per-prop thunks |
| 05 | [Native APIs](05-native-apis.md) | bottomSheet / alert / haptics / biometrics / notifications / share |
| 06 | [Navigation](06-navigation.md) | router.push/pop, типизированный routes registry, tab-bar |
| 07 | [Data: fetch & storage](07-data-fetch-storage.md) | `fetch`, `storage`, `secureStorage`, sandbox `connect` |
| 08 | [Advanced components](08-advanced-components.md) | ScrollView / VirtualList / TextInput / Blur / Glass / MapView |
| 09 | [Animations](09-animations.md) | `animated()` off-main, thunks vs AnimatedValue |
| 10 | [Project structure](10-project-structure.md) | Multi-file: `state/`, `services/`, `pages/`, `components/` |
| 11 | [Build & deploy](11-build-and-deploy.md) | `lumen build`, `.well-known/lumen.json`, выкладка |
| 12 | [Debugging](12-debugging.md) | Safari Inspector, `lumen.bench`, типичные грабли |
| 13 | [Cheatsheet](13-cheatsheet.md) | Краткая сводка API |

---

## Чем Lumen отличается от других рантаймов

- **Не WebView.** Нет DOM, нет CSS, нет селекторов. View = `CALayer`,
  Text = `CATextLayer` с измерением через CoreText.
- **JS живёт в JSContext.** Это полноценный JavaScriptCore с JIT (тот же,
  что в Safari). 1e6-итераций — <50ms.
- **Реактивность Vapor-style.** `() => sig.value` в стиль-слоте — это
  per-prop effect, который патчит свойство CALayer напрямую, без
  re-render всего поддерева.
- **Анимации не на main thread.** `animated()` пишет напрямую на render
  server (тот же, что крутит SwiftUI/UIKit). JS можно блокировать —
  анимация продолжит идти.
- **Sandbox по-серьёзному.** Storage, keychain, fetch — per-origin
  (scheme+host+port). Default-deny на cross-origin. Манифест расширяет
  через `connect`.

## Что НЕ поддерживается (специально)

- DOM API (`document`, `window`).
- CSS, селекторы, классы. Только inline style-объекты.
- `History API`, `localStorage` (есть свой `lumen.storage`).
- React. JSX можно через esbuild, но рантайм даёт функции `View(...)`/`Text(...)` напрямую.
- Сторонние npm-зависимости с DOM-кодом. TS/чистый JS — ОК.
