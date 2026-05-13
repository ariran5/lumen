import Foundation
import JavaScriptCore
import QuartzCore
import UIKit

/// Fine-grained patch bridge: применяет одно свойство к одному CALayer
/// по node-id, без обхода всего дерева. Используется JS-side
/// per-prop effect'ами (Vapor-style reactivity).
extension JSEngine {
    func installPatchBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let patch: @convention(block) (Int, String, JSValue) -> Void = { id, key, jsValue in
            MainActor.assumeIsolated {
                Self.applyPatch(id: id, key: key, value: jsValue)
            }
        }
        lumen.setObject(patch, forKeyedSubscript: "_patchProp" as NSString)

        // Slot-thunk вызывает _replaceChildren когда дети контейнера должны
        // пересобраться. Native находит Renderer'а владельца, мутирует
        // lastTree, запускает relayout — это пересобирает поддерево, но
        // НЕ оборачивает re-render всего mount-tree.
        let replaceChildren: @convention(block) (Int, JSValue) -> Void = { id, childrenJSValue in
            MainActor.assumeIsolated {
                Self.applyReplaceChildren(id: id, childrenValue: childrenJSValue)
            }
        }
        lumen.setObject(replaceChildren, forKeyedSubscript: "_replaceChildren" as NSString)
    }

    @MainActor
    private static func applyReplaceChildren(id: Int, childrenValue: JSValue) {
        guard let ref = Renderer.nodeIndex[id],
              let renderer = ref.renderer else { return }

        var newChildren: [RenderNode] = []
        if childrenValue.isArray {
            let length = Int(childrenValue.objectForKeyedSubscript("length")?.toInt32() ?? 0)
            newChildren.reserveCapacity(length)
            for i in 0..<length {
                if let child = childrenValue.atIndex(i),
                   child.isObject,
                   let node = RenderNode.parse(child) {
                    newChildren.append(node)
                }
            }
        }
        renderer.replaceChildren(id: id, newChildren: newChildren)
    }

    @MainActor
    private static func applyPatch(id: Int, key: String, value: JSValue) {
        guard let ref = Renderer.nodeIndex[id], let mount = ref.node else { return }
        let layer = mount.layer

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        switch key {
        case "opacity":
            if value.isNumber {
                layer.opacity = Float(value.toDouble())
            }

        case "backgroundColor":
            if value.isString, let s = value.toString(),
               let c = RenderNode.parseColor(s) {
                layer.backgroundColor = c
            }

        case "borderColor":
            if value.isString, let s = value.toString(),
               let c = RenderNode.parseColor(s) {
                layer.borderColor = c
            }

        case "borderWidth":
            if value.isNumber {
                layer.borderWidth = CGFloat(value.toDouble())
            }

        case "borderRadius":
            if value.isNumber {
                layer.cornerRadius = CGFloat(value.toDouble())
                layer.masksToBounds = layer.cornerRadius > 0
            }

        case "text":
            if value.isString, let s = value.toString() {
                // Делегируем Renderer.patchText: обновляет lastTree + relayout.
                // RenderNode — struct, поэтому просто менять mount.node.text
                // недостаточно — следующий reconcile откатит layer на старый
                // текст из lastTree.
                ref.renderer?.patchText(id: id, text: s)
            }

        case "color":
            if value.isString, let s = value.toString(),
               let c = RenderNode.parseColor(s),
               let textLayer = layer as? CATextLayer,
               let txt = mount.node.text {
                var style = mount.node.style
                style.color = c
                textLayer.string = TextMeasure.attributedString(txt, style: style)
                mount.node.style.color = c
            }

        default:
            // Не критично — неподдерживаемое свойство просто игнорируем.
            // Можно добавить логирование, но это спамит на 120Hz scroll.
            break
        }
    }
}
