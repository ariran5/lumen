import SwiftUI

public struct BrowserView: View {
    @State private var tabs = TabsStore.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let active = tabs.activeTab {
                AddressBar(tab: active)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .onAppear(perform: applyLaunchURLIfPresent)

                ProgressOverlay(visible: active.isLoading)
            }

            TabBar(tabs: tabs)
            Divider()

            // ZStack рендерит все табы одновременно; неактивные — opacity 0
            // и без hit-test'а. Это сохраняет WKWebView / FastAppHost state
            // (scroll position, JS heap) при переключении таб.
            ZStack {
                ForEach(tabs.tabs) { tab in
                    TabContent(tab: tab)
                        .opacity(tab.id == tabs.activeID ? 1 : 0)
                        .allowsHitTesting(tab.id == tabs.activeID)
                        .id(tab.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.15), value: tabs.activeID)
    }

    private func applyLaunchURLIfPresent() {
        guard let tab = tabs.activeTab,
              tab.mode == .start,
              let raw = UserDefaults.standard.string(forKey: "url") else { return }
        tab.addressInput = raw
        tab.commit()
    }
}

private struct TabContent: View {
    @Bindable var tab: TabModel

    var body: some View {
        switch tab.mode {
        case .start:
            StartPage(tab: tab)
                .transition(.opacity)
        case .web(let url):
            WebTabView(tab: tab)
                .id(url.host ?? "")
        case .fastApp(let url):
            FastAppHost(url: url, tabID: tab.id, onBundleName: { name in
                tab.pageTitle = name
            })
            .id(url.absoluteString)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct ProgressOverlay: View {
    let visible: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.tint)
                .frame(width: geo.size.width * 0.35, height: 2)
                .offset(x: geo.size.width * phase - geo.size.width * 0.35)
                .opacity(visible ? 1 : 0)
                .onChange(of: visible) { _, new in
                    if new {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            phase = 1.2
                        }
                    } else {
                        withAnimation(.linear(duration: 0.2)) { phase = 0 }
                    }
                }
        }
        .frame(height: 2)
    }
}

private struct StartPage: View {
    @Bindable var tab: TabModel

    private let exampleApps: [(label: String, url: String)] = [
        ("Tabs Lab — multi-tab API",   "http://192.168.0.108:8080"),
        ("HN reader — real-world demo", "http://192.168.0.108:8081"),
        ("Drag Lab — gestures + spring", "http://192.168.0.108:8082"),
        ("Glass Lab — iOS 26 Liquid Glass", "http://192.168.0.108:8083"),
        ("Scroll Lab — scroll + safe-area", "http://192.168.0.108:8084"),
        ("Input Lab — TextInput",       "http://192.168.0.108:8085"),
        ("Sheet Lab — bottomSheet",     "http://192.168.0.108:8086"),
        ("Hacker News (web fallback)",  "https://news.ycombinator.com"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                Text("Lumen")
                    .font(.largeTitle.weight(.bold))
                Text("Type a URL above to open a site. If it ships a Lumen manifest, it opens as a fast-app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(exampleApps, id: \.label) { item in
                        Button {
                            tab.addressInput = item.url
                            tab.commit()
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.tint)
                                Text(item.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(item.url)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: .secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
    }
}
