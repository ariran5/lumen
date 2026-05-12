import SwiftUI

public struct BrowserView: View {
    @State private var tab = TabModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            AddressBar(tab: tab)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .onAppear(perform: applyLaunchURLIfPresent)

            ProgressOverlay(visible: tab.isLoading)

            Divider()

            ZStack {
                switch tab.mode {
                case .start:
                    StartPage(tab: tab)
                        .transition(.opacity)
                case .web(let url):
                    WebTabView(tab: tab)
                        .id(url.host ?? "")
                case .fastApp(let url):
                    FastAppHost(url: url, onBundleName: { name in
                        tab.pageTitle = name
                    })
                    .id(url.absoluteString)
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.15), value: tab.mode)
    }

    private func applyLaunchURLIfPresent() {
        guard tab.mode == .start,
              let raw = UserDefaults.standard.string(forKey: "url") else { return }
        tab.addressInput = raw
        tab.commit()
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

    @State private var showPlayground: Bool = UserDefaults.standard.bool(forKey: "playground")
    @State private var showFastDemo: Bool = UserDefaults.standard.bool(forKey: "demo")
    @State private var showVirtualList: Bool = UserDefaults.standard.bool(forKey: "virtualList")

    private let exampleApps: [(label: String, url: String)] = [
        ("Hacker News", "http://localhost:8080"),
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

                if !exampleApps.isEmpty {
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

                VStack(spacing: 8) {
                    Button {
                        showPlayground = true
                    } label: {
                        Label("JavaScript Playground", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showFastDemo = true
                    } label: {
                        Label("Fast Tab Demo (inline JS)", systemImage: "square.grid.3x3.fill")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showVirtualList = true
                    } label: {
                        Label("Virtual List 10k", systemImage: "list.bullet.below.rectangle")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showPlayground) {
            JSPlaygroundView()
        }
        .sheet(isPresented: $showFastDemo) {
            DemoFastTabView()
        }
        .sheet(isPresented: $showVirtualList) {
            VirtualListDemoView()
        }
    }
}
