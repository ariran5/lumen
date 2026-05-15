import UIKit

@MainActor
final class BottomSheetViewController: UIViewController {
    private let content: RenderNode
    private var renderer: Renderer?
    private var contentView: UIView?
    private var didFireDismiss = false
    private var lastRenderedSize: CGSize = .zero

    var onDismiss: (() -> Void)?

    init(content: RenderNode) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Transparent backgroundColor on our VC.view so the sheet container's
        // surroundings show through under content: on iOS 26 it's Liquid Glass
        // material (partial detent) or opaque system background (.large detent).
        // Default UIViewController's is .systemBackground (dark in dark mode),
        // which would override the sheet background with solid dark.
        view.backgroundColor = .clear

        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.backgroundColor = .clear
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentView = host
        renderer = Renderer(hostView: host)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // Render exactly ONCE on the first valid bounds. No re-renders
        // on detent change — Renderer's explicit CALayer positions can't
        // smoothly follow the sheet morph (you get snaps or
        // mismatched timing). Content stays in place, sheet
        // visually grows around it.
        if lastRenderedSize != .zero { return }
        lastRenderedSize = size
        renderer?.render(content)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !didFireDismiss, isBeingDismissed || isMovingFromParent {
            didFireDismiss = true
            onDismiss?()
        }
    }
}
