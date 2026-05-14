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
        // Прозрачный backgroundColor у нашей VC.view'хи чтобы под content'ом
        // светилось sheet container's окружение: на iOS 26 это Liquid Glass
        // material (partial detent) или opaque системный фон (.large detent).
        // Default UIViewController'а — .systemBackground (dark в dark mode),
        // что перекрыло бы sheet'овский фон сплошным тёмным.
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
        // Рендерим ровно ОДИН раз на первом valid bounds. Никаких re-render'ов
        // при detent change'е — Renderer'овские explicit CALayer positions не
        // умеют плавно follow'ить sheet morph (получаются snap'ы или
        // mismatched timing). Content остаётся на своих позициях, sheet
        // визуально растёт вокруг него.
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
