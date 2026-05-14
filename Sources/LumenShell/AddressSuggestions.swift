import SwiftUI

/// Saggestion-панель над AddressBar в фокусе. Источник — HistoryStore,
/// фильтрация по подстроке в title/url. Tap → commit URL и closes focus.
/// Пустой query → топ-5 свежих визитов.
struct AddressSuggestions: View {
    let query: String
    let onSelect: (String) -> Void

    @State private var history = HistoryStore.shared
    private let maxItems = 6

    private var matches: [HistoryEntry] {
        let entries = history.entries
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return Array(entries.prefix(maxItems))
        }
        return entries.filter { e in
            e.url.lowercased().contains(q) ||
            e.title.lowercased().contains(q)
        }.prefix(maxItems).map { $0 }
    }

    var body: some View {
        let items = matches
        if !items.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, entry in
                    SuggestionRow(entry: entry, onTap: { onSelect(entry.url) })
                    if idx < items.count - 1 {
                        Divider().background(DarkPalette.border)
                            .padding(.leading, 44)
                    }
                }
            }
            .background(suggestionsBackground)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var suggestionsBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(DarkPalette.borderHi, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.30), radius: 22, x: 0, y: 14)
    }
}

private struct SuggestionRow: View {
    let entry: HistoryEntry
    let onTap: () -> Void

    private var host: String {
        URL(string: entry.url)?.hostForDisplay ?? entry.url
    }

    private var displayTitle: String {
        entry.title.isEmpty ? host : entry.title
    }

    private var initial: String {
        String(host.prefix(1)).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // mini-avatar с первой буквой хоста
                Text(initial)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DarkPalette.text)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DarkPalette.surface)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(DarkPalette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(DarkPalette.textDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DarkPalette.textSoft)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
