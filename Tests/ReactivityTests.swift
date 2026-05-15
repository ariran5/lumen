import XCTest
import JavaScriptCore
import QuartzCore
@testable import Lumen

/// End-to-end checks of fine-grained reactivity: signal → thunk → effect
/// → `lumen._patchProp` → applyPatch → CALayer + reconcile.
///
/// These tests catch a class of bugs where `reconcile` overwrites a just-applied
/// per-prop patch from a stale lastTree. The specific case they catch:
/// a sibling slot rebuilds on signal change, its
/// `_replaceChildren` triggers a full `relayout()`, and without the same-id
/// short-circuit in reconcile, visual styles of an unrelated subtree
/// get reverted to the initial value, which looks like flicker.
@MainActor
final class ReactivityTests: XCTestCase {

    // MARK: - Fixture

    /// Fresh fixture per test — Swift 6 strict concurrency dislikes
    /// stored properties of @MainActor types on XCTestCase (setUp/tearDown
    /// are technically non-isolated). Each test takes local values.
    private func makeFixture() -> (engine: JSEngine, renderer: Renderer, root: CALayer) {
        let root = CALayer()
        // Renderer.relayout() bails early if width==0 or height==0
        // (see guard in relayout). bounds on a bare CALayer without a parent
        // isn't derived from frame automatically — set it explicitly.
        root.bounds = CGRect(x: 0, y: 0, width: 320, height: 480)
        root.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let renderer = Renderer(rootLayer: root)
        let engine = JSEngine(origin: .system)
        engine.onLog = { level, msg in
            print("[js \(level.rawValue)] \(msg)")
        }
        engine.installRenderBridge(renderer: renderer)
        engine.installPatchBridge()
        _ = engine.eval(CoreFramework.script)
        return (engine, renderer, root)
    }

    /// JSC processes Promise.resolve().then via the context's runloop.
    /// In tests JS-side scheduleFlush enqueues microtasks that won't run
    /// until we let the runloop work. A 50ms pump gives the microtask
    /// queue several chances to drain.
    private func flushMicrotasks(_ ms: Double = 50) {
        let deadline = Date(timeIntervalSinceNow: ms / 1000.0)
        RunLoop.current.run(mode: .default, before: deadline)
    }

