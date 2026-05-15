import SwiftUI
import UIKit

/// Bottom-sheet "home" page. On tap of the favicon-disc the shell
/// shows it over the current tab.
///
/// Structure:
///   • TabView with two pages:
///       0 = Home (embedded `lumen://home` fast-app — greeting, pinned, labs, recent)
///       1 = Tabs list (switch / close / long-press = edit url)
///     Sideways swipe OR tap on header segments switches between them.
///   • A search field pinned to the bottom via the native URLTextField:
///     pre-filled with the active tab's URL, auto-focused + selectAll,
///     submit → navigate the active tab.
struct StartSheet: View {
    @Bindable var tabs: TabsStore
    @Binding var isPresented: Bool

    /// 0 = Home, 1 = Tabs
    @State private var page: Int = 0

    /// If the user long-pressed a tab card — its id is remembered so that
    /// the search bar's submit navigates THAT one. nil = the search
    /// applies to the active tab.
    @State private var editTargetID: UUID?

    @State private var searchInput: String = ""
    @State private var searchFocused: Bool = false

    /// Snapshot of activeID + active tab URL at the moment the sheet opens.
    /// Used for auto-dismiss when:
    ///   - a new tab was opened via lumen.tabs.open in the home fast-app
    ///   - the current tab was navigated via lumen.tabs.navigate
    ///   - the user committed the search bar
    @State private var activeIDOnOpen: UUID?
    @State private var activeURLOnOpen: URL?

    var body: some View {
        VStack(spacing: 0) {
            pageSwitcher
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

            TabView(selection: $page) {
                homePage.tag(0)
                tabsPage.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            searchBar
        }
        .background(DarkPalette.bg0.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            // Prefill with the active tab's URL — Safari's open-bar does
            // the same. selectAll happens on becomeFirstResponder inside URLTextField.
            let active = tabs.activeTab
            searchInput = active?.currentURL?.absoluteString ?? ""
            editTargetID = nil
            activeIDOnOpen = tabs.activeID
            activeURLOnOpen = active?.currentURL
            // Auto-focus: on open the user wants to either look at home / tabs,
            // or type a new URL. Focus is the short path for the second;
            // the first still works (tap anywhere outside the field = resign).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                searchFocused = true
            }
        }
        .onChange(of: tabs.activeID) { _, _ in dismissIfNavigated() }
        .onChange(of: tabs.activeTab?.currentURL) { _, _ in dismissIfNavigated() }
    }

    // MARK: - Top page switcher

    private var pageSwitcher: some View {
        HStack(spacing: 0) {
            switcherButton(label: "Home", index: 0)
            switcherButton(label: "Tabs · \(tabs.tabs.count)", index: 1)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DarkPalette.surface)
        )
    }

    private func switcherButton(label: String, index: Int) -> some View {
        let active = page == index
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { page = index }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? DarkPalette.text : DarkPalette.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? DarkPalette.bg0 : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 0 — Home (embedded fast-app)

    private var homePage: some View {
        // FastAppHost for lumen://home. SheetHome.tab is a persistent
        // TabModel, so on repeated sheet opens the engine
        // is reused (fast appearance, scroll position preserved).
        FastAppHost(tab: SheetHome.tab, url: TabModel.homeURL)
    }

    // MARK: - Page 1 — Tabs list

    private var tabsPage: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(tabs.tabs) { tab in
                    tabRow(tab: tab)
                }
                newTabRow
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func tabRow(tab: TabModel) -> some View {
        let isActive = tabs.activeID == tab.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DarkPalette.text)
                    .lineLimit(1)
                Text(tab.currentURL?.absoluteString ?? "Start")
                    .font(.system(size: 11))
                    .foregroundStyle(DarkPalette.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button {
                tabs.close(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DarkPalette.textDim)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DarkPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor : .clear,
                                      lineWidth: 1.5)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            tabs.switchTo(id: tab.id)
            isPresented = false
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            editTargetID = tab.id
            searchInput = tab.currentURL?.absoluteString ?? ""
            searchFocused = true
        }
    }

    private var newTabRow: some View {
        Button {
            let new = tabs.open(url: nil)
            tabs.switchTo(id: new.id)
            editTargetID = nil
            searchInput = ""
            searchFocused = true
            page = 0  // return to home so the user sees where they're going
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("New tab")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(DarkPalette.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DarkPalette.textDim.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search bar (pinned to bottom)

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: searchFocused ? "magnifyingglass" : "globe")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DarkPalette.textDim)
            URLTextField(
                text: $searchInput,
                isFocused: $searchFocused,
                placeholder: "Search or paste URL…",
                onSubmit: commitSearch
            )
            .frame(height: 22)
            if !searchInput.isEmpty {
                Button {
                    searchInput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DarkPalette.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DarkPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(searchFocused
                                      ? Color.accentColor.opacity(0.55)
                                      : DarkPalette.textDim.opacity(0.15),
                                      lineWidth: searchFocused ? 1.2 : 0.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, 6)
        .background(
            // Slightly tint the background under the search bar — soft upward
            // gradient so scroll content doesn't slam into it with a hard edge.
            LinearGradient(colors: [
                DarkPalette.bg0.opacity(0),
                DarkPalette.bg0,
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Helpers

    /// Dismiss the sheet if the active tab switched OR went to a
    /// different URL after open — pinned click in home fast-app, search
    /// commit, etc. Ignore if nothing changed (the user just
    /// scrolled home).
    private func dismissIfNavigated() {
        let curID = tabs.activeID
        let curURL = tabs.activeTab?.currentURL
        if curID != activeIDOnOpen || curURL != activeURLOnOpen {
            isPresented = false
        }
    }

    private func commitSearch() {
        let target = editTargetID.flatMap { id in tabs.tabs.first { $0.id == id } } ?? tabs.activeTab
        guard let target else { return }
        target.addressInput = searchInput
        target.commit()
        tabs.switchTo(id: target.id)
        searchInput = ""
        editTargetID = nil
        isPresented = false
    }

}

/// Persistent TabModel for the embedded home in StartSheet. Separate from
/// user tabs so the home fast-app doesn't show up in their list
/// (it's the shell's internal UI). Lives for the whole process lifetime; JSEngine
/// initializes lazily on the first sheet show via FastAppHost.
@MainActor
enum SheetHome {
    static let tab: TabModel = {
        let t = TabModel()
        t.mode = .fastApp(TabModel.homeURL)
        return t
    }()
}
