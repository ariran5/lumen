import JavaScriptCore
import QuartzCore
import UIKit

@MainActor
final class VirtualListController {
    var count: Int
    var itemHeight: CGFloat
    var renderFn: JSValue

    weak var view: VirtualListView?

    private(set) var lastJSMs: Double = 0
    private(set) var lastParseMs: Double = 0
    private(set) var lastRenderMs: Double = 0

    init(count: Int, itemHeight: CGFloat, renderFn: JSValue) {
        self.count = count
        self.itemHeight = itemHeight
        self.renderFn = renderFn
    }

    /// Re-render visible cells. cellForItemAt will call JS `render(i)`
    /// again; renderer inside the cell will apply the delta via reconciler
    /// without recreating CALayers.
    func reload() {
        view?.collectionView.reloadData()
    }

    /// Apply new values from the tree. If `count` or `itemHeight`
    /// changed — invalidate layout and reload.
    func update(count: Int, itemHeight: CGFloat, renderFn: JSValue) {
        let countChanged = self.count != count
        let heightChanged = self.itemHeight != itemHeight
        self.count = count
        self.itemHeight = itemHeight
        self.renderFn = renderFn
        if heightChanged {
            view?.applyItemHeight(itemHeight)
        }
        if countChanged || heightChanged {
            view?.collectionView.reloadData()
        } else {
            // same length — just re-render (render function may return different content)
            view?.collectionView.reloadData()
        }
    }

    func render(at index: Int) -> RenderNode? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let result = renderFn.call(withArguments: [index]) else { return nil }
        let t1 = CFAbsoluteTimeGetCurrent()
        let node = RenderNode.parse(result)
        let t2 = CFAbsoluteTimeGetCurrent()
        lastJSMs = (t1 - t0) * 1000
        lastParseMs = (t2 - t1) * 1000
        return node
    }
}

@MainActor
final class LumenCell: UICollectionViewCell {
    static let reuseID = "LumenCell"

    private var renderer: Renderer?
    private var lastLayoutBounds: CGRect = .zero

    func render(tree: RenderNode) {
        if renderer == nil {
            contentView.layer.masksToBounds = true
            renderer = Renderer(hostView: contentView)
        }
        renderer?.render(tree)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds != lastLayoutBounds, bounds.width > 0, bounds.height > 0 {
            lastLayoutBounds = bounds
            renderer?.relayout()
        }
    }

    // prepareForReuse isn't needed: on next render the renderer itself will
    // diff against the previous cell tree and apply the delta without flash.
}

final class VirtualListView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    let collectionView: UICollectionView
    let controller: VirtualListController

    var fpsCounter: FPSCounter?
    var didFinishAutoScroll: ((FPSCounter) -> Void)?

    private var scrollLink: CADisplayLink?
    private var scrollStartTime: CFTimeInterval = 0
    private var scrollDuration: TimeInterval = 0
    private var scrollTargetY: CGFloat = 0

    init(controller: VirtualListController, frame: CGRect) {
        self.controller = controller
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: max(1, frame.width), height: controller.itemHeight)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)

        controller.view = self

        collectionView.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(LumenCell.self, forCellWithReuseIdentifier: LumenCell.reuseID)
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.frame = bounds
        addSubview(collectionView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = bounds
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let newSize = CGSize(width: bounds.width, height: controller.itemHeight)
            if layout.itemSize != newSize {
                layout.itemSize = newSize
                layout.invalidateLayout()
            }
        }
    }

    func applyItemHeight(_ height: CGFloat) {
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.itemSize = CGSize(width: max(1, bounds.width), height: height)
            layout.invalidateLayout()
        }
    }

    func startAutoScroll(duration: TimeInterval, targetItems: Int = 200) {
        guard let counter = fpsCounter else { return }
        guard collectionView.contentSize.height > collectionView.bounds.height else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startAutoScroll(duration: duration, targetItems: targetItems)
            }
            return
        }
        counter.start()

        scrollTargetY = min(
            CGFloat(targetItems) * controller.itemHeight,
            collectionView.contentSize.height - collectionView.bounds.height
        )
        scrollStartTime = CACurrentMediaTime() + 0.25
        scrollDuration = duration

        let link = CADisplayLink(target: ScrollProxy(self),
                                  selector: #selector(ScrollProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        scrollLink = link
    }

    fileprivate func scrollTick(_ link: CADisplayLink) {
        let elapsed = link.timestamp - scrollStartTime
        if elapsed < 0 { return }

        if elapsed >= scrollDuration {
            collectionView.contentOffset = CGPoint(x: 0, y: scrollTargetY)
            scrollLink?.invalidate()
            scrollLink = nil
            fpsCounter?.stop()
            if let c = fpsCounter {
                didFinishAutoScroll?(c)
            }
            return
        }

        let progress = elapsed / scrollDuration
        collectionView.contentOffset = CGPoint(x: 0, y: scrollTargetY * CGFloat(progress))
    }

    nonisolated func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    nonisolated func collectionView(_ collectionView: UICollectionView,
                                    numberOfItemsInSection section: Int) -> Int {
        MainActor.assumeIsolated { controller.count }
    }

    nonisolated func collectionView(_ collectionView: UICollectionView,
                                    cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        MainActor.assumeIsolated {
            let t0 = CFAbsoluteTimeGetCurrent()
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: LumenCell.reuseID, for: indexPath
            ) as! LumenCell
            if let tree = controller.render(at: indexPath.item) {
                cell.render(tree: tree)
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            RenderMetrics.shared.record(elapsed)
            return cell
        }
    }
}

@MainActor
final class FPSCounter {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    private(set) var current: Double = 0
    private(set) var minFPS: Double = .infinity
    private(set) var maxFPS: Double = 0
    private(set) var avgFPS: Double = 0
    private(set) var samples: Int = 0
    private(set) var p5FPS: Double = 0
    private var allSamples: [Double] = []

    var onTick: ((Double) -> Void)?

    func start() {
        reset()
        let l = CADisplayLink(target: WeakProxy(self), selector: #selector(WeakProxy.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        if !allSamples.isEmpty {
            let sorted = allSamples.sorted()
            let idx = max(0, Int(Double(sorted.count) * 0.05))
            p5FPS = sorted[idx]
        }
    }

    private func reset() {
        lastTimestamp = 0
        current = 0
        minFPS = .infinity
        maxFPS = 0
        avgFPS = 0
        samples = 0
        allSamples.removeAll(keepingCapacity: true)
    }

    fileprivate func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        guard dt > 0 else { return }
        let f = 1.0 / dt
        current = f
        minFPS = Swift.min(minFPS, f)
        maxFPS = Swift.max(maxFPS, f)
        samples += 1
        avgFPS = avgFPS + (f - avgFPS) / Double(samples)
        allSamples.append(f)
        onTick?(f)
    }
}

@MainActor
private final class WeakProxy: NSObject {
    weak var target: FPSCounter?
    init(_ target: FPSCounter) { self.target = target }

    @objc func tick(_ link: CADisplayLink) {
        target?.tick(link)
    }
}

@MainActor
private final class ScrollProxy: NSObject {
    weak var target: VirtualListView?
    init(_ target: VirtualListView) { self.target = target }

    @objc func tick(_ link: CADisplayLink) {
        target?.scrollTick(link)
    }
}
