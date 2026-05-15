import Foundation
import JavaScriptCore

/// JS-side wrapper around native push channel. See `NativeNotifier.swift`.
///
///     const id = lumen._notify._subscribe('history', fn)
///     lumen._notify._unsubscribe('history', id)
///
/// CoreFramework wraps this into convenient `lumen.history.subscribe(fn)`
/// → returning an unsub closure.
extension JSEngine {
    func installNotifyBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let notifyNS = JSValue(newObjectIn: context) else { return }

        let subscribe: @convention(block) (String, JSValue) -> Int = { [weak self] channel, fn in
            guard let self,
                  fn.isObject,
                  let mv = JSManagedValue(value: fn) else { return -1 }
            self.context.virtualMachine.addManagedReference(mv, withOwner: self)
            let id = self.nextNotifyID()
            self.notifyListeners[channel, default: []].append((id, mv))
            return id
        }
        notifyNS.setObject(subscribe, forKeyedSubscript: "_subscribe" as NSString)

        let unsubscribe: @convention(block) (String, Int) -> Void = { [weak self] channel, id in
            guard let self,
                  var arr = self.notifyListeners[channel],
                  let idx = arr.firstIndex(where: { $0.0 == id }) else { return }
            let mv = arr[idx].1
            self.context.virtualMachine.removeManagedReference(mv, withOwner: self)
            arr.remove(at: idx)
            self.notifyListeners[channel] = arr
        }
        notifyNS.setObject(unsubscribe, forKeyedSubscript: "_unsubscribe" as NSString)

        lumen.setObject(notifyNS, forKeyedSubscript: "_notify" as NSString)
    }
}
