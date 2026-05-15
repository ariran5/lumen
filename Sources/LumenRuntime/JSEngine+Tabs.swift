import Foundation
import JavaScriptCore

/// `lumen.tabs.*` API for fast-apps. Available via TabsStore.shared
/// (browser-wide singleton). Each engine knows its `ownTabID` — used
/// as default for `.close()` (close own tab).
///
/// Bridge returns JSON strings for complex objects: Swift 6 strict
/// concurrency rejects `[String: Any]` / JSValue as a Sendable
/// return type. CoreFramework wraps lumen.tabs.* by parsing JSON.
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

        // navigate(url) — navigate OWN tab (doesn't open a new one).
        // Used by built-in lumen://home for pin / recent taps.
        // Fallback to activeTab is needed for the embedded sheet home —
        // there the JSEngine belongs to SheetHome.tab, which is NOT in
        // TabsStore.shared.tabs (it's a separate shell-only TabModel),
        // and a user pin tap should navigate the tab
        // under the sheet that the user is looking at.
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
