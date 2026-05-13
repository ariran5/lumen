import Foundation
import JavaScriptCore

/// `lumen.history.*` API. Доступ к browser-wide HistoryStore из fast-app'ов
/// (в первую очередь — builtin lumen://history).
///
/// Возвращает JSON-строки по тем же причинам что и Tabs bridge: Swift 6
/// strict concurrency не пропускает `[String: Any]` как Sendable return type.
extension JSEngine {
    func installHistoryBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let historyNS = JSValue(newObjectIn: context) else { return }

        let listJSON: @convention(block) () -> String = {
            MainActor.assumeIsolated {
                let entries = HistoryStore.shared.entries.map { e -> [String: Any] in
                    [
                        "id": e.id,
                        "url": e.url,
                        "title": e.title,
                        "at": Int(e.at * 1000),
                    ]
                }
                guard JSONSerialization.isValidJSONObject(entries),
                      let data = try? JSONSerialization.data(withJSONObject: entries),
                      let s = String(data: data, encoding: .utf8) else {
                    return "[]"
                }
                return s
            }
        }
        historyNS.setObject(listJSON, forKeyedSubscript: "_listJSON" as NSString)

        let remove: @convention(block) (String?) -> Void = { id in
            guard let id, !id.isEmpty else { return }
            MainActor.assumeIsolated { HistoryStore.shared.remove(id: id) }
        }
        historyNS.setObject(remove, forKeyedSubscript: "_remove" as NSString)

        let clear: @convention(block) () -> Void = {
            MainActor.assumeIsolated { HistoryStore.shared.clear() }
        }
        historyNS.setObject(clear, forKeyedSubscript: "_clear" as NSString)

        lumen.setObject(historyNS, forKeyedSubscript: "_historyRaw" as NSString)
    }
}
