import Foundation

/// JS framework `@lumen/core` — globally available in every fast-app.
/// Evolves as part of the runtime: the developer doesn't add an npm package,
/// just writes `View(...)`, `Text(...)`, `signal(...)`, `mount(...)`.
enum CoreFramework {
    static let script: String = #"""
    /* @lumen/core — minimal Flutter-style components + signals */
    ;(function () {
      // ─────────── signals ───────────
      let currentEffect = null
      const pendingEffects = new Set()
      let flushScheduled = false

      // Promise.resolve().then() works in any JS engine with Promise.
      // queueMicrotask is theoretically available in JSC 12.2+ too, but Promise
      // is more reliable as a fallback.
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

      // EffectScope (Vapor/Solid-style) — group of effects with a shared lifetime.
      // unmount node → scope.dispose() → all per-prop effects inside die.
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

      // untracked(fn) — run fn() WITHOUT subscribing the current effect to
      // signals. Used for initial-eval thunks in builders:
      // we need a start value so layout computes correctly, but
      // we do NOT want the mount-effect to catch these signals (otherwise any
      // signal change would trigger a full mount rerun — back to non-Vapor).
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

      // splitStyle splits props into:
      //   style   — static values (applied once)
      //   bindings — reactive thunks `() => signal.value` (per-prop effects)
      //
      // This is the core of the Vapor-style model: a function in a style slot means "reactive".
      // Handlers (onTap et al.) are excluded via NON_STYLE — they're functions too,
      // but for gestures, not bindings.
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
            // Initial untracked eval — gives layout the right measurement
            // for the first render. Effect is registered later via
            // registerBindings and will react to signal changes.
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

      // Each build call gets a unique id — renderer indexes
      // MountedNode by it so JS-side fine-grained effects can
      // patch a specific CALayer via lumen._patchProp(id, key, value).
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
        // text-content thunk: Text({...}, () => sig.value) — reactive text.
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

      // MapView(props) — native MKMapView wrapper. region/pins/mapType
      // — regular props (can be made reactive via thunks like style).
      // onRegionChange / onPinTap — handlers.
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

      // Slot(props, thunk) — reactive flex container. thunk returns
      // either a single RenderNode, an array, or null/undefined.
      // When signals inside the thunk change, native rebuilds ONLY
      // this container's children (bypassing a full mount-rerun).
      //
      // Analog of <For>/<Show> in Solid and v-for/v-if in Vue Vapor.
      function Slot(props /* , thunk */) {
        const thunk = arguments[1]
        if (typeof thunk !== 'function') {
          throw new Error('Slot requires a thunk function as second argument')
        }
        const sb = splitStyle(props)
        // Initial children — untracked eval gives the correct mount state,
        // effect is registered in registerBindings and will diff from there.
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
      // AnimatedValue — opaque binding to native-side CALayer.property.
      // The object itself doesn't trigger a reactive re-render: its job
      // is to bypass the JS loop entirely and move pixels on the render server.
      //
      // Usage:
      //   const x = animated(0)
      //   View({transform: {translateX: x}})    // parser sees __anim, binds
      //   x.set(40)                              // instantly
      //   x.animateTo(0, {duration: 300, easing: 'spring'})
      //   x.stop()                               // freeze at presentation point
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
      // Native pushes insets via lumen._updateSafeArea(top, bottom, left, right).
      // On the JS side these are signals, so any component reading
      // lumen.safeArea.top re-renders on change (rotation, keyboard).
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
      // Native pushes state via lumen._updateAppState(state). Reading
      // `lumen.appState` from a thunk prop makes the node a subscriber, fast-app
      // re-renders on foreground↔background transition.
      const _appState = signal(typeof lumen._appStateInitial === 'string'
                               ? lumen._appStateInitial : 'active')
      Object.defineProperty(lumen, 'appState', {
        get: function () { return _appState.value },
        configurable: false
      })
      lumen._updateAppState = function (s) { _appState.value = String(s) }

      // ─────────── appearance ───────────
      // lumen.appearance.theme → 'dark' | 'light'. Reactive — UITraitChange
      // observer on UIWindowScene fires on system theme change.
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
      // lumen.network.{online, type}. NWPathMonitor pushes updates;
      // first pathUpdate arrives right after .start, so the initial
      // ('unknown') only lives for milliseconds.
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
      // Native bridge returns JSON strings (Swift 6 Sendable rejects
      // objects as a return type). Wrap in a human API here.
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
          // Push channel 'tabs': TabsStore via withObservationTracking
          // fires on any change to list/active/title/loading/URL.
          subscribe: function (fn) {
            if (!lumen._notify) return function () {}
            const id = lumen._notify._subscribe('tabs', fn)
            return function () { lumen._notify._unsubscribe('tabs', id) }
          },
        }
      }

      // ─────────── history ───────────
      // subscribe(fn) → unsubscribe(). Under the hood — generic native push channel
      // 'history'. HistoryStore.persist() in Swift calls NativeNotifier.fire,
      // which walks all live JSEngines and invokes registered callbacks.
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

      // ─────────── notifications ───────────
      // Native bridge provides _nativeRequestPermission/_nativeSchedule (Promise-
      // friendly resolve+reject), cancel/cancelAll, _consumeTaps. Here
      // we wrap in a human API: requestPermission() and schedule()
      // return Promises; onTap.subscribe(fn) subscribes to channel
      // 'notifications.tap' and on fire drains pending tap ids.
      if (lumen.notifications) {
        const native = lumen.notifications
        const cancel = native.cancel
        const cancelAll = native.cancelAll
        lumen.notifications = {
          requestPermission: function () {
            return new Promise(function (resolve) {
              native._nativeRequestPermission(resolve, function () {})
            })
          },
          schedule: function (config) {
            return new Promise(function (resolve, reject) {
              native._nativeSchedule(config || {}, resolve, reject)
            })
          },
          cancel: function (id) { cancel(id == null ? null : String(id)) },
          cancelAll: function () { cancelAll() },
          onTap: {
            // Cold-launch case: user tapped a notification while app was killed,
            // delegate stores the id, JS subscribes later — drain() on
            // subscribe reads accumulated taps.
            subscribe: function (fn) {
              if (!lumen._notify) return function () {}
              function drain() {
                const ids = native._consumeTaps()
                if (!ids || ids.length === 0) return
                for (let i = 0; i < ids.length; i++) fn(ids[i])
              }
              drain()
              const id = lumen._notify._subscribe('notifications.tap', drain)
              return function () { lumen._notify._unsubscribe('notifications.tap', id) }
            },
          },
        }
      }

      // ─────────── linking.onIncoming ───────────
      // Deep-link URLs (lumen://...) arrive via SwiftUI .onOpenURL →
      // IncomingURLStore. subscribe(fn) subscribes to channel
      // 'linking.incoming' and on fire drains pending URLs.
      if (lumen.linking && lumen.linking._consumePending) {
        const consume = lumen.linking._consumePending
        lumen.linking.onIncoming = {
          subscribe: function (fn) {
            if (!lumen._notify) return function () {}
            function drain() {
              const urls = consume()
              if (!urls || urls.length === 0) return
              for (let i = 0; i < urls.length; i++) fn(urls[i])
            }
            drain()
            const id = lumen._notify._subscribe('linking.incoming', drain)
            return function () { lumen._notify._unsubscribe('linking.incoming', id) }
          },
        }
      }

      // ─────────── bindings → fine-grained effects ───────────
      // After lumen.render(tree) we walk the tree and for every binding
      // (reactive prop) create a per-prop effect. Effect lives in the mount
      // scope — on mount-effect re-run the scope is disposed.
      //
      // One thunk → one effect → one patch call into native when exactly
      // the signals this thunk reads change. This is Vapor-style:
      // mount-effect doesn't react to signal changes if all reactivity
      // is in thunks.
      // nodeScopes — per-id EffectScope. Every mounted node owns
      // its effects (per-prop bindings + slot rebuild). On unmount
      // native (reconcile remove or mutation via _replaceChildren) calls
      // `lumen._disposeNodes([id...])`, we dispose scopes of those ids
      // → their effects die, no leaks.
      //
      // Slot no longer keeps a manual childScope: each child has its own
      // node-scope, and native reconcile decides who to remove.
      // This paves the way for future keyed reuse (then _disposeNodes will only
      // arrive for actually removed ids).
      const nodeScopes = new Map()

      function registerBindings(node) {
        if (!node || typeof node !== 'object') return

        if (!node.id) {
          if (node.children) {
            for (let i = 0; i < node.children.length; i++) registerBindings(node.children[i])
          }
          return
        }

        // Re-register on the same id (e.g. slot re-run with the same ids):
        // dispose old scope so effects don't duplicate.
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
              // Native reconcile will remove old children and return their ids
              // via _disposeNodes; we register children scopes again
              // under the current scope of this node (slot).
              for (let i = 0; i < arr.length; i++) registerBindings(arr[i])
            })
            return
          }
          if (node.children) {
            for (let i = 0; i < node.children.length; i++) registerBindings(node.children[i])
          }
        })
      }

      // Native calls back here after reconcile when part of the mounted tree
      // was removed. One call per batch — cheap even with hundreds of ids.
      lumen._disposeNodes = function (ids) {
        if (!ids || !ids.length) return
        for (let i = 0; i < ids.length; i++) {
          const id = ids[i]
          const s = nodeScopes.get(id)
          if (s) { s.dispose(); nodeScopes.delete(id) }
        }
      }

      // ─────────── mount ───────────
      // Vapor-mode mount: one effect body for the whole component, inside
      // which scope.run(...) isolates all per-prop effects. If the
      // component function still reads .value directly (rather than through thunks),
      // mount-effect re-runs as in the old model — but scope cleanup
      // disposes old bindings so there are no leaks.
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

      // Globals for quick-use without import semantics
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

      // Also via lumen.core for those who want the namespace
      lumen.core = exportsObj
      lumen.animated = animated
    })();
    """#
}
