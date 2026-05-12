import SwiftUI
import UIKit

struct FastAppHost: UIViewControllerRepresentable {
    let url: URL
    var onBundleName: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onBundleName: onBundleName)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let rootPage = LumenPageViewController(title: nil)
        let nav = UINavigationController(rootViewController: rootPage)
        nav.navigationBar.prefersLargeTitles = false
        nav.view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)

        rootPage.loadViewIfNeeded()
        guard let rootRenderer = rootPage.renderer else { return nav }

        let engine = JSEngine()
        engine.installRenderBridge(renderer: rootRenderer)

        engine.installVirtualListBridge { [weak nav] controller in
            guard let topVC = nav?.topViewController, let host = topVC.view else { return }

            if let page = topVC as? LumenPageViewController {
                page.renderer?.detach()
            }
            host.subviews.forEach { $0.removeFromSuperview() }

            let list = VirtualListView(controller: controller, frame: host.bounds)
            list.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(list)
            NSLayoutConstraint.activate([
                list.topAnchor.constraint(equalTo: host.topAnchor),
                list.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                list.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ])
        }

        engine.installRouterBridge(navController: nav)
        engine.installPlatformBridges()

        context.coordinator.engine = engine
        context.coordinator.nav = nav
        context.coordinator.rootPage = rootPage

        rootPage.onLayout = { [weak coord = context.coordinator] in
            coord?.loadIfNeeded()
        }

        Self.styleNavBar(nav)

        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.loadIfNeeded()
    }

    private static func styleNavBar(_ nav: UINavigationController) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.shadowColor = .clear
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
        nav.navigationBar.tintColor = .white
    }

    @MainActor
    final class Coordinator {
        let url: URL
        let onBundleName: ((String) -> Void)?
        var engine: JSEngine?
        var nav: UINavigationController?
        var rootPage: LumenPageViewController?
        var didLoad = false

        init(url: URL, onBundleName: ((String) -> Void)?) {
            self.url = url
            self.onBundleName = onBundleName
        }

        func loadIfNeeded() {
            guard !didLoad,
                  let engine,
                  rootPage?.view.bounds.width ?? 0 > 0 else { return }
            didLoad = true
            Task { [weak self] in
                guard let self else { return }
                do {
                    let bundle = try await BundleLoader.load(from: self.url)
                    self.onBundleName?(bundle.manifest.name)
                    self.nav?.topViewController?.title = bundle.manifest.name
                    _ = engine.eval(bundle.script)
                } catch {
                    engine.eval("console.error('Bundle load failed: \(error.localizedDescription)')")
                }
            }
        }
    }
}
