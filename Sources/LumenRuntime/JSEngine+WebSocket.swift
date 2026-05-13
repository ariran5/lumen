import Foundation
@preconcurrency import JavaScriptCore

/// `lumen.ws(url, {onOpen, onMessage, onClose, onError})` → `{send, close}`.
///
/// Тонкая обёртка над `URLSessionWebSocketTask` с recursive `receive` loop'ом.
/// Не пытаемся следовать WHATWG `WebSocket` стандарту — для совместимости с
/// npm-либами (когда появится bundler) добавим shim в JS-runtime отдельно.
extension JSEngine {
    func installWebSocketBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        weak var weakSelf = self
        let connect: @convention(block) (String?, JSValue?) -> JSValue? = { urlString, callbacks in
            guard let engine = weakSelf,
                  let urlString,
                  let url = URL(string: urlString) else { return nil }
            return MainActor.assumeIsolated {
                let onOpen    = nonUndefined(callbacks?.objectForKeyedSubscript("onOpen"))
                let onMessage = nonUndefined(callbacks?.objectForKeyedSubscript("onMessage"))
                let onClose   = nonUndefined(callbacks?.objectForKeyedSubscript("onClose"))
                let onError   = nonUndefined(callbacks?.objectForKeyedSubscript("onError"))

                let bridge = WebSocketBridge(url: url,
                                             onOpen: onOpen,
                                             onMessage: onMessage,
                                             onClose: onClose,
                                             onError: onError)

                let handle = JSValue(newObjectIn: engine.context)!
                let sendBlock: @convention(block) (String?) -> Void = { text in
                    MainActor.assumeIsolated {
                        if let text { bridge.send(text) }
                    }
                }
                let closeBlock: @convention(block) () -> Void = {
                    MainActor.assumeIsolated {
                        bridge.close()
                    }
                }
                handle.setObject(sendBlock, forKeyedSubscript: "send" as NSString)
                handle.setObject(closeBlock, forKeyedSubscript: "close" as NSString)
                return handle
            }
        }
        lumen.setObject(connect, forKeyedSubscript: "ws" as NSString)
    }
}

private func nonUndefined(_ v: JSValue?) -> JSValue? {
    guard let v, !v.isUndefined, !v.isNull else { return nil }
    return v
}

@MainActor
private final class WebSocketBridge {
    static var alive: [ObjectIdentifier: WebSocketBridge] = [:]

    let task: URLSessionWebSocketTask
    let onOpen: JSValue?
    let onMessage: JSValue?
    let onClose: JSValue?
    let onError: JSValue?
    private var closed = false

    init(url: URL,
         onOpen: JSValue?,
         onMessage: JSValue?,
         onClose: JSValue?,
         onError: JSValue?) {
        self.onOpen = onOpen
        self.onMessage = onMessage
        self.onClose = onClose
        self.onError = onError
        self.task = URLSession.shared.webSocketTask(with: url)
        self.task.resume()
        WebSocketBridge.alive[ObjectIdentifier(self)] = self

        // onOpen фактически не привязан к WS-handshake (URLSessionWebSocketTask
        // не даёт onOpen-делегата), фаерим в next runloop tick — к этому моменту
        // task точно запущен. Если handshake провалится, receive loop поймает
        // ошибку и дёрнет onError.
        DispatchQueue.main.async { [weak self] in
            self?.startReceive()
            if let onOpen = self?.onOpen { _ = onOpen.call(withArguments: []) }
        }
    }

    private func startReceive() {
        guard !closed else { return }
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch result {
                    case .success(let msg):
                        let text: String? = {
                            switch msg {
                            case .string(let s): return s
                            case .data(let d): return String(data: d, encoding: .utf8)
                            @unknown default: return nil
                            }
                        }()
                        if let text, let cb = self.onMessage {
                            _ = cb.call(withArguments: [text])
                        }
                        self.startReceive()
                    case .failure(let err):
                        if let cb = self.onError {
                            _ = cb.call(withArguments: [err.localizedDescription])
                        }
                        self.cleanup()
                    }
                }
            }
        }
    }

    func send(_ text: String) {
        guard !closed else { return }
        task.send(.string(text)) { [weak self] err in
            guard let err else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let cb = self.onError {
                        _ = cb.call(withArguments: [err.localizedDescription])
                    }
                }
            }
        }
    }

    func close() {
        guard !closed else { return }
        task.cancel(with: .goingAway, reason: nil)
        cleanup()
    }

    private func cleanup() {
        guard !closed else { return }
        closed = true
        if let cb = onClose { _ = cb.call(withArguments: []) }
        WebSocketBridge.alive.removeValue(forKey: ObjectIdentifier(self))
    }
}
