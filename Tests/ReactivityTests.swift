import XCTest
import JavaScriptCore
import QuartzCore
@testable import Lumen

/// End-to-end проверки fine-grained реактивности: signal → thunk → effect
/// → `lumen._patchProp` → applyPatch → CALayer + reconcile.
///
/// Эти тесты ловят класс багов где `reconcile` перезаписывает только что
/// положенный per-prop patch из stale lastTree. Конкретный случай, который
/// они отлавливают: sibling slot rebuild'ится по signal change, его
/// `_replaceChildren` запускает full `relayout()`, и без same-id
/// short-circuit'а в reconcile визуальные стили unrelated subtree'я
/// перетираются обратно к initial значению, что выглядит как мелькание.
@MainActor
final class ReactivityTests: XCTestCase {

    // MARK: - Fixture

    /// Свежий fixture per test — Swift 6 strict concurrency не любит
    /// stored properties с @MainActor типами на XCTestCase (setUp/tearDown
    /// технически non-isolated). Каждый тест берёт локальные значения.
    private func makeFixture() -> (engine: JSEngine, renderer: Renderer, root: CALayer) {
        let root = CALayer()
        // Renderer.relayout() ранее bail'ится если width==0 или height==0
        // (см. guard в relayout). bounds на голом CALayer'е без parent'а
        // не выводится из frame автоматически — ставим явно.
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

    /// JSC обрабатывает Promise.resolve().then через context'овый runloop.
    /// В тестах JS-side scheduleFlush ставит микротаски, которые сами не
    /// сработают пока мы не дадим runloop'у поработать. Pump в 50ms даёт
    /// несколько шансов микротасковой очереди отстреляться.
    private func flushMicrotasks(_ ms: Double = 50) {
        let deadline = Date(timeIntervalSinceNow: ms / 1000.0)
        RunLoop.current.run(mode: .default, before: deadline)
    }

    /// Достаёт CGColor из NSAttributedString'а первого character'а Text-layer'а.
    /// Это «текущий цвет» Text-узла после patch'а — он живёт в
    /// `.foregroundColor` атрибуте, а не в отдельном CALayer'овом свойстве.
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

    /// Layer на DFS-пути в дереве. Удобно адресоваться к узлам без
    /// выпиливания id'шников из JS.
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

    /// Самый простой тест — eval'нем lumen.render с одним View+Text напрямую,
    /// без mount/effect/signal. Проверяем что JS↔Swift bridge работает.
    func testSmokeDirectRender() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
        _ = engine.eval("lumen.render(View({}, Text({ color: '#FF0000' }, 'hi')))")
        XCTAssertGreaterThan(root.sublayers?.count ?? 0, 0,
                             "lumen.render should produce sublayers")
    }

    // MARK: - The flicker bug

    /// Reproduces the TabBar flicker: signal change rebuilds a sibling slot
    /// (tab content), which triggers a full relayout. Без same-id reconcile
    /// short-circuit'а applyAll re-applies stale tree style к unrelated
    /// tab-bar Text'у и затирает только что положенный per-prop color patch.
    func testSiblingSlotRebuildPreservesPerPropPatchedColor() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
        let script = """
        const tab = signal('home')

        // Слот A — «контент таба», подписан на tab.value через slotThunk и
        // пересобирается на каждый switch. Симулирует index.ts'овский
        // tab-content slot.
        const contentSlot = Slot({}, () => Text(
          { color: '#000000' },
          tab.value === 'home' ? 'HOME PAGE' : 'OTHER PAGE'
        ))

        // Слот B — «tab bar», НЕ читает tab.value в slotThunk'е. Только
        // Text внутри использует per-prop color thunk. До фикса его цвет
        // перетирался на каждом switch — relayout, инициированный
        // contentSlot'ом, проходил по tab-bar Text'у и applyAll переписывал
        // layer'у цвет из stale lastTree.style.color.
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

        // Switch to 'other'. Это триггерит rebuild contentSlot + per-prop
        // patch tab-bar Text'а. Без фикса reconcile перезапишет цвет
        // обратно из stale tree → останется #FFFFFF.
        _ = engine.eval("__switch('other')")
        flushMicrotasks()

        XCTAssertEqual(cgColorHex(textColor(of: barTextLayer)), "#A8A8B8",
                       "after switch, color must reflect patched value, not stale tree")

        // Возврат на 'home' — цвет тоже должен обновиться.
        _ = engine.eval("__switch('home')")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: barTextLayer)), "#FFFFFF",
                       "switching back should re-activate color")
    }

    // MARK: - Multiple sibling thunks on same signal

    /// Все N color-thunk'ов, читающих один и тот же signal, должны
    /// сработать на signal change. Не выпадает «первый/последний эффект».
    func testAllSiblingThunksOnSameSignalFire() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
        let script = """
        const active = signal(0)
        const makeText = (i) => Text(
          { color: () => active.value === i ? '#FF0000' : '#00FF00' },
          'item-' + i
        )

