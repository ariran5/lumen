import Foundation

/// Минимальный WebSocket клиент для hot-reload канала dev-server'а.
/// Подключается к `ws://<host>:<port>/__hmr`, слушает сообщения,
/// дёргает `onReload` на main thread когда приходит `{"type":"reload"}`.
@MainActor
final class DevServerClient {
    var onReload: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private let url: URL
    private var stopped = false

    init?(baseURL: URL) {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let host = components.host else { return nil }
        // ws://host:port/__hmr (https → wss, http → ws)
        components.scheme = (baseURL.scheme?.lowercased() == "https") ? "wss" : "ws"
        components.path = "/__hmr"
        components.host = host
        guard let wsURL = components.url else { return nil }
        self.url = wsURL
    }

    func connect() {
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        listen()
    }

    func disconnect() {
        stopped = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.stopped else { return }

                switch result {
                case .success(.string(let text)):
                    if text.contains("\"reload\"") {
                        self.onReload?()
                    }
                    self.listen()
                case .success(.data(let data)):
                    if let text = String(data: data, encoding: .utf8),
                       text.contains("\"reload\"") {
                        self.onReload?()
                    }
                    self.listen()
                case .success:
                    self.listen()
                case .failure:
                    // Disconnect/error — пробуем переподключиться через 2с.
                    self.task = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self, !self.stopped else { return }
                        self.connect()
                    }
                }
            }
        }
    }
}
