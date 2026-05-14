import Foundation
import JavaScriptCore

/// `lumen.tabs.*` API для fast-app'ов. Доступен через TabsStore.shared
/// (browser-wide singleton). Каждый engine знает свой `ownTabID` — он
/// используется как дефолт в `.close()` (закрыть собственную табу).
///
/// Bridge возвращает JSON-строки для сложных объектов: Swift 6 strict
/// concurrency не пропускает `[String: Any]` / JSValue как Sendable
/// return type. CoreFramework оборачивает в lumen.tabs.* парся JSON.
extension JSEngine {
    func installTabsBridge(ownTabID: UUID) {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let tabsNS = JSValue(newObjectIn: context) else { return }

        let ownIDString = ownTabID.uuidString

        let listJSON: @convention(block) () -> String = {
            MainActor.assumeIsolated {
                let array = TabsStore.shared.tabs.map { tab in
                    Self.tabDict(tab, isActive: tab.id == TabsStore.shared.activeID)
                }
                return Self.toJSON(array)
            }
        }
        tabsNS.setObject(listJSON, forKeyedSubscript: "_listJSON" as NSString)

        let currentJSON: @convention(block) () -> String = {
            MainActor.assumeIsolated {
                guard let active = TabsStore.shared.activeTab else { return "null" }
                return Self.toJSON(Self.tabDict(active, isActive: true))
            }
        }
        tabsNS.setObject(currentJSON, forKeyedSubscript: "_currentJSON" as NSString)

        let ownJSON: @convention(block) () -> String = {
            MainActor.assumeIsolated {
                guard let tab = TabsStore.shared.tabs.first(where: { $0.id.uuidString == ownIDString }) else {
                    return "null"
                }
                return Self.toJSON(Self.tabDict(tab, isActive: tab.id == TabsStore.shared.activeID))
            }
        }
        tabsNS.setObject(ownJSON, forKeyedSubscript: "_ownJSON" as NSString)

        let open: @convention(block) (String?) -> String = { url in
            MainActor.assumeIsolated {
                let tab = TabsStore.shared.open(url: url)
                return tab.id.uuidString
            }
        }
        tabsNS.setObject(open, forKeyedSubscript: "open" as NSString)

        // navigate(url) — навигация СВОЕЙ табы (не открывает новую).
        // Используется встроенным lumen://home для пинов / recent клика.
        // Fallback на activeTab нужен для embedded'ового sheet home —
        // там JSEngine принадлежит SheetHome.tab, который НЕ в
        // TabsStore.shared.tabs (это отдельный шелл-only TabModel),
        // и user'овский клик по пину должен навигировать ту таб'у
        // под sheet'ом, на которую юзер смотрит.
        let navigate: @convention(block) (String) -> Void = { url in
            MainActor.assumeIsolated {
                let target = TabsStore.shared.tabs.first(where: { $0.id.uuidString == ownIDString })
                          ?? TabsStore.shared.activeTab
                guard let target else { return }
                target.addressInput = url
                target.commit()
            }
        }
        tabsNS.setObject(navigate, forKeyedSubscript: "navigate" as NSString)

        let close: @convention(block) (String?) -> Void = { id in
            let target = (id?.isEmpty == false) ? id! : ownIDString
            MainActor.assumeIsolated {
                if let uuid = UUID(uuidString: target) {
                    TabsStore.shared.close(id: uuid)
                }
            }
        }
        tabsNS.setObject(close, forKeyedSubscript: "close" as NSString)

        let switchTo: @convention(block) (String) -> Void = { id in
            MainActor.assumeIsolated {
                if let uuid = UUID(uuidString: id) {
                    TabsStore.shared.switchTo(id: uuid)
                }
            }
        }
        tabsNS.setObject(switchTo, forKeyedSubscript: "switch" as NSString)

        lumen.setObject(tabsNS, forKeyedSubscript: "_tabsRaw" as NSString)
    }

    @MainActor
    private static func tabDict(_ tab: TabModel, isActive: Bool) -> [String: Any] {
        [
            "id": tab.id.uuidString,
            "url": tab.currentURL?.absoluteString as Any? ?? NSNull(),
            "title": tab.displayTitle,
            "isLoading": tab.isLoading,
            "isActive": isActive,
        ]
    }

    private static func toJSON(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object) else { return "null" }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }
}
