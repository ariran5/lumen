import SwiftUI
import UIKit

private let virtualListScript = #"""
function color(i) {
  const r = (i * 37 + 73)  % 200 + 40;
  const g = (i * 91 + 19)  % 200 + 40;
  const b = (i * 173 + 53) % 200 + 40;
  return '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');
}

function row(i) {
  return {
    type: 'view',
    style: {
      flexDirection: 'row',
      padding: 12,
      gap: 12,
      backgroundColor: i % 2 === 0 ? '#15151a' : '#1c1c22',
      height: 80
    },
    children: [
      {
        type: 'view',
        style: { width: 56, height: 56, borderRadius: 28, backgroundColor: color(i) }
      },
      {
        type: 'view',
        style: { flex: 1, gap: 4, height: 56 },
        children: [
          {
            type: 'text',
            text: 'Item #' + i,
            style: { fontSize: 16, fontWeight: '600', color: '#ffffff', height: 22 }
          },
          {
            type: 'text',
            text: 'Virtual list cell #' + i + ' rendered from JavaScript via CALayer',
            style: { fontSize: 12, color: '#9CA3AF', numberOfLines: 2, lineHeight: 16, height: 32 }
          }
        ]
      }
    ]
  };
}

lumen.virtualList({
  count: 10000,
  itemHeight: 80,
  render: row
});

console.log('virtualList mounted: 10000 items');
"""#

struct VirtualListDemoView: View {
    @State private var fpsLive: Double = 0
    @State private var summary: FPSSummary?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VirtualListHost(script: virtualListScript,
                                onFPSTick: { fpsLive = $0 },
                                onFinish: { summary = $0 })
                    .ignoresSafeArea(edges: .bottom)

                overlay
            }
            .navigationTitle("Virtual List Spike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = summary {
                Text("Finished — avg \(Int(s.avg)) · p5 \(Int(s.p5)) · min \(Int(s.minimum)) · max \(Int(s.maximum)) · n=\(s.samples)")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("FPS: \(Int(fpsLive))")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct FPSSummary {
    var avg: Double
    var p5: Double
    var minimum: Double
    var maximum: Double
    var samples: Int
}

private struct VirtualListHost: UIViewRepresentable {
    let script: String
    let onFPSTick: (Double) -> Void
    let onFinish: (FPSSummary) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(script: script, onFPSTick: onFPSTick, onFinish: onFinish)
    }

    func makeUIView(context: Context) -> UIView {
        let container = HostContainer()
        container.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        container.coordinator = context.coordinator

        let engine = JSEngine()
        engine.installVirtualListBridge { [weak container] controller in
            guard let container else { return }
            container.subviews.forEach { $0.removeFromSuperview() }
            let list = VirtualListView(controller: controller, frame: container.bounds)
            list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            list.fpsCounter = FPSCounter()
            container.list = list
            container.addSubview(list)
            context.coordinator.list = list
            context.coordinator.startAutoScrollIfReady()
        }
        context.coordinator.engine = engine

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    @MainActor
    final class Coordinator {
        var engine: JSEngine?
        var list: VirtualListView?
        var script: String
        var onFPSTick: (Double) -> Void
        var onFinish: (FPSSummary) -> Void
        var didRunScript = false
        var pendingAutoScroll = UserDefaults.standard.bool(forKey: "autoscroll")

        init(script: String, onFPSTick: @escaping (Double) -> Void,
             onFinish: @escaping (FPSSummary) -> Void) {
            self.script = script
            self.onFPSTick = onFPSTick
            self.onFinish = onFinish
        }

        func onLayout() {
            guard let engine, !didRunScript else { return }
            didRunScript = true
            _ = engine.eval(script)
        }

        func startAutoScrollIfReady() {
            guard pendingAutoScroll, let list else { return }
            pendingAutoScroll = false
            let counter = FPSCounter()
            counter.onTick = { [weak self] f in
                self?.onFPSTick(f)
            }
            list.fpsCounter = counter
            list.didFinishAutoScroll = { [weak self] c in
                guard let self else { return }
                self.onFinish(FPSSummary(avg: c.avgFPS,
                                          p5: c.p5FPS,
                                          minimum: c.minFPS,
                                          maximum: c.maxFPS,
                                          samples: c.samples))
            }
            counter.start()
            list.fpsCounter = counter
            list.startAutoScroll(duration: 8.0)
        }
    }
}

private final class HostContainer: UIView {
    weak var coordinator: VirtualListHost.Coordinator?
    weak var list: VirtualListView?
    private var lastBounds: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != lastBounds {
            lastBounds = bounds.size
            coordinator?.onLayout()
        }
    }
}
