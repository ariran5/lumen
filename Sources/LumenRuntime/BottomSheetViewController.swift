import UIKit

@MainActor
final class BottomSheetViewController: UIViewController {
    private let content: RenderNode
    private var renderer: Renderer?
    private var contentView: UIView?
    private var didFireDismiss = false

    var onDismiss: (() -> Void)?

    init(content: RenderNode) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)

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
