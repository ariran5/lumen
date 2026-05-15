# 02 — Your first app

## Создание проекта

```sh
bunx @lumen/cli init my-app
cd my-app
```

CLI создаст структуру:

```
my-app/
├── manifest.json          # имя/версия/entry/permissions
├── tsconfig.json          # strict TS, без DOM lib
├── lumen-types.d.ts       # глобальные типы View/Text/signal/lumen.*
└── index.ts               # entry-скрипт
```

### `manifest.json`

```json
{
  "name": "My App",
  "version": "0.0.1",
  "entry": "/index.ts",
  "min_runtime": "0.1",
  "dev": true
}
```

| Поле | Зачем |
|---|---|
| `name`, `version` | Показываются в браузере / в истории |
| `entry` | Путь к entry-скрипту от корня сайта |
| `min_runtime` | Минимальная версия Lumen. Если у юзера старее — fast-app не загрузится, откроется через WebView |
| `dev` | Включает HMR-клиент в браузере (только локальная разработка) |
| `permissions` | Список нативных permission'ов: `"biometric"`, `"notifications"` и т.д. |
| `connect` | Whitelist хостов для cross-origin `fetch` (см. главу 07) |

---

## Запуск dev-сервера

```sh
lumen dev               # path=., port=8080 по умолчанию
# или: lumen dev . 8090
```

Открой `http://<host>:8080` в Lumen-браузере. На симуляторе подойдёт
`localhost`, с физического устройства — IP машины в той же Wi-Fi.

> Что делает dev-server: раздаёт файлы из текущей папки, на лету
> транспилит `.ts/.tsx` через `Bun.Transpiler`, и поднимает WebSocket
> на `port+1`. При изменении любого файла шлёт `reload` — fast-app
> перезапускается, состояние signal'ов сбрасывается, JSContext
> чистый. Это HMR-уровня «реакт-натив reload», не «React Fast Refresh».

---

## Минимальный счётчик

`index.ts` после `lumen init` уже содержит счётчик. Разберём его построчно:

```ts
const count = signal(0)

function App() {
  return View({
    flex: 1,
    padding: 32, gap: 24,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#0F0F12',
  },
    Text(
      { fontSize: 48, fontWeight: '700', color: '#FFFFFF' },
      `${count.value}`,
    ),

    Pressable({
      onTap: () => {
        count.value++
        lumen.haptics('light')
      },
      paddingTop: 14, paddingRight: 24, paddingBottom: 14, paddingLeft: 24,
      backgroundColor: '#6366F1',
      borderRadius: 12,
    },
      Text({ fontSize: 16, fontWeight: '600', color: '#FFFFFF' }, 'Tap me'),
    ),
  )
}

mount(App)
```

### Что здесь происходит

- **`signal(0)`** — реактивная ячейка. Чтение `.value` записывает в
  текущий effect/component, что мы зависим от этого signal'а. Запись
  `.value = …` дёргает все зависящие effect'ы.
- **`View(props, ...children)`** — фабрика узла. Возвращает immutable
  `RenderNode`. Не CALayer и не UIView — это просто описание дерева,
  которое потом превратится в CALayer.
- **`Pressable`** — то же что View, но с обязательным `onTap`. Под капотом
  ставится UITapGestureRecognizer на соответствующий CALayer.
- **`mount(App)`** — регистрирует root-effect. Каждый раз когда любой
  signal, прочитанный внутри `App()`, меняется — `App()` запускается
  заново, reconciler сравнивает деревья, в живые CALayer'ы летят патчи.
  Не пересоздаются — переиспользуются.

### Где разница с React

`App` это не компонент, который монтируется один раз и потом обновляется
через хуки. `App` это функция, которую mount-effect перезапускает целиком
при изменении любого signal'а внутри неё. **Это дёшево** (создание
объектов 1µs/узел), но если ты не хочешь, чтобы при каждом тике
ребилдилось всё дерево — изолируй реактивность в `Slot` или используй
**thunk** в стиль-слоте (см. главу 04).

---

## Что попробовать дальше

1. Поменяй `'Tap me'` на что угодно — сохрани файл, увидь HMR.
2. Замени `Pressable` на:

   ```ts
   Pressable({ ... },
     Text({ fontSize: 16, fontWeight: '600', color: '#FFFFFF' },
       () => `Tapped ${count.value} times`),
   )
   ```

   Текст теперь — **thunk**. При изменении `count` ребилдится не вся
   `App()`, а только содержимое этого `Text`. Это per-text effect.

3. Добавь второй счётчик `const score = signal(0)` и отдельную
   `Pressable`. Понаблюдай в Safari Developer Tools (см. главу 12),
   что mount-effect срабатывает на каждое изменение.

---

## Дальше

→ [03 — Views & styling](03-views-and-styling.md): полный набор примитивов
и стиль-системы.