        // Sibling slot чтобы триггерить full relayout на signal change.
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

        // Переключаем на средний — все должны переключиться корректно.
        _ = engine.eval("__select(2)")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[0])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[1])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[2])), "#FF0000")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[3])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[4])), "#00FF00")

        // Последний.
        _ = engine.eval("__select(4)")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[0])), "#00FF00")
        XCTAssertEqual(cgColorHex(textColor(of: textLayers[4])), "#FF0000")
    }

    // MARK: - Computed

    /// Computed = signal-производный. Patch должен фолловить через цепочку.
    func testComputedDrivesPatches() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
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
        _ = renderer  // удерживаем — bridge капчурит weak
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

    // MARK: - Opacity / backgroundColor через sibling-rebuild

    /// Аналогично color: opacity и backgroundColor thunk'и не должны
    /// сбрасываться при relayout, вызванном sibling slot'ом.
    func testOpacityAndBackgroundSurviveSiblingRebuild() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
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

        // Несколько switch'ей подряд в одном tick'е — pendingEffects схлопывает
        // дубликаты, эффект отрабатывает один раз для финального значения.
        // 3 flip'а из true: true→false→true→false. Финал = false.
        _ = engine.eval("__flip(); __flip(); __flip()")
        flushMicrotasks()
        XCTAssertEqual(Double(target?.opacity ?? -1), 0.3, accuracy: 0.001,
                       "after 3 flips from true → false")
        XCTAssertEqual(cgColorHex(target?.backgroundColor), "#FF0000")
    }

    // MARK: - Slot show/hide

    /// Когда Slot выкидывает узел (показывает null), его binding-scope'ы
    /// должны dispose'иться — последующее signal change'ы не должны
    /// падать с warning'ами и не должны патчить layer которого больше нет.
    func testHiddenSlotChildrenStopReceivingPatches() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
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

        // После удаления update'ы color не должны падать.
        _ = engine.eval("__setColor('#00FF00')")
        flushMicrotasks()
        // По-прежнему пусто, ничего не воскресло.
        XCTAssertEqual(slotWrapper?.sublayers?.count ?? 0, 0, "no zombie text")
    }

    /// Snapshot-цикл: показали → спрятали → показали. Re-mount должен
    /// зацепить новые thunk-binding'и; patches на новом дереве работают.
    func testShowHideShowReattachesPatches() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
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

    /// N signal change'ей в одном tick'е должны схлопнуться в один flush
    /// и дать корректный финальный state без промежуточных мельканий.
    func testBatchedSignalChangesYieldFinalValue() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
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

    /// Если outer scope (e.g. mount-component) читает signal.value напрямую,
    /// mount-эффект пересоберёт всё дерево. Это валидный режим — проверяем
    /// что не падает и не дублирует bindings.
    func testOuterSignalReadCausesFullRebuild() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
        let script = """
        const v = signal(1)
        mount(() => {
          v.value  // ← подписка mount-effect'а
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

        // После full rebuild — новый text layer, но color must match новое
        // условие. Адресуем заново через DFS (ids изменились, но позиция
        // в дереве та же).
        XCTAssertEqual(cgColorHex(textColor(of: descend(root, [0, 0]))), "#00FF00",
                       "after outer rebuild text reflects new condition")
    }

    // MARK: - Nested deep tree

    /// Sibling slot rebuild не должен фронтально перетирать стили
    /// глубоко-вложенных узлов в другом поддереве. Без нашего фикса
    /// applyAll рекурсивно прошёл бы весь дерево и каждый Text перерисовал
    /// бы из stale `next.style.color`.
    func testDeepNestedSubtreeSurvivesSiblingRebuild() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
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

        // Меняем accent — Text должен подхватить.
        _ = engine.eval("__set('#00AAFF')")
        flushMicrotasks()
        XCTAssertEqual(cgColorHex(textColor(of: deepText)), "#00AAFF")

        // Теперь триггерим sibling slot rebuild'ы. Они НЕ должны откатить
        // цвет — это и есть классический «мелькающий» патч.
        for _ in 0..<5 {
            _ = engine.eval("__tick()")
            flushMicrotasks()
            XCTAssertEqual(cgColorHex(textColor(of: deepText)), "#00AAFF",
                           "deep nested color survives sibling rebuild")
        }
    }

    // MARK: - Mixed static + reactive

    /// Mixed узел: один проп статический, второй — thunk. Sibling rebuild
    /// не должен затронуть НИ статический (он остаётся), НИ thunked (он в
    /// patch-state'е).
    func testMixedStaticAndReactivePropsCoexist() {
        let (engine, renderer, root) = makeFixture()
        _ = renderer  // удерживаем — bridge капчурит weak
        let script = """
        const v = signal(false)
        const sib = Slot({}, () => Text({}, String(v.value)))
        mount(() => View({},
          sib,
          View({
            backgroundColor: '#123456',     // статика
            opacity: () => v.value ? 1 : 0.5  // реактив
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
