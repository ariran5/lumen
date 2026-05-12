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
                if tab.currentURL == nil {
                    StartPage()
                        .transition(.opacity)
                } else {
                    WebTabView(tab: tab)
                        .id(tab.currentURL?.host ?? "")
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: tab.currentURL)
    }

    private func applyLaunchURLIfPresent() {
        guard tab.currentURL == nil,
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
    @State private var showPlayground: Bool = UserDefaults.standard.bool(forKey: "playground")
    @State private var showFastDemo: Bool = UserDefaults.standard.bool(forKey: "demo")
    @State private var showVirtualList: Bool = UserDefaults.standard.bool(forKey: "virtualList")
    @State private var showRemoteApp: Bool = UserDefaults.standard.bool(forKey: "remote")
    @State private var fastAppURL: String = UserDefaults.standard.string(forKey: "fastUrl") ?? "http://localhost:8080"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Lumen")
                .font(.largeTitle.weight(.bold))
            Text("Enter a URL above to begin")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
                    Label("Fast Tab Demo", systemImage: "square.grid.3x3.fill")
                        .font(.callout)
                }
                .buttonStyle(.bordered)

                Button {
                    showVirtualList = true
                } label: {
                    Label("Virtual List 10k (M8 spike)", systemImage: "list.bullet.below.rectangle")
                        .font(.callout)
                }
                .buttonStyle(.bordered)

                Divider().padding(.vertical, 4)

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("http://localhost:8080", text: $fastAppURL)
                            .textFieldStyle(.plain)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.caption, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        showRemoteApp = true
                    } label: {
                        Label("Load fast-app from URL", systemImage: "arrow.down.circle.fill")
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(URL(string: fastAppURL) == nil)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showPlayground) {
            JSPlaygroundView()
        }
        .sheet(isPresented: $showFastDemo) {
            DemoFastTabView()
        }
        .sheet(isPresented: $showVirtualList) {
            VirtualListDemoView()
        }
        .sheet(isPresented: $showRemoteApp) {
            if let url = URL(string: fastAppURL) {
                RemoteFastAppView(url: url)
            }
        }
    }
}
