import UIKit

/// Lumen wrapper over UIVisualEffectView. Children render into
/// `effectView.contentView` via a nested Renderer (same pattern as
/// ScrollView, but in `.stretch` mode — blur doesn't scroll).
///
/// Used via `kind: 'blur'`:
///   Blur({intensity: 'regular', padding: 12, borderRadius: 16},
///     Text('Sticky pill'),
///   )
@MainActor
final class LumenBlurView: UIView {
    private let effectView: UIVisualEffectView
    let renderer: Renderer

    private var lastRenderedChildren: [RenderNode] = []
    private var lastWrapperStyle: ViewStyle = ViewStyle()
    private var lastIntensity: String = ""

    init(frame: CGRect, intensity: String) {
        let effect = LumenBlurView.effect(for: intensity)
        self.effectView = UIVisualEffectView(effect: effect)
        self.effectView.frame = CGRect(origin: .zero, size: frame.size)
        self.renderer = Renderer(hostView: effectView.contentView)
        super.init(frame: frame)
        self.lastIntensity = intensity
        addSubview(effectView)
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func update(intensity: String, children: [RenderNode], wrapperStyle: ViewStyle) {
        if intensity != lastIntensity {
            effectView.effect = LumenBlurView.effect(for: intensity)
            lastIntensity = intensity
        }
        lastRenderedChildren = children
        lastWrapperStyle = wrapperStyle
        applyRender()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if effectView.frame.size != bounds.size {
            effectView.frame = bounds
            applyRender()
        }
    }

    private func applyRender() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        var wrapper = RenderNode()
        wrapper.kind = .view
        wrapper.style = lastWrapperStyle
        wrapper.children = lastRenderedChildren
        renderer.render(wrapper)
    }

    static func effect(for intensity: String) -> UIVisualEffect {
        // iOS 26+ Liquid Glass.
        if #available(iOS 26.0, *) {
            switch intensity {
            case "glass", "glassRegular":
                let g = UIGlassEffect()
                return g
            case "glassClear":
                let g = UIGlassEffect(style: .clear)
                return g
            default:
                break
            }
        }
        // Legacy system materials (iOS 17+, fallback for glass on older OS).
        let style: UIBlurEffect.Style
        switch intensity {
        case "ultraThin":            style = .systemUltraThinMaterial
        case "thin":                 style = .systemThinMaterial
        case "thick":                style = .systemThickMaterial
        case "chrome":               style = .systemChromeMaterial
        case "glass", "glassRegular": style = .systemMaterial   // fallback iOS < 26
        case "glassClear":           style = .systemThinMaterial // fallback
        case "regular":              fallthrough
        default:                     style = .systemMaterial
        }
        return UIBlurEffect(style: style)
    }
}
