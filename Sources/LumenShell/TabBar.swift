import SwiftUI

/// Минимальный горизонтальный tab-strip. Не финальный визуал — нужен чтобы
/// видно было multi-tab capability сейчас, пока shell-as-fast-app не готов.
/// Будущая красивая версия — на Lumen runtime.
struct TabBar: View {
    @Bindable var tabs: TabsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs.tabs) { tab in
                    TabChip(tab: tab,
                            isActive: tab.id == tabs.activeID,
                            onTap: { tabs.switchTo(id: tab.id) },
                            onClose: { tabs.close(id: tab.id) })
                }

                Button {
                    tabs.open()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                        .background(
                            Circle().fill(Color(uiColor: .secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(height: 36)
    }
}

private struct TabChip: View {
    @Bindable var tab: TabModel
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: leadingIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: 110, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive
                      ? Color(uiColor: .systemBackground)
                      : Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var leadingIcon: String {
        if tab.isLoading { return "ellipsis" }
        switch tab.mode {
        case .fastApp: return "bolt.fill"
        case .web: return "globe"
        case .start: return "house"
        }
    }
}
