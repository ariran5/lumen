# 01 — Getting started

## Что нужно установить

| Инструмент | Зачем | Команда |
|---|---|---|
| macOS 14+ / Xcode 15+ | Сборка iOS-приложения Lumen-браузера | App Store |
| [xcodegen](https://github.com/yonaskolb/XcodeGen) | Генерация `Lumen.xcodeproj` из `project.yml` | `brew install xcodegen` |
| [Bun](https://bun.sh) | Dev-server, CLI, бандлер fast-app'ов | `brew install bun` |
| Apple Developer account | Запуск на физическом девайсе (бесплатный годится) | [developer.apple.com](https://developer.apple.com) |

Симулятор iPhone 17 Pro подходит для разработки. На физическом девайсе
тестируй перед релизом — JIT в симуляторе ведёт себя не так, как на железе,
а ProMotion 120 fps в симе не воспроизведёшь.

---

## Сборка Lumen-браузера

```sh
git clone <repo>
cd alternativeRenderer
xcodegen generate           # создаст Lumen.xcodeproj
open Lumen.xcodeproj
# Выбери iPhone 17 Pro Simulator → Run (⌘R)
```

Браузер откроется, увидишь стартовый экран со списком встроенных
fast-app'ов и адресной строкой.

### Альтернатива: CLI-сборка

```sh
xcodebuild -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build
```

### Запуск на физическом устройстве

```sh
xcrun devicectl list devices                                    # узнай UDID
xcodebuild -scheme Lumen -showdestinations | grep <твой iPhone> # достань xcodebuild-id (он другой!)

xcodebuild -scheme Lumen -destination 'id=<xcodebuild-id>' \
  -derivedDataPath build build

xcrun devicectl device install app --device <devicectl-id> \
  build/Build/Products/Debug-iphoneos/Lumen.app
xcrun devicectl device process launch --device <devicectl-id> com.lumen.browser
```

⚠️ `xcodebuild` и `devicectl` используют **разные форматы** device id —
не путай их.

---

## Запуск встроенного примера

В репо лежит `Examples/HelloApp` — однофайловый минимальный fast-app.

```sh
bun tools/dev-server.ts Examples/HelloApp 8080
```

В терминале появятся IP'ы хоста:

```
Lumen dev server: http://192.168.x.x:8080
WebSocket: ws://192.168.x.x:8081
```

В стартовом экране Lumen-браузера (или в адресной строке) введи
`http://<IP>:8080` — fast-app загрузится, ты увидишь экран «Hello Lumen»
из трёх карточек.

> Если открываешь с симулятора на том же Mac — используй `localhost:8080`
> или `127.0.0.1:8080`. С физического устройства нужен IP машины в той же
> Wi-Fi сети.

### Что происходит при загрузке URL

1. Браузер дёргает `http://<host>:8080/.well-known/lumen.json`.
2. Получает манифест → это fast-app, не обычный сайт.
3. Качает entry-script (`/index.js` или `/index.ts` для dev).
4. Запускает скрипт в JSContext, ставит рендер.

Если манифеста нет — браузер открывает страницу через WKWebView (как Safari).

---

## Установка CLI глобально

```sh
bun add -g @lumen/cli
# или одноразово:
bunx @lumen/cli init my-app
```

После этого доступны:

- `lumen init <name>` — создать новый проект
- `lumen dev [path] [port]` — поднять dev-сервер с HMR
- `lumen build [path]` — собрать production bundle

Подробнее про каждую команду — в [11-build-and-deploy.md](11-build-and-deploy.md).

---

## Дальше

→ [02 — Your first app](02-your-first-app.md): создаём свой первый fast-app
со счётчиком и HMR.
