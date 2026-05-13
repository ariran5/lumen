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
        // iOS 26: НЕ ставим backgroundColor — система сама накладывает
        // Liquid Glass на sheet container. Любой свой непрозрачный фон
        // даст артефакт-rim по краям (известная проблема).
        // Стиль (light/dark) наследуем от системы, чтобы Glass совпадал
        // с цветовой схемой приложения.
        if #available(iOS 26.0, *) {
            view.backgroundColor = .clear
        } else {
            view.backgroundColor = .systemBackground
        }

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
