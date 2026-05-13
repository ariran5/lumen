import Foundation
@preconcurrency import JavaScriptCore
import UserNotifications

/// `lumen.notifications.*` — local notifications через UNUserNotificationCenter.
///
/// API:
/// ```ts
/// const status = await lumen.notifications.requestPermission()  // 'granted' | 'denied'
/// const id = await lumen.notifications.schedule({title, body, at})  // at = unix ms
/// lumen.notifications.cancel(id)
/// lumen.notifications.cancelAll()
/// const unsub = lumen.notifications.onTap.subscribe((id) => {...})
/// ```
///
/// Push (APNS) НЕ входит — это Tier 2.5 (нужны entitlements + сертификат).
/// Здесь только local: schedule + trigger по времени.
///
/// `onTap` ловит и тапы, и launch-from-notification (когда app killed) — iOS
/// удерживает response и доставит его как только мы выставим delegate, что
/// происходит при init JSEngine.
extension JSEngine {
    func installNotificationsBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let notifications = JSValue(newObjectIn: context)!

        MainActor.assumeIsolated {
            LumenNotificationDelegate.install()
        }

        let nativeRequest: @convention(block) (JSValue, JSValue) -> Void = { resolve, _ in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        _ = resolve.call(withArguments: [granted ? "granted" : "denied"])
                    }
                }
            }
        }
        notifications.setObject(nativeRequest, forKeyedSubscript: "_nativeRequestPermission" as NSString)

        let nativeSchedule: @convention(block) (JSValue?, JSValue, JSValue) -> Void = { payload, resolve, reject in
            guard let payload, !payload.isUndefined, !payload.isNull else {
                _ = reject.call(withArguments: ["payload required"])
                return
            }
            let title = payload.objectForKeyedSubscript("title")?.toString() ?? ""
            let body  = payload.objectForKeyedSubscript("body")?.toString() ?? ""

            // `at` — unix ms. Если нет — fire через 1 секунду (минимум для
            // UNTimeIntervalNotificationTrigger).
            let now = Date().timeIntervalSince1970 * 1000
            let atValue = payload.objectForKeyedSubscript("at")
            let atMs: Double
            if let atValue, !atValue.isUndefined, !atValue.isNull,
               atValue.isNumber, let num = atValue.toNumber() {
                atMs = num.doubleValue
            } else {
                atMs = now + 1000
            }
            let delaySec = max(1, (atMs - now) / 1000.0)

            let providedID = payload.objectForKeyedSubscript("id")?.toString()
            let id = (providedID?.isEmpty == false) ? providedID! : UUID().uuidString

            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delaySec, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { err in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let err {
                            _ = reject.call(withArguments: [err.localizedDescription])
                        } else {
                            _ = resolve.call(withArguments: [id])
                        }
                    }
                }
            }
        }
        notifications.setObject(nativeSchedule, forKeyedSubscript: "_nativeSchedule" as NSString)

        let cancel: @convention(block) (String?) -> Void = { id in
            guard let id, !id.isEmpty else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }
        notifications.setObject(cancel, forKeyedSubscript: "cancel" as NSString)

        let cancelAll: @convention(block) () -> Void = {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
        notifications.setObject(cancelAll, forKeyedSubscript: "cancelAll" as NSString)

        let consumeTaps: @convention(block) () -> [String] = {
            MainActor.assumeIsolated {
                LumenNotificationDelegate.shared.consumeTaps()
            }
        }
        notifications.setObject(consumeTaps, forKeyedSubscript: "_consumeTaps" as NSString)

        lumen.setObject(notifications, forKeyedSubscript: "notifications" as NSString)
    }
}

/// Singleton-delegate `UNUserNotificationCenter`. Делегат у центра один на
/// процесс — поэтому здесь shared, а не per-engine.
///
/// `pendingTaps` — id'шники нотификаций, на которые юзер тапнул, но JS ещё не
/// успел вычитать. Drain'ится через `lumen.notifications._consumeTaps()` из
/// JS-обёртки `onTap.subscribe`.
final class LumenNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = LumenNotificationDelegate()

    @MainActor private var pendingTaps: [String] = []

    @MainActor
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    @MainActor
    func consumeTaps() -> [String] {
        let r = pendingTaps
        pendingTaps = []
        return r
    }

    /// App в foreground'е — по умолчанию iOS гасит notification banner. Здесь
    /// возвращаем `.banner` чтобы он показался даже когда фастапп открыт —
    /// нагляднее для PlatformLab demo.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.pendingTaps.append(id)
                NativeNotifier.shared.fire("notifications.tap")
            }
        }
        // Apple требует "as soon as possible" — фаерим сразу, наша работа на
        // main выполнится отдельно.
        completionHandler()
    }
}
