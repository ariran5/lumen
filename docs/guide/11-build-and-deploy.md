# 11 — Build & deploy

## Local dev vs production

| Режим | Команда | Что делает |
|---|---|---|
| Dev | `lumen dev` | Раздаёт файлы, on-the-fly TS-транспил, HMR через WebSocket |
| Production | `lumen build` | Бандлит entry+импорты в один `dist/bundle.js`, минифицирует, пишет `dist/manifest.json` |

Production build обязателен для multi-file проектов — runtime сам по
себе не делает import resolution, на dev это делает dev-server.

---

## `lumen dev`

```sh
lumen dev               # path=., port=8080
lumen dev . 8090
lumen dev Examples/BankApp 8081
```

Что происходит:
1. HTTP сервер на `:8080` раздаёт файлы из текущей папки.
2. `.ts`/`.tsx` транспилятся в JS через `Bun.Transpiler` (быстро).
3. WebSocket на `:8081` пушит `reload` при изменении любого файла.
4. Браузер при `dev: true` в манифесте подключается к WebSocket
   и перезапускает fast-app.

В dev режиме fast-app может состоять из нескольких файлов:
- Lumen-браузер дёргает entry (`/index.ts`).
- Dev-server резолвит `import`'ы и отдаёт каждый файл отдельно.

---

## `lumen build`

```sh
lumen build              # path=.
lumen build Examples/BankApp
```

Результат:

```
dist/
├── bundle.js          # entry + все импорты в один файл, IIFE для JSC
└── manifest.json      # production-манифест, entry → /bundle.js
```

`bundle.js` собирается через `Bun.build` с `target: 'browser'`,
format = IIFE (важно, иначе JSC не съест ESM напрямую). TypeScript
проверки выключены — сделай `tsc --noEmit` отдельно, если хочешь
ловить ошибки типов.

`dist/manifest.json` — production версия, без `dev: true`:

```json
{
  "name": "My App",
  "version": "0.0.1",
  "entry": "/bundle.js",
  "min_runtime": "0.1"
}
```

---

## Deploy

Lumen-браузер ищет fast-app по адресу:

```
GET https://yourdomain.com/.well-known/lumen.json
```

Это standard well-known URI. Сервер должен отдать тот самый
`dist/manifest.json`.

### Простейший вариант: статический хостинг

Залей `dist/` на любой static-хостинг:

| Хостинг | Как |
|---|---|
| Vercel | `vercel deploy dist/` (или drag-and-drop) |
| Netlify | `netlify deploy --dir=dist` |
| Cloudflare Pages | Подключи repo, build command `lumen build`, output `dist` |
| GitHub Pages | Push `dist/` в `gh-pages` branch |
| S3 | `aws s3 sync dist/ s3://bucket --acl public-read` |
| nginx | `cp -r dist /var/www/myapp/` |

### URL setup

Сервер должен:

1. Отдавать `manifest.json` по пути `/.well-known/lumen.json`.
2. Отдавать `bundle.js` по пути из манифеста (по умолчанию `/bundle.js`).
3. Возвращать `Content-Type: application/json` для манифеста и
   `application/javascript` для bundle.
4. Поддерживать **HTTPS** (Lumen блокирует HTTP-манифесты в production,
   как и веб у Service Workers).

### Пример nginx config

```nginx
server {
  listen 443 ssl http2;
  server_name myapp.example.com;

  root /var/www/myapp;

  location = /.well-known/lumen.json {
    alias /var/www/myapp/manifest.json;
    add_header Content-Type application/json;
    add_header Cache-Control "no-cache";
  }

  location /bundle.js {
    add_header Cache-Control "public, max-age=3600";
  }

  location / {
    try_files $uri =404;
  }
}
```

### Verify deploy

После выкладки проверь:

```sh
curl https://myapp.example.com/.well-known/lumen.json
# должно вернуть { "name": ..., "version": ..., "entry": "/bundle.js", ... }

curl -I https://myapp.example.com/bundle.js
# 200 OK, Content-Type: application/javascript
```

Потом в Lumen-браузере введи `https://myapp.example.com` — браузер
дёрнет манифест, найдёт fast-app, загрузит bundle.

---

## Версионирование

`version` в манифесте — semver. Каждый relayer хорошо инкрементить.
Lumen-браузер увидит изменение версии и:

- Скачает новый bundle.
- Старый кэш инвалидирует.
- (TODO: bytecode pre-compile per version.)

Hash бандла можно класть в `bundle_hash`:

```json
{
  "name": "My App",
  "version": "0.1.5",
  "entry": "/bundle.js",
  "bundle_hash": "sha256-abc123..."
}
```

Если хеш не совпадает после загрузки — bundle отвергается. Защита от
MITM на канал HTTPS->JSC.

---

## Permissions и connect

Production-манифест должен явно объявить все используемые permission'ы
и хосты для fetch:

```json
{
  "name": "My App",
  "version": "0.1.0",
  "entry": "/bundle.js",
  "min_runtime": "0.1",
  "permissions": ["biometric", "notifications"],
  "connect": [
    "https://api.example.com",
    "https://*.cdn.example.com"
  ]
}
```

Юзер увидит этот список **до** запуска fast-app'а (UI permission-prompt
TODO в shell). Запросы на хосты вне `connect` отвергаются без обращения
к юзеру.

Подробнее про connect-правила — [07-data-fetch-storage.md](07-data-fetch-storage.md).

---

## Размер bundle

Цель — bundle меньше 200KB (gzipped <50KB) для cold start <150ms на 4G.

Что увеличивает bundle:
- Большие npm-зависимости (lodash целиком, moment).
- Не tree-shaken JSON.
- Inline base64 ассеты.

Что уменьшает:
- Bun build с `minify: true` (по умолчанию в `lumen build`).
- Используй стрелочные функции, ES2020 features — JSC всё это съест без полифилов.
- Большие иконки/изображения — отдельно как HTTP-ассеты, не inline.

---

## Локальное тестирование production bundle

```sh
lumen build
cd dist
bun --hot serve --port 8080
# в манифесте проверь entry — должно быть "/bundle.js"
```

Или через любой static-server:

```sh
cd dist
python3 -m http.server 8080
```

Открой `http://<host>:8080` в Lumen — fast-app загрузится из bundle.

> Для production деплоя ты должен будешь поддерживать `/.well-known/lumen.json`
> как alias на `/manifest.json`. На dev-сервере (`lumen dev`) этот alias
> подставляется автоматически.

---

## Дальше

→ [12 — Debugging](12-debugging.md): Safari Inspector, FPS HUD, типичные
проблемы.
