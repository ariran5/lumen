import os
import UIKit

/// Long-lived per-tab runtime: JSEngine + UIKit host hierarchy. Lives as long
/// as the owning TabModel exists, survives SwiftUI rebuilds across tab
/// switches (contrast with the old Coordinator which died together with the
/// SwiftUI representation).
///
/// Multi-app shell:
///   Tab A ↔ Tab B (switch) — both TabRuntimes live in their TabModels,
///   JS state / signals / module-scope storage stay in place for both.
///   When the user closes a tab — TabsStore.close drops the TabModel from the array,
///   ARC releases TabRuntime, engine and UIKit stack are freed.
///
/// Lifecycle:
///   init → setupEngine → loadIfNeeded (on onLayout) → eval bundle.script
///   performReload (on WS reload event) → recreate rootPage + engine,
///     but with the same tabID and url
///   dispose (deinit) → release engine, disconnect DevServerClient
@MainActor
final class TabRuntime {
    let tabID: UUID
    var url: URL

    /// Callbacks to TabModel — populate title and chrome-mode when the bundle
    /// has loaded. Weak to avoid the TabModel ↔ TabRuntime retain cycle.
    var onBundleName: ((String) -> Void)?
    var onChromeMode: ((ChromeMode) -> Void)?

    private(set) var engine: JSEngine?
    private(set) var nav: UINavigationController
    private(set) var rootPage: LumenPageViewController
    private var didLoad = false

    private var devClient: DevServerClient?
    private let jsLogger = os.Logger(subsystem: "com.lumen.js", category: "console")

    init(url: URL, tabID: UUID) {
        self.url = url
        self.tabID = tabID

        let page = LumenPageViewController(title: nil)
        let nav = UINavigationController(rootViewController: page)
        nav.navigationBar.prefersLargeTitles = false
        nav.view.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
        nav.setNavigationBarHidden(true, animated: false)
        nav.interactivePopGestureRecognizer?.delegate = nil
        page.loadViewIfNeeded()
        self.nav = nav
        self.rootPage = page

        setupEngine()

        page.onLayout = { [weak self] in
            self?.loadIfNeeded()
        }
    }

    // deinit is nonisolated, so we can't explicitly call `devClient?.disconnect()`
    // (main-actor method). URLSessionWebSocketTask cleans itself up at
    // DevServerClient dealloc — task release → URLSession drops it.
    // Race with the listen callback is safe: inside the callback `[weak self]`
    // → guard on nil → no-op.

    /// Create a new JSEngine and install all bridges. Called from init
    /// and from performReload (HMR). On reload the old engine is dropped,
    /// the renderer is recreated.
    func setupEngine() {
        guard let rootRenderer = rootPage.renderer else { return }
        let origin = Origin(url: url) ?? .system
        let engine = JSEngine(origin: origin)
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

        rootPage.onSafeAreaChange = { [weak engine] insets in
            engine?.updateSafeArea(insets)
        }
        engine.updateSafeArea(rootPage.view.safeAreaInsets)
    }

    func loadIfNeeded() {
        guard !didLoad,
              let engine,
              rootPage.view.bounds.width > 0 else { return }
        didLoad = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let bundle = try await BundleLoader.load(from: self.url)
                engine.applyManifest(bundle.manifest)
                self.onBundleName?(bundle.manifest.name)
                self.nav.topViewController?.title = bundle.manifest.name
                let mode = ChromeMode(rawValue: bundle.manifest.chrome ?? "compact") ?? .compact
                self.onChromeMode?(mode)
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
        // CALayer references in AnimationManager are bound to layers that
        // die after setViewControllers. Without reset, AnimatedValue ids
        // would collide with stale records (a new context starts at 1).
        AnimationManager.shared.reset()

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
