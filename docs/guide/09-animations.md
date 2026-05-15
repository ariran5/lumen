# 09 — Animations

Lumen различает **два типа реактивных значений**:

1. **Thunk** (`() => sig.value`) — js пишет через bridge при каждом
   изменении signal'а. Хорошо для статичных переходов (тема, ввод),
   плохо для 60+ fps анимации.
2. **AnimatedValue** — native-driven значение, живёт на render server
   thread. JS только заказывает анимацию ("animateTo 100 за 300ms").
   После запуска **не зависит от JS** — даже если JS thread занят,
   анимация продолжает идти.

---

## animated() — off-main анимации

```ts
const x = animated(0)  // initial = 0

View({
  width: 100, height: 100,
  backgroundColor: '#7B6CFF',
  transform: {
    translateX: x,    // ← AnimatedValue, не number, не thunk
  },
})
```

Когда Renderer видит `AnimatedValue` в transform/opacity — он **линкует**
свойство CALayer с этим значением. Дальше все `x.set/animateTo/stop`
пишут напрямую в render server, минуя js→swift bridge.

### Методы AnimatedValue

```ts
x.set(50)                                    // мгновенно, без анимации
x.animateTo(100, { duration: 300 })          // ease (default 'easeOut')
x.animateTo(0, { duration: 500, easing: 'spring' })
x.stop()                                     // freeze на текущем визуальном
x.current()                                  // последнее js-side значение (может отставать от визуального во время анимации)
```

### Easing

```ts
type Easing = 'linear' | 'easeIn' | 'easeOut' | 'easeInOut' | 'spring'

x.animateTo(100, { duration: 400, easing: 'spring' })
// duration игнорируется для spring — длительность считается из физики
```

### Поля, поддерживающие AnimatedValue

- Transform: `translateX`, `translateY`, `scale`, `scaleX`, `scaleY`, `rotate`
- Visual: `opacity`

Остальные props (color, borderRadius, и т.д.) — через thunks или
обычные signals.

---

## Пример: drag + spring-back

```ts
const x = animated(0)
const y = animated(0)

View({
  width: 120, height: 120,
  backgroundColor: '#7B6CFF',
  borderRadius: 60,
  transform: {
    translateX: x,
    translateY: y,
  },
  onPan: (e) => {
    if (e.state === 'start') {
      // Поймать в середине анимации: stop() возвращает текущий визуальный
      // и кладёт его как новый model — никакого "перепрыга" при touchdown.
      x.stop()
      y.stop()
    }
    else if (e.state === 'changed') {
      x.set(x.current() + e.dx)
      y.set(y.current() + e.dy)
    }
    else if (e.state === 'ended') {
      // Spring back to 0
      x.animateTo(0, { easing: 'spring' })
      y.animateTo(0, { easing: 'spring' })
    }
  },
})
```

Что здесь важно:
- `x.stop()` на `start` — берёт current presentation value и делает его
  новым model. Без этого пользователь схватил бы "старую" позицию (то,
  что было до прошлой spring-анимации).
- `e.dx / e.dy` — translation от начала жеста, не дельта между tick'ами.
  Поэтому `x.set(x.current() + e.dx)` — каждый tick новая абсолютная
  позиция, не накопление.
- На `ended` JS делает один вызов `animateTo` — анимация дальше идёт
  без JS.

---

## Thunk vs AnimatedValue — когда что

| Сценарий | Что использовать |
|---|---|
| Цвет при tap'е (`backgroundColor`) | Thunk: `backgroundColor: () => pressed.value ? red : blue` |
| Текст счётчика | Thunk: `Text(props, () => count.value)` |
| Drag-translate | `AnimatedValue` |
| Sheet-snap (open/close) | `AnimatedValue` с `'spring'` |
| Анимация opacity при load | `AnimatedValue` или thunk + `effect` |
| Прогресс-бар (% width) | Thunk, если плавность не критична. AnimatedValue для smooth fill |

**Правило большого пальца:** если анимация **должна продолжаться** даже
когда JS занят (drag, spring back, parallax при скролле) — `animated()`.
Если значение редко меняется в ответ на одно событие (загрузка, tap) —
thunk.

---

## Пример: fade-in при load

```ts
const opacity = animated(0)

mount(() => {
  // Запустить fade-in после mount
  opacity.animateTo(1, { duration: 400 })

  return View({
    opacity: opacity,
    flex: 1,
    backgroundColor: '#16161D',
  }, ...)
})
```

---

## Пример: pull-to-collapse header

```ts
const headerHeight = animated(200)

ScrollView({
  flex: 1,
  onScroll: (e) => {
    const h = Math.max(80, 200 - e.offset)
    headerHeight.set(h)  // прямо в render server
  },
},
  View({
    height: headerHeight,  // AnimatedValue в style — НЕ поддержано для height
    // ...
  }),
)
```

⚠️ `height` пока не поддерживает AnimatedValue (только transform + opacity).
Для прыжков размера используй `transform: { scaleY: ... }` или ребилдь
через thunk + `effect`.

---

## Что НЕ делать

- ❌ Не привязывай AnimatedValue к нескольким узлам одновременно.
  Один AnimatedValue → один layer-property. Если нужно два узла —
  заведи два AnimatedValue.
- ❌ Не вызывай `.current()` в hot loop. Это js-side mirror; во время
  анимации он может отставать от визуального значения.
- ❌ Не забывай `.stop()` перед перехватом drag'ом, если узел был в
  анимации — иначе JS возьмёт устаревший model-value.

---

## Дальше

→ [10 — Project structure](10-project-structure.md): как организовать
средне-большое приложение.
