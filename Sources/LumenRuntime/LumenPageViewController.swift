import UIKit
@preconcurrency import JavaScriptCore

@MainActor
final class LumenPageViewController: UIViewController {

    private(set) var renderer: Renderer?
    private(set) var contentView: UIView?
    var onLayout: (() -> Void)?
    var onSafeAreaChange: ((UIEdgeInsets) -> Void)?

    private let renderFn: JSValue?
    private let onPopValue: JSValue?
    private var didFirstRender = false
    private var didFirePop = false

    init(title: String?, renderFn: JSValue? = nil, onPop: JSValue? = nil) {
        self.renderFn = renderFn
        self.onPopValue = onPop
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func loadView() {
        let host = UIView()
        host.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
        view = host

        // contentView фуллскрин — от top до bottom. Fast-app сам уважает
        // `lumen.safeArea.top/bottom` в своей разметке (greeting/header).
        // Без этого мы режем верхнюю часть и host-bg торчит над контентом.
        let content = UIView()
        content.backgroundColor = .clear
        content.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        self.contentView = content
        renderer = Renderer(hostView: content)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let contentView,
              contentView.bounds.width > 0,
              contentView.bounds.height > 0 else { return }

        if !didFirstRender {
            didFirstRender = true
            if let renderFn,
               let result = renderFn.call(withArguments: []),
               !result.isUndefined,
               let tree = RenderNode.parse(result) {
                renderer?.render(tree)
            }
        } else {
            renderer?.relayout()
        }

        onLayout?()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        onSafeAreaChange?(view.safeAreaInsets)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil, !didFirePop {
            didFirePop = true
            onPopValue?.call(withArguments: [])
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        StatusBarConfig.current.style
    }

    override var prefersStatusBarHidden: Bool {
        StatusBarConfig.current.hidden
    }
}
