import Foundation

/// JS-framework `@lumen/core` — глобально доступен в любом fast-app'е.
/// Эволюционирует как часть рантайма: разработчик не подключает npm-пакет,
/// просто пишет `View(...)`, `Text(...)`, `signal(...)`, `mount(...)`.
enum CoreFramework {
    static let script: String = #"""
    /* @lumen/core — minimal Flutter-style components + signals */
    ;(function () {
      // ─────────── signals ───────────
      let currentEffect = null
      const pendingEffects = new Set()
      let flushScheduled = false

      // Promise.resolve().then() работает в любом JS engine с Promise.
      // queueMicrotask теоретически тоже доступен в JSC 12.2+, но Promise
      // надёжнее как fallback.
      const microtask = (typeof queueMicrotask === 'function')
        ? queueMicrotask
        : function (fn) { Promise.resolve().then(fn) }

      function scheduleFlush() {
        if (flushScheduled) return
        flushScheduled = true
        microtask(function () {
          flushScheduled = false
          const effects = Array.from(pendingEffects)
          pendingEffects.clear()
          for (const eff of effects) {
            try { eff._run() }
            catch (e) { console.error('effect threw: ' + (e && e.message ? e.message : String(e))) }
          }
        })
      }

      function Signal(initial) {
        this._value = initial
        this._subs = new Set()
      }
      Object.defineProperty(Signal.prototype, 'value', {
        get: function () {
          if (currentEffect) {
            this._subs.add(currentEffect)
            currentEffect._signals.add(this)
          }
          return this._value
        },
        set: function (v) {
          if (this._value === v) return
          this._value = v
          const subs = Array.from(this._subs)
          for (const sub of subs) {
            pendingEffects.add(sub)
          }
          scheduleFlush()
        }
      })
      Signal.prototype.peek = function () { return this._value }

      function signal(initial) { return new Signal(initial) }

      // EffectScope (Vapor/Solid-style) — группа effect'ов с общим lifetime.
      // unmount узла → scope.dispose() → все per-prop effect'ы внутри отдых.
      let currentScope = null
      function EffectScope() {
        this._effects = []
        this._disposed = false
      }
      EffectScope.prototype.run = function (fn) {
        if (this._disposed) return fn()
        const prev = currentScope
        currentScope = this
        try { return fn() } finally { currentScope = prev }
      }
      EffectScope.prototype.dispose = function () {
        if (this._disposed) return
        this._disposed = true
        for (const e of this._effects) e.dispose()
        this._effects.length = 0
      }

      function Effect(fn) {
        this._fn = fn
        this._signals = new Set()
        this._disposed = false
        if (currentScope && !currentScope._disposed) {
          currentScope._effects.push(this)
        }
        this._run()
      }
      Effect.prototype._run = function () {
        if (this._disposed) return
        for (const s of this._signals) s._subs.delete(this)
        this._signals.clear()
        const prev = currentEffect
        currentEffect = this
        try { this._fn() } finally { currentEffect = prev }
      }
      Effect.prototype.dispose = function () {
        this._disposed = true
        for (const s of this._signals) s._subs.delete(this)
        this._signals.clear()
        pendingEffects.delete(this)
      }

      function effect(fn) { return new Effect(fn) }

      // untracked(fn) — выполнить fn() БЕЗ подписки текущего effect'а на
      // signal'ы. Используется для initial-eval thunks в билдерах:
      // нам нужен start-value чтобы layout посчитался правильно, но
      // мы НЕ хотим чтобы mount-effect ловил эти signal'ы (иначе любой
      // signal change запускал бы full mount rerun — обратно к не-Vapor).
      function untracked(fn) {
        const prev = currentEffect
        currentEffect = null
        try { return fn() } finally { currentEffect = prev }
      }

      function computed(fn) {
        const s = new Signal(undefined)
        effect(function () { s.value = fn() })
        return s
      }

      // ─────────── component builders ───────────
      const NON_STYLE = {
        onTap: 1, onDoubleTap: 1, onLongPress: 1,
        onPan: 1, onSwipe: 1, onPinch: 1, onRotate: 1,
        source: 1, count: 1, itemHeight: 1,
        render: 1, children: 1, key: 1,
        value: 1, placeholder: 1, keyboardType: 1, returnKey: 1,
        autocapitalize: 1, autocorrect: 1, secure: 1,
        onChange: 1, onSubmit: 1, onFocus: 1, onBlur: 1,
        intensity: 1, variant: 1,
        onScroll: 1, onRefresh: 1,
        // map-specific
        region: 1, pins: 1, mapType: 1,
        onRegionChange: 1, onPinTap: 1,
      }
      const GESTURE_PROPS = [
        'onTap', 'onDoubleTap', 'onLongPress',
        'onPan', 'onSwipe', 'onPinch', 'onRotate'
      ]
      function attachGestures(node, props) {
        if (!props) return
        for (let i = 0; i < GESTURE_PROPS.length; i++) {
          const k = GESTURE_PROPS[i]
          if (typeof props[k] === 'function') node[k] = props[k]
        }
      }

      // splitStyle делит props на:
      //   style   — статические значения (применяются один раз)
      //   bindings — реактивные thunk'и `() => signal.value` (per-prop effects)
      //
      // Это ядро Vapor-style модели: функция в style-слоте означает «реактивное».
      // Handler'ы (onTap и co.) исключаются через NON_STYLE — они тоже функции,
      // но для жестов, не для биндингов.
      function splitStyle(props) {
        if (!props) return {style: {}, bindings: null}
        const style = {}
        let bindings = null
        for (const k in props) {
          if (!Object.prototype.hasOwnProperty.call(props, k)) continue
          if (NON_STYLE[k]) continue
          const v = props[k]
          if (typeof v === 'function') {
            if (!bindings) bindings = []
            bindings.push([k, v])
            // Initial untracked eval — даёт layout правильный измеритель
            // для первого рендера. Effect зарегистрируется потом через
            // registerBindings и будет реагировать на signal-changes.
            try { style[k] = untracked(v) } catch (e) { /* leave undefined */ }
          } else {
            style[k] = v
          }
        }
        return {style, bindings}
      }
      function extractStyle(props) {
        return splitStyle(props).style
      }

      // Каждый build-вызов получает уникальный id — рендерер индексирует
      // MountedNode по нему, чтобы JS-side fine-grained effect'ы могли
      // патчить конкретный CALayer через lumen._patchProp(id, key, value).
      let _nextNodeId = 0
      function nextId() { _nextNodeId = (_nextNodeId | 0) + 1; return _nextNodeId }

      function flatten(arr) {
        const out = []
        for (let i = 0; i < arr.length; i++) {
          const x = arr[i]
          if (x === null || x === undefined || x === false || x === true) continue
          if (Array.isArray(x)) {
            for (let j = 0; j < x.length; j++) {
              const y = x[j]
              if (y === null || y === undefined || y === false || y === true) continue
              out.push(typeof y === 'string' || typeof y === 'number' ? Text(String(y)) : y)
            }
          } else if (typeof x === 'string' || typeof x === 'number') {
            out.push(Text(String(x)))
          } else {
            out.push(x)
          }
        }
        return out
      }

      function View(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const sb = splitStyle(props)
        const node = {
          type: 'view',
          id: nextId(),
          style: sb.style,
          children: flatten(children)
        }
        if (sb.bindings) node.bindings = sb.bindings
        attachGestures(node, props)
        if (props && props.key !== undefined) node.key = String(props.key)
        return node
      }

      function Text(propsOrText /* , ...rest */) {
        if (typeof propsOrText === 'string' || typeof propsOrText === 'number') {
          return { type: 'text', id: nextId(), text: String(propsOrText) }
        }
        const props = propsOrText || {}
        // text-content thunk: Text({...}, () => sig.value) — реактивный text.
        let textThunk = null
        let text = ''
        for (let i = 1; i < arguments.length; i++) {
          const a = arguments[i]
          if (a === null || a === undefined) continue
          if (typeof a === 'function' && i === 1 && arguments.length === 2) {
            textThunk = a
          } else {
            text += String(a)
          }
        }
        const sb = splitStyle(props)
        if (textThunk) {
          try { text = String(untracked(textThunk)) } catch (e) { /* '' */ }
        }
        const node = { type: 'text', id: nextId(), style: sb.style, text }
        if (sb.bindings) node.bindings = sb.bindings
        if (textThunk) {
          if (!node.bindings) node.bindings = []
          node.bindings.push(['text', textThunk])
        }
        if (props.key !== undefined) node.key = String(props.key)
        return node
      }

      function Pressable(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const sb = splitStyle(props)
        const node = {
          type: 'view',
          id: nextId(),
          style: sb.style,
          children: flatten(children)
        }
        if (sb.bindings) node.bindings = sb.bindings
        attachGestures(node, props)
        if (props && props.key !== undefined) node.key = String(props.key)
        return node
      }

      function Image(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const sb = splitStyle(props)
        const node = {
          type: 'image',
          id: nextId(),
          style: sb.style,
          source: props && props.source,
          children: flatten(children)
        }
        if (sb.bindings) node.bindings = sb.bindings
        attachGestures(node, props)
        if (props && props.key !== undefined) node.key = String(props.key)
        return node
      }

      function VirtualList(props) {
        return {
          type: 'virtualList',
          id: nextId(),
          style: extractStyle(props),
          count: (props && props.count) || 0,
          itemHeight: (props && props.itemHeight) || 50,
          render: props && props.render
        }
      }

      function Blur(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const p = props || {}
        const sb = splitStyle(p)
        const node = {
          type: 'blur',
          id: nextId(),
          style: sb.style,
          intensity: (typeof p.intensity === 'string') ? p.intensity : 'regular',
          children: flatten(children)
        }
        if (sb.bindings) node.bindings = sb.bindings
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      function Glass(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const p = props || {}
        const intensity = (p.variant === 'clear') ? 'glassClear' : 'glass'
        const sb = splitStyle(p)
        const node = {
          type: 'blur',
          id: nextId(),
          style: sb.style,
          intensity: intensity,
          children: flatten(children)
        }
        if (sb.bindings) node.bindings = sb.bindings
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      function ScrollView(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const p = props || {}
        const sb = splitStyle(p)
        const node = {
          type: 'scroll',
          id: nextId(),
          style: sb.style,
          children: flatten(children)
        }
        if (sb.bindings) node.bindings = sb.bindings
        if (typeof p.onScroll === 'function') node.onScroll = p.onScroll
        if (typeof p.onRefresh === 'function') node.onRefresh = p.onRefresh
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      // MapView(props) — нативная MKMapView обёртка. region/pins/mapType
      // — обычные props (можно делать реактивными через thunks как и стиль).
      // onRegionChange / onPinTap — handler'ы.
      function MapView(props) {
        const p = props || {}
        const sb = splitStyle(p)
        const node = {
          type: 'map',
          id: nextId(),
          style: sb.style,
          region: p.region || null,
          pins: Array.isArray(p.pins) ? p.pins : [],
          mapType: typeof p.mapType === 'string' ? p.mapType : 'standard',
          children: [],
        }
        if (sb.bindings) node.bindings = sb.bindings
        if (typeof p.onRegionChange === 'function') node.onRegionChange = p.onRegionChange
        if (typeof p.onPinTap === 'function') node.onPinTap = p.onPinTap
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      // Slot(props, thunk) — реактивный flex-контейнер. thunk возвращает
      // либо одиночный RenderNode, либо массив, либо null/undefined.
      // Когда сигналы внутри thunk'а меняются, native пересоберёт ТОЛЬКО
      // детей этого контейнера (минуя mount-rerun всего дерева).
      //
      // Аналог <For>/<Show> в Solid и v-for/v-if в Vue Vapor.
      function Slot(props /* , thunk */) {
        const thunk = arguments[1]
        if (typeof thunk !== 'function') {
          throw new Error('Slot requires a thunk function as second argument')
        }
        const sb = splitStyle(props)
        // Initial children — untracked eval даёт правильный mount-state,
        // effect зарегистрируется в registerBindings и будет диффить дальше.
        let initialChildren = []
        try {
          const r = untracked(thunk)
          initialChildren = Array.isArray(r)
            ? r.filter(function (x) { return x != null && x !== false && x !== true })
            : (r != null && r !== false && r !== true ? [r] : [])
        } catch (e) { /* empty */ }
        const node = {
          type: 'view',
          id: nextId(),
          style: sb.style,
          children: initialChildren,
          slotThunk: thunk,
        }
        if (sb.bindings) node.bindings = sb.bindings
        attachGestures(node, props)
        if (props && props.key !== undefined) node.key = String(props.key)
        return node
      }

      function TextInput(props) {
        const p = props || {}
        const sb = splitStyle(p)
        const node = {
          type: 'textInput',
          id: nextId(),
          style: sb.style,
          value: (typeof p.value === 'string') ? p.value : '',
          placeholder: (typeof p.placeholder === 'string') ? p.placeholder : undefined,
          keyboardType: p.keyboardType,
          returnKey: p.returnKey,
          autocapitalize: p.autocapitalize,
          autocorrect: p.autocorrect,
          secure: p.secure
        }
        if (sb.bindings) node.bindings = sb.bindings
        if (typeof p.onChange === 'function') node.onChange = p.onChange
        if (typeof p.onSubmit === 'function') node.onSubmit = p.onSubmit
        if (typeof p.onFocus === 'function') node.onFocus = p.onFocus
        if (typeof p.onBlur === 'function') node.onBlur = p.onBlur
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      // ─────────── animated values ───────────
      // AnimatedValue — opaque-binding к native-side CALayer.property.
      // Сам объект не триггерит реактивный re-render: его задача
      // обходить JS-loop вообще и двигать пиксели на render-сервере.
      //
      // Используется так:
      //   const x = animated(0)
      //   View({transform: {translateX: x}})    // парсер видит __anim, биндит
      //   x.set(40)                              // мгновенно
      //   x.animateTo(0, {duration: 300, easing: 'spring'})
      //   x.stop()                               // freeze в presentation-точке
      let _animSeq = 0
      function _nextAnimId() {
        _animSeq = (_animSeq | 0) + 1
        return _animSeq
      }
      function AnimatedValue(initial) {
        const v = (typeof initial === 'number') ? initial : 0
        this.__anim = _nextAnimId()
        this._current = v
        lumen._animValue.create(this.__anim, v)
      }
      AnimatedValue.prototype.set = function (v) {
        const n = +v
        this._current = n
        lumen._animValue.set(this.__anim, n)
      }
      AnimatedValue.prototype.animateTo = function (v, opts) {
        const n = +v
        this._current = n
        const o = opts || {}
        const dur = (typeof o.duration === 'number') ? o.duration : 300
        const easing = (typeof o.easing === 'string') ? o.easing : 'easeOut'
        lumen._animValue.animateTo(this.__anim, n, dur, easing)
      }
      AnimatedValue.prototype.stop = function () {
        lumen._animValue.stop(this.__anim)
        this._current = lumen._animValue.current(this.__anim)
        return this._current
      }
      AnimatedValue.prototype.current = function () { return this._current }
      AnimatedValue.prototype.release = function () {
        lumen._animValue.release(this.__anim)
      }
      function animated(initial) { return new AnimatedValue(initial) }

      // ─────────── safe area ───────────
      // Native пушит insets через lumen._updateSafeArea(top, bottom, left, right).
      // На JS-стороне это signal'ы, поэтому любой компонент который читает
      // lumen.safeArea.top перерендерится при изменении (rotation, keyboard).
      const _saT = signal(0), _saB = signal(0), _saL = signal(0), _saR = signal(0)
      Object.defineProperty(lumen, 'safeArea', {
        value: Object.freeze({
          get top()    { return _saT.value },
          get bottom() { return _saB.value },
          get left()   { return _saL.value },
          get right()  { return _saR.value },
        }),
        writable: false, configurable: false
      })
      lumen._updateSafeArea = function (t, b, l, r) {
        _saT.value = t
        _saB.value = b
        _saL.value = l
        _saR.value = r
      }

      // ─────────── app lifecycle ───────────
      // Native пушит state через lumen._updateAppState(state). Чтение
      // `lumen.appState` из thunk-prop'а делает узел подписчиком, фастапп
      // перерисуется при transition'е foreground↔background.
      const _appState = signal(typeof lumen._appStateInitial === 'string'
                               ? lumen._appStateInitial : 'active')
      Object.defineProperty(lumen, 'appState', {
        get: function () { return _appState.value },
        configurable: false
      })
      lumen._updateAppState = function (s) { _appState.value = String(s) }

      // ─────────── appearance ───────────
      // lumen.appearance.theme → 'dark' | 'light'. Реактивно — UITraitChange
      // observer на UIWindowScene фаерит при смене системной темы.
      const _theme = signal(typeof lumen._themeInitial === 'string'
                            ? lumen._themeInitial : 'light')
      Object.defineProperty(lumen, 'appearance', {
        value: Object.freeze({
          get theme() { return _theme.value },
        }),
        writable: false, configurable: false
      })
      lumen._updateTheme = function (t) { _theme.value = String(t) }

      // ─────────── network ───────────
      // lumen.network.{online, type}. NWPathMonitor пушит обновления;
      // первый pathUpdate приходит сразу после .start, поэтому initial
      // ('unknown') живёт миллисекунды.
      const _netOnline = signal(typeof lumen._networkOnlineInitial === 'boolean'
                                ? lumen._networkOnlineInitial : true)
      const _netType = signal(typeof lumen._networkTypeInitial === 'string'
                              ? lumen._networkTypeInitial : 'unknown')
      Object.defineProperty(lumen, 'network', {
        value: Object.freeze({
          get online() { return _netOnline.value },
          get type()   { return _netType.value },
        }),
        writable: false, configurable: false
      })
      lumen._updateNetwork = function (online, type) {
        _netOnline.value = !!online
        _netType.value = String(type)
      }

      // ─────────── tabs ───────────
      // Native bridge выдаёт JSON-строки (Swift 6 Sendable не пропускает
      // объекты как return type). Здесь оборачиваем в человеческий API.
      if (lumen._tabsRaw) {
        const raw = lumen._tabsRaw
        const parse = function (s) { return (s === 'null' || s == null) ? null : JSON.parse(s) }
        lumen.tabs = {
          list:     function ()    { return parse(raw._listJSON()) || [] },
          current:  function ()    { return parse(raw._currentJSON()) },
          own:      function ()    { return parse(raw._ownJSON()) },
          open:     function (url) { return raw.open(url == null ? null : String(url)) },
          navigate: function (url) { if (url != null) raw.navigate(String(url)) },
          close:    function (id)  { raw.close(id == null ? null : String(id)) },
          switch:   function (id)  { raw['switch'](String(id)) },
          // Push-канал 'tabs': TabsStore через withObservationTracking
          // фаерит на любое изменение списка/активной/title/loading/URL.
          subscribe: function (fn) {
            if (!lumen._notify) return function () {}
            const id = lumen._notify._subscribe('tabs', fn)
            return function () { lumen._notify._unsubscribe('tabs', id) }
          },
        }
      }

      // ─────────── history ───────────
      // subscribe(fn) → unsubscribe(). Под капотом — generic native push-канал
      // 'history'. HistoryStore.persist() в Swift делает NativeNotifier.fire,
      // тот обходит все живые JSEngine'ы и зовёт зарегистрированные callback'и.
      if (lumen._historyRaw) {
        const raw = lumen._historyRaw
        lumen.history = {
          list:   function ()    { try { return JSON.parse(raw._listJSON()) } catch (e) { return [] } },
          remove: function (id)  { if (id != null) raw._remove(String(id)) },
          clear:  function ()    { raw._clear() },
          subscribe: function (fn) {
            if (!lumen._notify) return function () {}
            const id = lumen._notify._subscribe('history', fn)
            return function () { lumen._notify._unsubscribe('history', id) }
          },
        }
      }

      // ─────────── bindings → fine-grained effects ───────────
      // После lumen.render(tree) проходим по дереву и для каждого binding'а
      // (реактивного prop'а) создаём per-prop effect. Effect живёт в scope'е
      // mount'а — при пересоздании mount-effect'а scope dispose'ится.
      //
      // Один thunk → один effect → один patch вызов в native при изменении
      // именно тех signal'ов которые этот thunk читает. Это Vapor-style:
      // mount-effect не реагирует на signal-changes если все reactivity
      // вынесена в thunks.
      // nodeScopes — per-id EffectScope. Каждый смонтированный узел владеет
      // своими effect'ами (per-prop bindings + slot rebuild). Native при
      // unmount'е (reconcile remove или мьют через _replaceChildren) зовёт
      // `lumen._disposeNodes([id...])`, мы dispose'им scope этих id'шников
      // → их effect'ы умирают, утечек нет.
      //
      // Slot больше не держит ручной childScope: каждый ребёнок имеет свой
      // node-scope, и nativу нативный reconcile сам решает кого снести.
      // Это путь к будущему keyed reuse (тогда _disposeNodes придёт только
      // на реально удалённых ids).
      const nodeScopes = new Map()

      function registerBindings(node) {
        if (!node || typeof node !== 'object') return

        if (!node.id) {
          if (node.children) {
            for (let i = 0; i < node.children.length; i++) registerBindings(node.children[i])
          }
          return
        }

        // Re-register на тот же id (например slot re-run с теми же ids):
        // dispose старый scope чтобы effect'ы не дублировались.
        const existing = nodeScopes.get(node.id)
        if (existing) existing.dispose()

        const scope = new EffectScope()
        nodeScopes.set(node.id, scope)

        scope.run(function () {
          if (node.bindings) {
            const id = node.id
            for (let i = 0; i < node.bindings.length; i++) {
              const b = node.bindings[i]
              const prop = b[0], thunk = b[1]
              effect(function () {
                const v = thunk()
                lumen._patchProp(id, prop, v)
              })
            }
          }
          if (node.slotThunk) {
            const id = node.id
            const slotThunk = node.slotThunk
            effect(function () {
              const result = slotThunk()
              const arr = Array.isArray(result)
                ? result.filter(function (x) { return x != null && x !== false && x !== true })
                : (result != null && result !== false && result !== true ? [result] : [])
              lumen._replaceChildren(id, arr)
              // Native reconcile удалит старых детей и вернёт нам их ids
              // через _disposeNodes; scope'ы детей мы регистрируем заново
              // под current scope этой ноды (slot).
              for (let i = 0; i < arr.length; i++) registerBindings(arr[i])
            })
            return
          }
          if (node.children) {
            for (let i = 0; i < node.children.length; i++) registerBindings(node.children[i])
          }
        })
      }

      // Native колбэкает сюда после reconcile когда часть mounted-дерева
      // снесли. Один вызов на батч — дёшево даже на сотнях ids.
      lumen._disposeNodes = function (ids) {
        if (!ids || !ids.length) return
        for (let i = 0; i < ids.length; i++) {
          const id = ids[i]
          const s = nodeScopes.get(id)
          if (s) { s.dispose(); nodeScopes.delete(id) }
        }
      }

      // ─────────── mount ───────────
      // Vapor-mode mount: одно тело effect'а на всю компоненту, внутри
      // которого scope.run(...) изолирует все per-prop effect'ы. Если
      // component-функция всё-таки читает .value напрямую (а не через thunks),
      // mount-effect ре-ранется как в старой модели — но scope cleanups
      // disposes старые binding'и чтобы не было утечек.
      function mount(component) {
        let scope = null
        return effect(function () {
          if (scope) scope.dispose()
          scope = new EffectScope()
          const tree = component()
          lumen.render(tree)
          scope.run(function () { registerBindings(tree) })
        })
      }

      // ─────────── exports ───────────
      const exportsObj = {
        signal: signal, computed: computed, effect: effect,
        View: View, Text: Text, Pressable: Pressable,
        Image: Image, VirtualList: VirtualList,
        TextInput: TextInput, ScrollView: ScrollView,
        Blur: Blur, Glass: Glass,
        Slot: Slot,
        MapView: MapView,
        mount: mount, animated: animated
      }

      // Глобалы для quick-use без import-семантики
      globalThis.signal = signal
      globalThis.computed = computed
      globalThis.effect = effect
      globalThis.View = View
      globalThis.Text = Text
      globalThis.Pressable = Pressable
      globalThis.Image = Image
      globalThis.VirtualList = VirtualList
      globalThis.TextInput = TextInput
      globalThis.ScrollView = ScrollView
      globalThis.Blur = Blur
      globalThis.Glass = Glass
      globalThis.Slot = Slot
      globalThis.MapView = MapView
      globalThis.mount = mount
      globalThis.animated = animated

      // Также через lumen.core для тех кто хочет namespace
      lumen.core = exportsObj
      lumen.animated = animated
    })();
    """#
}
