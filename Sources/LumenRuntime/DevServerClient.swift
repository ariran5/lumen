import Foundation

/// Minimal WebSocket client for the dev-server hot-reload channel.
/// Connects to `ws://<host>:<port>/__hmr`, listens to messages,
/// calls `onReload` on main thread when `{"type":"reload"}` arrives.
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
                    // Disconnect/error — retry reconnect after 2s.
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
