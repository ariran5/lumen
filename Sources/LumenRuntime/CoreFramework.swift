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

      function Effect(fn) {
        this._fn = fn
        this._signals = new Set()
        this._disposed = false
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
        onScroll: 1
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

      function extractStyle(props) {
        if (!props) return {}
        const style = {}
        for (const k in props) {
          if (!Object.prototype.hasOwnProperty.call(props, k)) continue
          if (!NON_STYLE[k]) style[k] = props[k]
        }
        return style
      }

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
        const node = {
          type: 'view',
          style: extractStyle(props),
          children: flatten(children)
        }
        attachGestures(node, props)
        if (props && props.key !== undefined) node.key = String(props.key)
        return node
      }

      function Text(propsOrText /* , ...rest */) {
        if (typeof propsOrText === 'string' || typeof propsOrText === 'number') {
          return { type: 'text', text: String(propsOrText) }
        }
        const props = propsOrText || {}
        let text = ''
        for (let i = 1; i < arguments.length; i++) {
          const a = arguments[i]
          if (a === null || a === undefined) continue
          text += String(a)
        }
        const node = { type: 'text', style: extractStyle(props), text }
        if (props.key !== undefined) node.key = String(props.key)
        return node
      }

      function Pressable(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const node = {
          type: 'view',
          style: extractStyle(props),
          children: flatten(children)
        }
        attachGestures(node, props)
        if (props && props.key !== undefined) node.key = String(props.key)
        return node
      }

      function Image(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const node = {
          type: 'image',
          style: extractStyle(props),
          source: props && props.source,
          children: flatten(children)
        }
        attachGestures(node, props)
        if (props && props.key !== undefined) node.key = String(props.key)
        return node
      }

      function VirtualList(props) {
        return {
          type: 'virtualList',
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
        const node = {
          type: 'blur',
          style: extractStyle(p),
          intensity: (typeof p.intensity === 'string') ? p.intensity : 'regular',
          children: flatten(children)
        }
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      // Glass — iOS 26 Liquid Glass (UIGlassEffect). На старых iOS откатывается
      // на systemMaterial автоматически. props.variant: 'regular' (по умолчанию)
      // или 'clear' (более прозрачный).
      function Glass(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const p = props || {}
        const intensity = (p.variant === 'clear') ? 'glassClear' : 'glass'
        const node = {
          type: 'blur',
          style: extractStyle(p),
          intensity: intensity,
          children: flatten(children)
        }
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      function ScrollView(props /* , ...children */) {
        const len = arguments.length
        const children = []
        for (let i = 1; i < len; i++) children.push(arguments[i])
        const p = props || {}
        const node = {
          type: 'scroll',
          style: extractStyle(p),
          children: flatten(children)
        }
        if (typeof p.onScroll === 'function') node.onScroll = p.onScroll
        if (p.key !== undefined) node.key = String(p.key)
        return node
      }

      function TextInput(props) {
        const p = props || {}
        const node = {
          type: 'textInput',
          style: extractStyle(p),
          value: (typeof p.value === 'string') ? p.value : '',
          placeholder: (typeof p.placeholder === 'string') ? p.placeholder : undefined,
          keyboardType: p.keyboardType,
          returnKey: p.returnKey,
          autocapitalize: p.autocapitalize,
          autocorrect: p.autocorrect,
          secure: p.secure
        }
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

      // ─────────── tabs ───────────
      // Native bridge выдаёт JSON-строки (Swift 6 Sendable не пропускает
      // объекты как return type). Здесь оборачиваем в человеческий API.
      if (lumen._tabsRaw) {
        const raw = lumen._tabsRaw
        const parse = function (s) { return (s === 'null' || s == null) ? null : JSON.parse(s) }
        lumen.tabs = {
          list:    function ()    { return parse(raw._listJSON()) || [] },
          current: function ()    { return parse(raw._currentJSON()) },
          own:     function ()    { return parse(raw._ownJSON()) },
          open:    function (url) { return raw.open(url == null ? null : String(url)) },
          close:   function (id)  { raw.close(id == null ? null : String(id)) },
          switch:  function (id)  { raw['switch'](String(id)) },
        }
      }

      // ─────────── mount ───────────
      // mount(componentFn) — запускает component, рендерит результат через
      // lumen.render и подписывается на signals. Любой signal-update тригерит
      // повторный render. Reconciler внутри Lumen применит дельту без флэша.
      function mount(component) {
        return effect(function () {
          const tree = component()
          lumen.render(tree)
        })
      }

      // ─────────── exports ───────────
      const exportsObj = {
        signal: signal, computed: computed, effect: effect,
        View: View, Text: Text, Pressable: Pressable,
        Image: Image, VirtualList: VirtualList,
        TextInput: TextInput, ScrollView: ScrollView,
        Blur: Blur, Glass: Glass,
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
      globalThis.mount = mount
      globalThis.animated = animated

      // Также через lumen.core для тех кто хочет namespace
      lumen.core = exportsObj
      lumen.animated = animated
    })();
    """#
}
