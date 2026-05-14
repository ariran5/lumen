import SwiftUI

/// Bottom-anchored Liquid Glass address bar.
/// Два визуальных режима:
///   full    — full pill: [🏠] [icon · TextField] [✦]
///   compact — disc 44×44 с одной leading-иконкой (lock/sparkle/host-letter).
///             Tap на disc → isFocused=true → разворачивается + клавиатура,
///             URL pre-selected (через нативный UITextField).
///
/// Используется как:
///   - home / web → full mode
///   - fast-app (сторонний) → compact, чтобы не закрывать контент, но
///     сохранить отступление обратно (через home button или ввод URL'а).
struct AddressBar: View {
    @Bindable var tab: TabModel
    @Binding var isFocused: Bool
    var onOpenLibrary: () -> Void = {}
    /// Compact-pill tap callback: вместо разворачивания строки в полную
    /// шелл открывает StartSheet с табами + поиском внизу.
    var onTapCompactPill: () -> Void = {}
    var isCompact: Bool = false

    private var renderCompact: Bool { isCompact && !isFocused }

    private var isHome: Bool { tab.currentURL == TabModel.homeURL }
    private var hasURL: Bool { tab.currentURL != nil && !isHome }

    private var hostText: String {
        if isHome { return "Search or ask anything…" }
        guard let url = tab.currentURL else { return "Search or ask anything…" }
        return url.hostForDisplay
    }

    private var leadingGlyph: String? {
        if tab.isLoading { return "ellipsis" }
        if isHome { return nil }
        switch tab.currentURL?.scheme {
        case "https": return "lock.fill"
        case "lumen": return "sparkles"
        default:      return "globe"
        }
    }

    private var iconStyle: AnyShapeStyle {
        if isFocused { return AnyShapeStyle(DarkPalette.textDim) }
        switch leadingGlyph {
        case "lock.fill": return AnyShapeStyle(DarkPalette.ok)
        case "sparkles":  return AnyShapeStyle(DarkPalette.accent)
        default:          return AnyShapeStyle(DarkPalette.textDim)
        }
    }

    var body: some View {
        Group {
            if renderCompact {
                compactPill
            } else {
                fullBar
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: renderCompact)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isFocused)
    }

    // MARK: - compact mode

    private var compactPill: some View {
        Button {
            // Tap по compact-pill теперь открывает StartSheet (overlay с
            // tabs + search), а не разворачивает в полный bar. Старый
            // full-mode остаётся для домашней страницы / web-режима.
            onTapCompactPill()
        } label: {
            ZStack {
                Image(systemName: leadingGlyph ?? "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconStyle)
            }
            .frame(width: 46, height: 46)
            .background(glassBackground(cornerRadius: 23))
        }
        .buttonStyle(.plain)
    }

    // MARK: - full mode

    private var fullBar: some View {
        HStack(spacing: 8) {
            roundButton(icon: "house") {
                isFocused = false
                tab.goHome()
            }
            urlField
            aiButton
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(glassBackground(cornerRadius: 24))
    }

    private var urlField: some View {
        HStack(spacing: 8) {
            Image(systemName: isFocused ? "magnifyingglass" : (leadingGlyph ?? "magnifyingglass"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(iconStyle)

            ZStack(alignment: .leading) {
                Text(hostText)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(hasURL ? DarkPalette.text : DarkPalette.textDim)
                    .frame(maxWidth: .infinity,
                           alignment: hasURL && !isFocused ? .center : .leading)
                    .opacity(isFocused ? 0 : 1)
                    .allowsHitTesting(false)

                // Native UITextField — selectAll работает (SwiftUI TextField не умеет).
                URLTextField(
                    text: $tab.addressInput,
                    isFocused: $isFocused,
                    placeholder: "Search or ask anything…",
                    onSubmit: {
                        tab.commit()
                        isFocused = false
                    }
                )
                .frame(height: 22)
                .opacity(isFocused ? 1 : 0)
            }

            if isFocused, !tab.addressInput.isEmpty {
                Button {
                    tab.addressInput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DarkPalette.textDim)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DarkPalette.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isFocused {
                if hasURL { tab.addressInput = tab.currentURL?.absoluteString ?? "" }
                isFocused = true
            }
        }
    }

    // MARK: - buttons

    @ViewBuilder
    private func roundButton(icon: String,
                             enabled: Bool = true,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(enabled ? DarkPalette.text : DarkPalette.textSoft)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var aiButton: some View {
        Button(action: onOpenLibrary) {
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x0B0B0F))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [DarkPalette.accent, DarkPalette.accent2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .shadow(color: DarkPalette.accent.opacity(0.4), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func glassBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DarkPalette.borderHi, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 18)
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
    }
}
