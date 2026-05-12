import SwiftUI
import UIKit

struct RemoteFastAppView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var status: Status = .loading
    @State private var bundleName: String = "Loading…"

    enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
                    .ignoresSafeArea()

                switch status {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Loading \(url.absoluteString)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                case .ready:
                    RemoteFastAppHost(url: url, onBundleName: { bundleName = $0 })
                        .ignoresSafeArea(edges: .bottom)
                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text("Load failed")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
            .navigationTitle(bundleName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(uiColor: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)),
                                for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task {
            do {
                _ = try await BundleLoader.load(from: url)
                status = .ready
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

private struct RemoteFastAppHost: UIViewRepresentable {
    let url: URL
    let onBundleName: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onBundleName: onBundleName) }

    func makeUIView(context: Context) -> UIView {
        let container = RemoteContainerView()
        container.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        container.coordinator = context.coordinator

        let renderer = Renderer(rootLayer: container.layer)
        let engine = JSEngine()
        engine.installRenderBridge(renderer: renderer)
        engine.installVirtualListBridge { [weak container] controller in
            guard let container else { return }
            container.subviews.forEach { $0.removeFromSuperview() }
            let list = VirtualListView(controller: controller, frame: container.bounds)
            list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(list)
        }
        engine.installPlatformBridges()

        context.coordinator.engine = engine
        context.coordinator.renderer = renderer
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    @MainActor
    final class Coordinator {
        let url: URL
        let onBundleName: (String) -> Void
        var engine: JSEngine?
        var renderer: Renderer?
        var didLoad = false

        init(url: URL, onBundleName: @escaping (String) -> Void) {
            self.url = url
            self.onBundleName = onBundleName
        }

        func onLayout() {
            guard !didLoad, let engine, renderer != nil else { return }
            didLoad = true
            Task { [weak self] in
                guard let self else { return }
                do {
                    let bundle = try await BundleLoader.load(from: self.url)
                    self.onBundleName(bundle.manifest.name)
                    _ = engine.eval(bundle.script)
                } catch {
                    engine.eval("console.error('Bundle load failed: \(error.localizedDescription)')")
                }
            }
        }
    }
}

private final class RemoteContainerView: UIView {
    weak var coordinator: RemoteFastAppHost.Coordinator?
    private var lastBounds: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != lastBounds {
            lastBounds = bounds.size
            coordinator?.onLayout()
        }
    }
}
