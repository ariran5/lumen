import JavaScriptCore
import UIKit

/// Lumen-обёртка над UIScrollView. Внутри живёт `contentView`, чей layer —
/// rootLayer для nested Renderer. Renderer в режиме `.scrollContent` считает
/// layout с infinite height, после чего мы читаем `computedContentHeight()`
/// и выставляем `contentView.bounds.height` + `contentSize`.
///
/// Паттерн оверлея тот же что у VirtualList / TextInput — UIScrollView сидит
/// как subview родительского hostView с абсолютным frame'ом из flex.
@MainActor
final class LumenScrollView: UIScrollView, UIScrollViewDelegate {

    let contentView: UIView
    let renderer: Renderer
    var onScrollHandler: JSValue?

    private var lastRenderedChildren: [RenderNode] = []
    private var lastWrapperStyle: ViewStyle = ViewStyle()
    private var lastViewportWidth: CGFloat = 0

    override init(frame: CGRect) {
        self.contentView = UIView(frame: CGRect(origin: .zero, size: frame.size))
        self.contentView.backgroundColor = .clear
        self.renderer = Renderer(hostView: contentView)
        self.renderer.contentMode = .scrollContent
        super.init(frame: frame)
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .never
        showsVerticalScrollIndicator = true
        showsHorizontalScrollIndicator = false
        delegate = self
        addSubview(contentView)
        // Slot-thunk внутри scroll-контента может изменить число детей —
        // renderer.replaceChildren запустит relayout() и дёрнет onAfterLayout,
        // тут пересчитаем contentSize.
        self.renderer.onAfterLayout = { [weak self] in
            self?.resyncContentSize()
        }
    }

    private func resyncContentSize() {
        guard bounds.width > 0 else { return }
        let height = max(0, renderer.computedContentHeight())
        let newSize = CGSize(width: bounds.width, height: max(height, bounds.height))
        if contentView.frame.size != newSize {
            contentView.frame = CGRect(origin: .zero, size: newSize)
        }
        if contentSize != newSize {
            contentSize = newSize
        }
    }

    // Fires часто (per-frame во время scroll). Если JS handler тяжёлый,
    // компонент сам должен throttle'ить. Bridge call ~0.05ms на пустой
    // handler, поэтому 120Hz scroll даёт ≤6ms/sec суммарно — приемлемо.
    nonisolated func scrollViewDidScroll(_ scrollView: UIScrollView) {
        MainActor.assumeIsolated {
            guard let cb = onScrollHandler else { return }
            let event: [String: Any] = [
                "offset": Double(scrollView.contentOffset.y),
                "viewportHeight": Double(scrollView.bounds.height),
                "contentHeight": Double(scrollView.contentSize.height),
            ]
            _ = cb.call(withArguments: [event])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    /// Принимает детей scroll-узла + стиль самого scroll-узла (нужен для
    /// padding/gap, которые пробрасываются на синтетический wrapper).
    /// Wrap'ает их в один column-узел, дёргает nested renderer, ресайзит
    /// contentView под получившуюся высоту.
    func renderContent(children: [RenderNode], wrapperStyle: ViewStyle) {
        lastRenderedChildren = children
        lastWrapperStyle = wrapperStyle
        applyRender()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastViewportWidth {
            lastViewportWidth = bounds.width
            // Reset content frame to current viewport width — renderer
            // прочитает rootLayer.bounds.width при следующем relayout.
            contentView.frame = CGRect(origin: .zero,
                                        size: CGSize(width: bounds.width,
                                                     height: contentView.bounds.height))
            applyRender()
        }
    }

    private func applyRender() {
        guard bounds.width > 0 else { return }

        // Wrapper — column-контейнер с padding/gap из scroll-узла. justify=start
        // (дефолт) обеспечивает наклейку детей сверху без растяжения.
        var wrapper = RenderNode()
        wrapper.kind = .view
        wrapper.style = lastWrapperStyle
        wrapper.style.flex.direction = .column
        wrapper.style.flex.height = .auto
        wrapper.style.flex.width = .auto
        wrapper.children = lastRenderedChildren

        renderer.render(wrapper)

        let height = max(0, renderer.computedContentHeight())
        let newSize = CGSize(width: bounds.width, height: max(height, bounds.height))
        if contentView.frame.size != newSize {
            contentView.frame = CGRect(origin: .zero, size: newSize)
        }
        if contentSize != newSize {
            contentSize = newSize
        }
    }
}
