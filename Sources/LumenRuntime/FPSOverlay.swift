import UIKit
import QuartzCore

@MainActor
final class RenderMetrics {
    static let shared = RenderMetrics()

    private(set) var samples: [Double] = []  // ms per cell render
    private(set) var totalCount: Int = 0     // монотонный счётчик — для renders/sec

    func record(_ ms: Double) {
        samples.append(ms)
        totalCount &+= 1
        if samples.count > 8192 {
            samples.removeFirst(samples.count - 8192)
        }
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        totalCount = 0
    }

    struct Stats {
        let avg: Double
        let p50: Double
        let p95: Double
        let p99: Double
        let max: Double
        let count: Int
    }

    func snapshot() -> Stats {
        let sorted = samples.sorted()
        guard let last = sorted.last else {
            return Stats(avg: 0, p50: 0, p95: 0, p99: 0, max: 0, count: 0)
        }
        let avg = sorted.reduce(0, +) / Double(sorted.count)
        let p50 = sorted[Int(Double(sorted.count) * 0.5)]
        let p95Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        let p99Index = min(sorted.count - 1, Int(Double(sorted.count) * 0.99))
        return Stats(avg: avg, p50: p50, p95: sorted[p95Index], p99: sorted[p99Index], max: last, count: sorted.count)
    }

    /// Дешёвая версия для HUD — без сортировки, чтобы тик overlay'а
    /// сам не стоил ничего во время скролла.
    struct Quick {
        let totalCount: Int
        let avgRecent: Double  // mean over last N samples
        let maxRecent: Double
    }

    func quickSnapshot(window: Int = 60) -> Quick {
        let n = samples.count
        guard n > 0 else { return Quick(totalCount: totalCount, avgRecent: 0, maxRecent: 0) }
        let start = max(0, n - window)
        var sum = 0.0
        var mx = 0.0
        for i in start..<n {
            sum += samples[i]
            if samples[i] > mx { mx = samples[i] }
        }
        return Quick(totalCount: totalCount,
                     avgRecent: sum / Double(n - start),
                     maxRecent: mx)
    }
}

@MainActor
final class FPSOverlay {

    static let shared = FPSOverlay()

    private var label: UILabel?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var samples: [Double] = []
    private var ema: Double = 0

    private var lastRenderCount: Int = 0
    private var renderRateEMA: Double = 0

    /// Show or hide the floating FPS HUD in the key window.
    func setVisible(_ visible: Bool) {
        if visible {
            install()
        } else {
            label?.removeFromSuperview()
            label = nil
            link?.invalidate()
            link = nil
        }
    }

    /// Reset counters but keep the overlay running.
    func resetStats() {
        samples.removeAll(keepingCapacity: true)
        ema = 0
    }

    /// Stop counter and return aggregated stats over the recorded samples.
    struct Stats {
        let avg: Double
        let min: Double
        let p5: Double
        let max: Double
        let count: Int
    }

    func snapshot() -> Stats {
        let sorted = samples.sorted()
        guard let first = sorted.first, let last = sorted.last else {
            return Stats(avg: 0, min: 0, p5: 0, max: 0, count: 0)
        }
        let avg = sorted.reduce(0, +) / Double(sorted.count)
        let p5Index = max(0, Int(Double(sorted.count) * 0.05))
        return Stats(avg: avg, min: first, p5: sorted[p5Index], max: last, count: sorted.count)
    }

    private func install() {
        guard label == nil else { return }
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard let window else { return }

        let lbl = UILabel()
        lbl.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = UIColor.white
        lbl.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        lbl.textAlignment = .center
        lbl.layer.cornerRadius = 6
        lbl.layer.masksToBounds = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = "fps –"
        window.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            lbl.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 6),
            lbl.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            lbl.heightAnchor.constraint(equalToConstant: 22),
        ])
        label = lbl

        let l = CADisplayLink(target: OverlayProxy(self), selector: #selector(OverlayProxy.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        lastTimestamp = 0
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
        samples.append(f)
        if samples.count > 4096 {
            samples.removeFirst(samples.count - 4096)
        }
        ema = ema == 0 ? f : (ema * 0.85 + f * 0.15)

        // Renders/sec: дельта totalCount поделённая на dt; даёт прямой ответ
        // «сколько раз mount-effect прокрутился за последнюю секунду».
        let r = RenderMetrics.shared.quickSnapshot()
        let countDelta = max(0, r.totalCount - lastRenderCount)
        lastRenderCount = r.totalCount
        let rate = Double(countDelta) / dt
        renderRateEMA = renderRateEMA == 0 ? rate : (renderRateEMA * 0.85 + rate * 0.15)

        if r.totalCount > 0 {
            label?.text = String(format: " %.0f fps · %.0f r/s · %.1fms (max %.0f) ",
                                 ema, renderRateEMA, r.avgRecent, r.maxRecent)
        } else {
            label?.text = String(format: " %.0f fps ", ema)
        }
    }
}

@MainActor
private final class OverlayProxy: NSObject {
    weak var target: FPSOverlay?
    init(_ target: FPSOverlay) { self.target = target }

    @objc func tick(_ link: CADisplayLink) {
        target?.tick(link)
    }
}
