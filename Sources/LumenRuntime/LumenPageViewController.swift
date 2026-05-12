import UIKit
@preconcurrency import JavaScriptCore

@MainActor
final class LumenPageViewController: UIViewController {

    private(set) var renderer: Renderer?
    var onLayout: (() -> Void)?

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
        host.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        view = host
        renderer = Renderer(hostView: host)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }

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

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil, !didFirePop {
            didFirePop = true
            onPopValue?.call(withArguments: [])
        }
    }
}
