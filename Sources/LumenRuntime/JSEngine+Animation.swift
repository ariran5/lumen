import Foundation
import JavaScriptCore

extension JSEngine {
    /// JS-side AnimatedValue in CoreFramework talks to native via `lumen._animValue.*`.
    /// This is a private API — users use the `animated(initial)` builder.
    func installAnimationBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let animNS = JSValue(newObjectIn: context) else { return }

        let register: @convention(block) (Int, Double) -> Void = { id, initial in
            MainActor.assumeIsolated {
                AnimationManager.shared.register(id: id, initial: initial)
            }
        }
        animNS.setObject(register, forKeyedSubscript: "create" as NSString)

        let set: @convention(block) (Int, Double) -> Void = { id, value in
            MainActor.assumeIsolated {
                AnimationManager.shared.set(id: id, value: value)
            }
        }
        animNS.setObject(set, forKeyedSubscript: "set" as NSString)

        let animateTo: @convention(block) (Int, Double, Double, String) -> Void = { id, value, duration, easing in
            MainActor.assumeIsolated {
                AnimationManager.shared.animateTo(id: id, value: value, duration: duration, easing: easing)
            }
        }
        animNS.setObject(animateTo, forKeyedSubscript: "animateTo" as NSString)

        let stop: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated {
                AnimationManager.shared.stop(id: id)
            }
        }
        animNS.setObject(stop, forKeyedSubscript: "stop" as NSString)

        let current: @convention(block) (Int) -> Double = { id in
            MainActor.assumeIsolated {
                AnimationManager.shared.current(id: id)
            }
        }
        animNS.setObject(current, forKeyedSubscript: "current" as NSString)

        let release: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated {
                AnimationManager.shared.release(id: id)
            }
        }
        animNS.setObject(release, forKeyedSubscript: "release" as NSString)

        let reset: @convention(block) () -> Void = {
            MainActor.assumeIsolated {
                AnimationManager.shared.reset()
            }
        }
        animNS.setObject(reset, forKeyedSubscript: "resetAll" as NSString)

        lumen.setObject(animNS, forKeyedSubscript: "_animValue" as NSString)
    }
}