    /// Extracts CGColor from the first character's NSAttributedString in a Text layer.
    /// This is the "current color" of the Text node after patching — it lives in
    /// the `.foregroundColor` attribute, not in a separate CALayer property.
    private func textColor(of layer: CALayer?) -> CGColor? {
        guard let textLayer = layer as? CATextLayer,
              let attributed = textLayer.string as? NSAttributedString,
              attributed.length > 0 else { return nil }
        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil)
        if let ui = color as? UIColor { return ui.cgColor }
        return nil
    }

    private func cgColorHex(_ c: CGColor?) -> String {
        guard let c, let comps = c.components, comps.count >= 3 else { return "<nil>" }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Layer at a DFS path in the tree. Convenient way to address nodes without
    /// extracting ids from JS.
    private func descend(_ root: CALayer, _ path: [Int]) -> CALayer? {
        var current: CALayer = root
        for idx in path {
            guard let subs = current.sublayers, idx < subs.count else { return nil }
            current = subs[idx]
        }
        return current
    }

    private func debugDumpTree(_ layer: CALayer, prefix: String = "", depth: Int = 0) {
        let indent = String(repeating: "  ", count: depth)
        let kind = String(describing: type(of: layer))
        let bounds = layer.bounds
        let text: String = {
            if let tl = layer as? CATextLayer,
               let s = tl.string as? NSAttributedString { return " text=\"\(s.string)\"" }
            return ""
        }()
        print("\(prefix) \(indent)\(kind) bounds=\(bounds)\(text)")
        for sub in layer.sublayers ?? [] {
            debugDumpTree(sub, prefix: prefix, depth: depth + 1)
        }
    }

    // MARK: - Smoke

    /// The simplest test — eval lumen.render with a single View+Text directly,
    /// no mount/effect/signal. Verifies that the JS↔Swift bridge works.
    func testSmokeDirectRender() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        _ = engine.eval("lumen.render(View({}, Text({ color: '#FF0000' }, 'hi')))")
        XCTAssertGreaterThan(root.sublayers?.count ?? 0, 0,
                             "lumen.render should produce sublayers")
    }

    // MARK: - The flicker bug

    /// Reproduces the TabBar flicker: signal change rebuilds a sibling slot
    /// (tab content), which triggers a full relayout. Without the same-id reconcile
    /// short-circuit, applyAll re-applies stale tree style to the unrelated
    /// tab-bar Text and overwrites the just-applied per-prop color patch.
    func testSiblingSlotRebuildPreservesPerPropPatchedColor() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const tab = signal('home')

        // Slot A — "tab content", subscribed to tab.value via slotThunk and
        // rebuilt on each switch. Simulates the tab-content slot in index.ts.
        const contentSlot = Slot({}, () => Text(
          { color: '#000000' },
          tab.value === 'home' ? 'HOME PAGE' : 'OTHER PAGE'
        ))

        // Slot B — "tab bar", does NOT read tab.value in its slotThunk. Only
        // the inner Text uses a per-prop color thunk. Before the fix its color
        // was overwritten on every switch — the relayout initiated by
        // contentSlot walked over the tab-bar Text and applyAll repainted
        // the layer's color from stale lastTree.style.color.
        const barSlot = Slot({}, () => Text(
          { color: () => tab.value === 'home' ? '#FFFFFF' : '#A8A8B8' },
          'TAB BAR ITEM'
        ))

        mount(() => View({}, contentSlot, barSlot))
        globalThis.__switch = function (v) { tab.value = v }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        // Tree: root > rootView > [contentSlot wrapper, barSlot wrapper]
        // → barSlot wrapper.children[0] = Text "TAB BAR ITEM".
        let barTextLayer = descend(root, [0, 1, 0])
        XCTAssertEqual(cgColorHex(textColor(of: barTextLayer)), "#FFFFFF",
                       "initial color should be active white")

        // Switch to 'other'. This triggers rebuild of contentSlot + per-prop
        // patch of tab-bar Text. Without the fix, reconcile rewrites the color
        // back from the stale tree → stays #FFFFFF.
        _ = engine.eval("__switch('other')")
        flushMicrotasks()

        XCTAssertEqual(cgColorHex(textColor(of: barTextLayer)), "#A8A8B8",
                       "after switch, color must reflect patched value, not stale tree")

        // Back to 'home' — color must update too.
        _ = engine.eval("__switch('home')")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: barTextLayer)), "#FFFFFF",
                       "switching back should re-activate color")
    }

    // MARK: - Multiple sibling thunks on same signal

    /// All N color thunks reading the same signal must fire
    /// on a signal change. No "first/last effect" drop-out.
    func testAllSiblingThunksOnSameSignalFire() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const active = signal(0)
        const makeText = (i) => Text(
          { color: () => active.value === i ? '#FF0000' : '#00FF00' },
          'item-' + i
        )

        // Sibling slot to trigger full relayout on signal change.
        const sib = Slot({}, () => Text({}, 'tick-' + active.value))

        mount(() => View({},
          sib,
          makeText(0), makeText(1), makeText(2), makeText(3), makeText(4)
        ))

        globalThis.__select = function (i) { active.value = i }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        let textLayers = (1...5).map { descend(root, [0, $0]) }
        XCTAssertEqual(textLayers.compactMap { $0 }.count, 5, "all 5 text layers mounted")

        // Initial: active=0 → first red, others green.
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[0])), "#FF0000")
        for i in 1..<5 {
            XCTAssertEqual(cgColorHex(textColor(of: textLayers[i])), "#00FF00",
                           "text-\(i) green initially")
        }

        // Select middle — all should switch correctly.
        _ = engine.eval("__select(2)")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[0])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[1])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[2])), "#FF0000")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[3])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[4])), "#00FF00")

        // Last one.
        _ = engine.eval("__select(4)")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[0])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[4])), "#FF0000")
    }

    // MARK: - Computed

    /// Computed = signal-derived. Patch must follow through the chain.
    func testComputedDrivesPatches() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const base = signal(1)
        const doubled = computed(() => base.value * 2)

        mount(() => View({},
          Text({
            opacity: () => doubled.value / 10
          }, 'op')
        ))

        globalThis.__set = function (v) { base.value = v }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        let text = descend(root, [0, 0])
        XCTAssertEqual(Double(text?.opacity ?? -1), 0.2, accuracy: 0.001,
                       "initial 1*2/10 = 0.2")

        _ = engine.eval("__set(3)")
        flushMicrotasks()
        XCTAssertEqual(Double(text?.opacity ?? -1), 0.6, accuracy: 0.001,
                       "after set(3): 3*2/10 = 0.6")

        _ = engine.eval("__set(5)")
        flushMicrotasks()
        XCTAssertEqual(Double(text?.opacity ?? -1), 1.0, accuracy: 0.001,
                       "after set(5): 5*2/10 = 1.0")
    }

    // MARK: - Text content patching

    func testReactiveTextContentUpdatesAndRelayoutsCorrectly() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const label = signal('short')
        mount(() => View({},
          Text({ fontSize: 14 }, () => label.value)
        ))
        globalThis.__set = function (v) { label.value = v }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        let textLayer = descend(root, [0, 0]) as? CATextLayer
        XCTAssertNotNil(textLayer)
        XCTAssertEqual((textLayer?.string as? NSAttributedString)?.string, "short")

        _ = engine.eval("__set('this is a much longer label')")
        flushMicrotasks()

        XCTAssertEqual((textLayer?.string as? NSAttributedString)?.string,
                       "this is a much longer label",
                       "text content should reflect signal value")
    }

    // MARK: - Opacity / backgroundColor through sibling-rebuild

    /// Same as color: opacity and backgroundColor thunks must not
    /// be reset on a relayout caused by a sibling slot.
    func testOpacityAndBackgroundSurviveSiblingRebuild() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const toggle = signal(false)
        const sib = Slot({}, () => Text({}, toggle.value ? 'on' : 'off'))
        mount(() => View({},
          sib,
          View({
            opacity: () => toggle.value ? 1.0 : 0.3,
            backgroundColor: () => toggle.value ? '#00FF00' : '#FF0000'
          })
        ))
        globalThis.__flip = function () { toggle.value = !toggle.value }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        let target = descend(root, [0, 1])
        XCTAssertEqual(Double(target?.opacity ?? -1), 0.3, accuracy: 0.001)
        XCTAssertEqual(cgColorHex(target?.backgroundColor), "#FF0000")

        _ = engine.eval("__flip()")  // false → true
        flushMicrotasks()
        XCTAssertEqual(Double(target?.opacity ?? -1), 1.0, accuracy: 0.001)
        XCTAssertEqual(cgColorHex(target?.backgroundColor), "#00FF00")

        // Several switches in a row in one tick — pendingEffects collapses
        // duplicates, the effect runs once for the final value.
        // 3 flips from true: true→false→true→false. Final = false.
        _ = engine.eval("__flip(); __flip(); __flip()")
        flushMicrotasks()
        XCTAssertEqual(Double(target?.opacity ?? -1), 0.3, accuracy: 0.001,
                       "after 3 flips from true → false")
        XCTAssertEqual(cgColorHex(target?.backgroundColor), "#FF0000")
    }

    // MARK: - Slot show/hide

    /// When a Slot drops a node (renders null), its binding scopes
    /// must be disposed — subsequent signal changes must not
    /// throw warnings and must not patch a layer that no longer exists.
    func testHiddenSlotChildrenStopReceivingPatches() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const visible = signal(true)
        const color = signal('#FF0000')

        mount(() => View({},
          Slot({}, () => visible.value
            ? Text({ color: () => color.value }, 'hi')
            : null)
        ))
        globalThis.__hide = function () { visible.value = false }
        globalThis.__setColor = function (c) { color.value = c }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        let slotWrapper = descend(root, [0, 0])
        XCTAssertEqual(slotWrapper?.sublayers?.count, 1, "text mounted initially")
        XCTAssertEqual(cgColorHex(textColor(of: slotWrapper?.sublayers?[0])), "#FF0000")

        _ = engine.eval("__hide()")
        flushMicrotasks()
        XCTAssertEqual(slotWrapper?.sublayers?.count ?? 0, 0, "text removed")

        // After removal, color updates must not crash.
        _ = engine.eval("__setColor('#00FF00')")
        flushMicrotasks()
        // Still empty, nothing came back to life.
        XCTAssertEqual(slotWrapper?.sublayers?.count ?? 0, 0, "no zombie text")
    }

    /// Snapshot cycle: shown → hidden → shown. Re-mount must
    /// attach new thunk bindings; patches on the new tree work.
    func testShowHideShowReattachesPatches() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const show = signal(true)
        const c = signal('#111111')

        mount(() => View({},
          Slot({}, () => show.value
            ? Text({ color: () => c.value }, 'x')
            : null)
        ))
        globalThis.__show = function (v) { show.value = v }
        globalThis.__c = function (v) { c.value = v }
        """
        _ = engine.eval(script)
        flushMicrotasks()
        let slot = descend(root, [0, 0])

        _ = engine.eval("__show(false)")
        flushMicrotasks()
        XCTAssertEqual(slot?.sublayers?.count ?? 0, 0)

        _ = engine.eval("__show(true)")
        flushMicrotasks()
        XCTAssertEqual(slot?.sublayers?.count, 1, "remounted on re-show")
        XCTAssertEqual(cgColorHex(textColor(of: slot?.sublayers?[0])), "#111111",
                       "initial color from current signal value")

        _ = engine.eval("__c('#ABCDEF')")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: slot?.sublayers?[0])), "#ABCDEF",
                       "patches on re-mounted subtree work")
    }

    // MARK: - Stress: multiple signal changes batched

    /// N signal changes in one tick must collapse into one flush
    /// and produce the correct final state without intermediate flickers.
    func testBatchedSignalChangesYieldFinalValue() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const s = signal('a')
        mount(() => View({},
          Text({ color: () => s.value === 'final' ? '#00FF00' : '#FF0000' }, 'x')
        ))
        globalThis.__run = function () {
          s.value = 'b'; s.value = 'c'; s.value = 'd'; s.value = 'final'
        }
        """
        _ = engine.eval(script)
        flushMicrotasks()
        let text = descend(root, [0, 0])
        XCTAssertEqual(cgColorHex(textColor(of: text)), "#FF0000")

        _ = engine.eval("__run()")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: text)), "#00FF00",
                       "after batched changes, final value wins")
    }

    // MARK: - Same-signal touching outer scope

    /// If an outer scope (e.g. mount-component) reads signal.value directly,
    /// the mount-effect rebuilds the whole tree. This is a valid mode — verify
    /// it doesn't crash and doesn't duplicate bindings.
    func testOuterSignalReadCausesFullRebuild() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const v = signal(1)
        mount(() => {
          v.value  // ← mount-effect subscribes here
          return View({},
            Text({ color: () => v.value > 5 ? '#00FF00' : '#FF0000' }, String(v.value))
          )
        })
        globalThis.__set = function (n) { v.value = n }
        """
        _ = engine.eval(script)
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: descend(root, [0, 0]))), "#FF0000")

        _ = engine.eval("__set(10)")
        flushMicrotasks()

        // After full rebuild — a new text layer, but color must match the new
        // condition. Re-address via DFS (ids changed, but the tree position
        // is the same).
        XCTAssertEqual(cgColorHex(textColor(of: descend(root, [0, 0]))), "#00FF00",
                       "after outer rebuild text reflects new condition")
    }

    // MARK: - Nested deep tree

    /// A sibling slot rebuild must not blanket-overwrite styles of
    /// deeply nested nodes in another subtree. Without our fix
    /// applyAll would recurse through the whole tree and repaint every Text
    /// from stale `next.style.color`.
    func testDeepNestedSubtreeSurvivesSiblingRebuild() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const tick = signal(0)
        const accent = signal('#AA0000')

        mount(() => View({},
          Slot({}, () => Text({}, 'tick=' + tick.value)),
          View({}, View({}, View({},
            Text({ color: () => accent.value }, 'deep')
          )))
        ))
        globalThis.__tick = function () { tick.value++ }
        globalThis.__set = function (c) { accent.value = c }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        // root → root[0] → View[1] (deep wrapper) → View[0] → View[0] → Text[0]
        let deepText = descend(root, [0, 1, 0, 0, 0])
        XCTAssertEqual(cgColorHex(textColor(of: deepText)), "#AA0000")

        // Change accent — Text must pick it up.
        _ = engine.eval("__set('#00AAFF')")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: deepText)), "#00AAFF")

        // Now trigger sibling slot rebuilds. They must NOT revert
        // the color — this is the classic "flickering" patch.
        for _ in 0..<5 {
            _ = engine.eval("__tick()")
            flushMicrotasks()
            XCTAssertEqual(cgColorHex(textColor(of: deepText)), "#00AAFF",
                           "deep nested color survives sibling rebuild")
        }
    }

    // MARK: - Mixed static + reactive

    /// Mixed node: one prop static, the other a thunk. A sibling rebuild
    /// must touch NEITHER the static one (it stays) NOR the thunked one (it
    /// is in patch state).
    func testMixedStaticAndReactivePropsCoexist() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // retain — bridge captures weakly
        let script = """
        const v = signal(false)
        const sib = Slot({}, () => Text({}, String(v.value)))
        mount(() => View({},
          sib,
          View({
            backgroundColor: '#123456',     // static
            opacity: () => v.value ? 1 : 0.5  // reactive
          })
        ))
        globalThis.__flip = function () { v.value = !v.value }
        """
        _ = engine.eval(script)
        flushMicrotasks()

        let target = descend(root, [0, 1])
        XCTAssertEqual(cgColorHex(target?.backgroundColor), "#123456",
                       "static bg applied")
        XCTAssertEqual(Double(target?.opacity ?? -1), 0.5, accuracy: 0.001)

        _ = engine.eval("__flip()")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(target?.backgroundColor), "#123456",
                       "static bg preserved through reactivity tick")
        XCTAssertEqual(Double(target?.opacity ?? -1), 1.0, accuracy: 0.001)

        _ = engine.eval("__flip(); __flip(); __flip(); __flip(); __flip()")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(target?.backgroundColor), "#123456",
                       "static bg untouched across many flips")
    }
}
