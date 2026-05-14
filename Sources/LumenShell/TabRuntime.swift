import os
import UIKit

/// Long-lived per-tab runtime: JSEngine + UIKit host hierarchy. Живёт пока
/// существует TabModel-владелец, выживает SwiftUI rebuild'ы при tab
/// switch'е (контраст с прежним Coordinator'ом, который умирал вместе с
/// SwiftUI представлением).
///
/// Multi-app shell:
///   Tab A ↔ Tab B (switch) — обе TabRuntime живут в своих TabModel'ах,
///   JS state / signals / module-scope storage остаются на месте у обоих.
///   Когда юзер закроет tab — TabsStore.close выкидывает TabModel из массива,
///   ARC дёргает TabRuntime, engine и UIKit-стек освобождаются.
///
/// Lifecycle:
///   init → setupEngine → loadIfNeeded (по onLayout) → eval bundle.script
///   performReload (по WS reload event'у) → пересоздать rootPage + engine,
///     но с тем же tabID и url
///   dispose (deinit) → release engine, отключить DevServerClient
@MainActor
final class TabRuntime {
    let tabID: UUID
    var url: URL

    /// Callback'и в TabModel — заполняют title и chrome-mode когда bundle
    /// загрузился. Слабые чтобы избежать retain-cycle TabModel ↔ TabRuntime.
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

    // deinit nonisolated, поэтому явно `devClient?.disconnect()` (main-actor
    // method) вызвать нельзя. URLSessionWebSocketTask чистится сам при
    // dealloc'е DevServerClient'а — task release → URLSession удалит его.
    // Race с listen-callback'ом безопасен: внутри callback'а `[weak self]`
    // → guard на nil → no-op.

    /// Создать новый JSEngine, поставить все bridges. Вызывается из init
    /// и из performReload (HMR). При reload'е старый engine выкидывается,
    /// renderer пересоздаётся.
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
        // CALayer-ссылки в AnimationManager привязаны к layer'ам которые
        // умрут после setViewControllers. Без reset'а id'ы AnimatedValue
        // пересекутся со stale-записями (новый context стартует с 1).
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
