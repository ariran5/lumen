import Foundation
import JavaScriptCore

extension JSEngine {
    func installBenchBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let bench = JSValue(newObjectIn: context)!

        let showFPS: @convention(block) (Bool) -> Void = { visible in
            MainActor.assumeIsolated {
                FPSOverlay.shared.setVisible(visible)
            }
        }

        let resetStats: @convention(block) () -> Void = {
            MainActor.assumeIsolated {
                FPSOverlay.shared.resetStats()
            }
        }

        let snapshot: @convention(block) () -> [String: Double] = {
            MainActor.assumeIsolated {
                let s = FPSOverlay.shared.snapshot()
                return [
                    "avg": s.avg,
                    "min": s.min,
                    "p5": s.p5,
                    "max": s.max,
                    "count": Double(s.count),
                ]
            }
        }

        bench.setObject(showFPS, forKeyedSubscript: "showFPS" as NSString)
        bench.setObject(resetStats, forKeyedSubscript: "resetStats" as NSString)
        bench.setObject(snapshot, forKeyedSubscript: "snapshot" as NSString)

        lumen.setObject(bench, forKeyedSubscript: "bench" as NSString)
    }
}
