import Foundation

struct HistoryEntry: Codable, Sendable {
    let id: String
    let url: String
    var title: String
    let at: TimeInterval   // unix seconds
}

/// Browser-wide история визитов. Persists в Documents/history.json.
/// Trim до `maxEntries` старых записей чтобы файл не рос бесконечно.
@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var entries: [HistoryEntry] = []
    private let fileURL: URL
    private let maxEntries = 500

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func record(url: URL, title: String) {
        // Внутренние lumen:// страницы в историю не пишем.
        if url.scheme == "lumen" { return }

        let entry = HistoryEntry(
            id: UUID().uuidString,
            url: url.absoluteString,
            title: title,
            at: Date().timeIntervalSince1970
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        persist()
    }

    func updateTitle(forURL url: String, title: String) {
        guard !title.isEmpty,
              let idx = entries.firstIndex(where: { $0.url == url && $0.title.isEmpty }) else {
            return
        }
        entries[idx].title = title
        persist()
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    /// Persist + push в JS-подписчиков. Любая мутация публичных методов
    /// проходит через эту точку — единая seam для notify.
    private func persist() {
        save()
        NativeNotifier.shared.fire("history")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
