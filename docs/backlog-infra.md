# Lumen — инфраструктурный бэклог (DX)

Отложено 2026-05-13: пользователь приоритезирует возможности платформы (device API, primitives), а не DX-инфру. Возвращаемся сюда после.

## 1. HMR (Hot Module Reload)
Сейчас изменения в `.ts` требуют ручного reload таба. Дев-сервер уже есть (`192.168.0.108:80xx`), JS-bridge есть, per-node EffectScope/disposal есть.

Что нужно:
- ws-канал dev-server → device (file change events)
- JS-сторона: реэкспорт-патч модуля или полный re-eval с сохранением signals state
- Renderer.swift: переиспользует существующий per-node disposal — после re-eval JS вызывает `lumen._disposeNodes(oldIds)` и монтирует свежее дерево
- Опционально: HMR-acceptance API в стиле `import.meta.hot.accept(...)`

Сложность: средняя. Самая хитрая часть — сохранение state'а сигналов через перезагрузку (нужно идентифицировать "тот же" сигнал).

## 2. lumen-cli (npm bundling)
Сейчас bare imports (`import { z } from 'zod'`) не работают — dev-server только TS транспилит.

Что нужно:
- CLI `lumen build` / `lumen dev` поверх esbuild
- Конфиг `lumen.config.ts` (entry, externals, target)
- Резолвинг node_modules + tree-shaking
- Source maps для DevTools

Открывает доступ к pure-JS либам: zod, date-fns, TanStack Query core, immer, mitt, nanoid, etc.

## 3. @lumen/ui component kit + design tokens
Каждый Lab верстает Button/Card/List с нуля. Опубликовать пакет:
- Базовые: Button, Card, ListItem, Sheet, Tabs, Switch, Stepper, Progress, Spinner
- Design tokens: `tokens.color.{bg,surface,accent,...}`, `tokens.radius.{sm,md,lg}`, `tokens.spacing.{xs,...,xl}`, dark/light
- Сейчас компоненты приходится копировать между Lab'ами

Снижает порог входа в Lumen: новый fast-app выглядит прилично без боли.

## 4. DevTools / Error Overlay
JS exception сейчас уходит в Xcode console, в самом приложении не видно.

Что нужно:
- Overlay поверх Lumen-дерева на JS-exception (red screen of death в стиле RN)
- Stack trace + кнопка "Reload"
- Source maps от dev-server'а — показывать `.ts` строки, не транспилированный `.js`
- Опционально: inspector дерева (`lumen.devtools.dumpTree()`)

## 5. Builtin fast-apps HMR
home / history / library сейчас вшиты Swift String'ами в [BuiltinFastApps.swift](../Sources/LumenRuntime/BuiltinFastApps.swift). Любое изменение → пересобирать iOS.

Что нужно: dev-режим, который грузит builtin'ы с локального dev-server'а (`http://192.168.0.108:9090/home`), а в release — из bundle. Тогда home/history итерируются как обычные fast-app'ы.

## 6. Performance instrumentation
- FPS overlay (mount/relayout per frame)
- JS→Native call count per frame
- Memory: сколько MountedNode/CALayer держится

Без этого оптимизировать вслепую.

## Открытые мелочи из P7
- MapView keyed-pin diff (сейчас сравнение по signature, на больших списках пинов будет лишний reapply)
- WebView/MapView gesture priority — edge-swipe-back не работает поверх контента, который ловит pan-жесты
- iOS 26 status bar dynamic style (light/dark в зависимости от контента)
