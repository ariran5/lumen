import SwiftUI

private let demoScript = #"""
function color(i, total) {
  const t = i / total;
  const r = Math.round(127 + 127 * Math.sin(t * 6.28));
  const g = Math.round(127 + 127 * Math.sin(t * 6.28 + 2.09));
  const b = Math.round(127 + 127 * Math.sin(t * 6.28 + 4.19));
  return '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');
}

function tile(i, total) {
  return {
    type: 'view',
    style: { width: 32, height: 32, backgroundColor: color(i, total), borderRadius: 8 }
  };
}

const COLS = 10, ROWS = 10, total = COLS * ROWS;
const rows = [];
for (let r = 0; r < ROWS; r++) {
  const cells = [];
  for (let c = 0; c < COLS; c++) cells.push(tile(r * COLS + c, total));
  rows.push({
    type: 'view',
    style: { flexDirection: 'row', gap: 4, height: 32 },
    children: cells
  });
}

const title = {
  type: 'text',
  text: 'Lumen Fast Tab',
  style: {
    fontSize: 28,
    fontWeight: '700',
    color: '#FFFFFF',
    height: 36,
  }
};

const subtitle = {
  type: 'text',
  text: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate.',
  style: {
    fontSize: 13,
    color: '#9CA3AF',
    numberOfLines: 3,
    lineHeight: 18,
    height: 56,
  }
};

const caption = {
  type: 'text',
  text: '100 CALayer tiles · zero web stack',
  style: {
    fontSize: 11,
    fontWeight: '500',
    color: '#6EE7B7',
    textAlign: 'center',
    height: 16,
  }
};

const tree = {
  type: 'view',
  style: { padding: 20, gap: 14, backgroundColor: '#0F0F12', flex: 1 },
  children: [
    title,
    subtitle,
    ...rows,
    caption
  ]
};

console.log('rendering', total, 'tiles +', 3, 'text nodes');
lumen.render(tree);
console.log('done');
"""#

struct DemoFastTabView: View {
    @State private var layerCount: Int = 0
    @State private var renderMs: Double = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FastTabView(script: demoScript) { count, ms in
                    layerCount = count
                    renderMs = ms
                }

                metricsBar
            }
            .navigationTitle("Fast Tab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var metricsBar: some View {
        HStack(spacing: 16) {
            metric(label: "layers", value: "\(layerCount)")
            metric(label: "render", value: String(format: "%.2f ms", renderMs))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
        }
    }
}
