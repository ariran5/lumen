import os
import SwiftUI
import UIKit

struct FastAppHost: UIViewControllerRepresentable {
    let url: URL
    let tabID: UUID
    var onBundleName: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, tabID: tabID, onBundleName: onBundleName)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let rootPage = LumenPageViewController(title: nil)
        let nav = UINavigationController(rootViewController: rootPage)
        nav.navigationBar.prefersLargeTitles = false
        nav.view.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
        // Скрываем nav bar — chrome теперь живёт в shell'е, fast-app не
        // должен рисовать свою верхнюю плашку. Edge-swipe-to-pop при этом
        // продолжает работать.
        nav.setNavigationBarHidden(true, animated: false)

        rootPage.loadViewIfNeeded()

        context.coordinator.nav = nav
        context.coordinator.rootPage = rootPage
        context.coordinator.setupEngine()

        rootPage.onLayout = { [weak coord = context.coordinator] in
            coord?.loadIfNeeded()
        }

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
        let tabID: UUID
        let onBundleName: ((String) -> Void)?
        var engine: JSEngine?
        var nav: UINavigationController?
        var rootPage: LumenPageViewController?
        var didLoad = false

        private var devClient: DevServerClient?
        private let jsLogger = os.Logger(subsystem: "com.lumen.js", category: "console")

        init(url: URL, tabID: UUID, onBundleName: ((String) -> Void)?) {
            self.url = url
            self.tabID = tabID
            self.onBundleName = onBundleName
        }

        /// Создать новый JSEngine, поставить все bridges, eval framework.
        /// Вызывается изначально и при hot-reload.
        func setupEngine() {
            guard let rootPage, let nav, let rootRenderer = rootPage.renderer else { return }
            let engine = JSEngine()
            engine.onLog = { [weak self] level, msg in
                print("[js \(level.rawValue)] \(msg)")
                self?.jsLogger.info("\(level.rawValue, privacy: .public): \(msg, privacy: .public)")
            }
            engine.installRenderBridge(renderer: rootRenderer)
            engine.installRouterBridge(navController: nav)
            engine.installPlatformBridges()
            engine.installTabsBridge(ownTabID: tabID)
            engine.eval(CoreFramework.script)
            self.engine = engine

            // Push initial safe-area + подписаться на изменения
            rootPage.onSafeAreaChange = { [weak engine] insets in
                engine?.updateSafeArea(insets)
            }
            engine.updateSafeArea(rootPage.view.safeAreaInsets)
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
                    if bundle.manifest.dev == true {
                        self.connectDevServer()
                    }
                } catch {
                    engine.eval("console.error('Bundle load failed: \(error.localizedDescription)')")
                }
            }
        }

        private func connectDevServer() {
            guard devClient == nil, let client = DevServerClient(baseURL: url) else { return }
            client.onReload = { [weak self] in
                print("[lumen] hot reload triggered")
                self?.performReload()
            }
            client.connect()
            self.devClient = client
        }

        private func performReload() {
            guard let nav else { return }

            // Animation state привязан к старым CALayer'ам, которые умрут после
            // setViewControllers. Без reset id'ы AnimatedValue пересекутся со
            // stale-записями (new context стартует ids с 1).
            AnimationManager.shared.reset()

            // Hot reload через полное пересоздание page + engine:
            // старый rootPage / Renderer / VirtualListView освобождаются
            // ARC'ом, и в дереве UIView не остаётся dangling-ссылок (была
            // crash на _updateSafeAreaInsets после partial cleanup).
            let newRoot = LumenPageViewController(title: nav.topViewController?.title)
            newRoot.loadViewIfNeeded()
            nav.setViewControllers([newRoot], animated: false)
            self.rootPage = newRoot
            newRoot.onLayout = { [weak self] in
                self?.loadIfNeeded()
            }

            setupEngine()
            didLoad = false
            loadIfNeeded()
        }
    }
}
