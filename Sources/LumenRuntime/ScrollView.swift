import JavaScriptCore
import UIKit

/// Lumen wrapper over UIScrollView. Inside lives `contentView`, whose layer is
/// the rootLayer for a nested Renderer. Renderer in `.scrollContent` mode computes
/// layout with infinite height, then we read `computedContentHeight()`
/// and set `contentView.bounds.height` + `contentSize`.
///
/// Same overlay pattern as VirtualList / TextInput — UIScrollView sits
/// as a subview of the parent hostView with an absolute frame from flex.
@MainActor
final class LumenScrollView: UIScrollView, UIScrollViewDelegate {

    let contentView: UIView
    let renderer: Renderer
    var onScrollHandler: JSValue?
    var onRefreshHandler: JSValue?
    private var refreshTarget: RefreshTarget?

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
        // A slot-thunk inside scroll content may change the number of children —
        // renderer.replaceChildren will run relayout() and fire onAfterLayout,
        // we recompute contentSize here.
        self.renderer.onAfterLayout = { [weak self] in
            self?.resyncContentSize()
        }
    }

    /// Enables UIRefreshControl when `onRefresh` appears, disables when
    /// `onRefresh == nil`. Spinner control is via the Promise returned from
    /// JS: after resolve/reject native calls `endRefreshing()`.
    /// Sync handler without a Promise — spinner ends immediately after return.
    func configureRefresh(onRefresh: JSValue?) {
        onRefreshHandler = onRefresh

        if onRefresh == nil {
            if let rc = refreshControl {
                rc.removeTarget(refreshTarget, action: nil, for: .valueChanged)
                rc.endRefreshing()
                refreshControl = nil
                refreshTarget = nil
            }
            return
        }

        if refreshControl == nil {
            let rc = UIRefreshControl()
            let target = RefreshTarget { [weak self] in
                self?.fireRefresh()
            }
            rc.addTarget(target, action: #selector(RefreshTarget.fire), for: .valueChanged)
            refreshTarget = target
            refreshControl = rc
        }
    }

    private func fireRefresh() {
        guard let handler = onRefreshHandler else { return }
        let result = handler.call(withArguments: [])

        // If JS returned a thenable — wait for resolve/reject. Otherwise — sync, end immediately.
        if let result, result.isObject,
           let thenProp = result.objectForKeyedSubscript("then"),
           thenProp.isObject,
           let context = result.context {
            let endBlock: @convention(block) (JSValue?) -> Void = { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshControl?.endRefreshing()
                }
            }
            // .then(end, end) — end spinner on both resolve and reject.
            if let endValue = JSValue(object: endBlock, in: context) {
                result.invokeMethod("then", withArguments: [endValue, endValue])
                return
            }
        }
        // Sync path: let UIKit draw the spinner before we close it.
        DispatchQueue.main.async { [weak self] in
            self?.refreshControl?.endRefreshing()
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

    // Fires frequently (per-frame during scroll). If the JS handler is heavy,
    // the component must throttle itself. Bridge call is ~0.05ms on an empty
    // handler, so 120Hz scroll gives ≤6ms/sec total — acceptable.
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

    /// Accepts the children of the scroll node + the style of the scroll node itself (needed for
    /// padding/gap, which are forwarded onto a synthetic wrapper).
    /// Wraps them in one column node, drives the nested renderer, resizes
    /// contentView to the resulting height.
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
            // will read rootLayer.bounds.width on next relayout.
            contentView.frame = CGRect(origin: .zero,
                                        size: CGSize(width: bounds.width,
                                                     height: contentView.bounds.height))
            applyRender()
        }
    }

    private func applyRender() {
        guard bounds.width > 0 else { return }

        // Wrapper — column container with padding/gap from the scroll node. justify=start
        // (default) sticks children to the top without stretching.
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

/// UIRefreshControl expects an `@objc` target. JSValue can't be one, so
/// we wrap it in an NSObject wrapper that holds a Swift closure.
@MainActor
private final class RefreshTarget: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }
    @objc func fire() { action() }
}
