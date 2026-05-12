import SwiftUI

private let defaultSnippet = """
// Lumen JS Playground
console.log('platform:', lumen.platform, 'v' + lumen.version)

const start = Date.now()
let sum = 0
for (let i = 0; i < 1_000_000; i++) sum += i
console.log('sum 1e6:', sum, '— ' + (Date.now() - start) + 'ms (JS clock)')

// Return value shows up as result
sum
"""

struct JSPlaygroundView: View {
    @State private var source: String = defaultSnippet
    @State private var output: [OutputLine] = []
    @State private var lastDurationMs: Double?
    @State private var lastResult: String?
    @State private var engine: JSEngine?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editor
                Divider()
                consoleArea
            }
            .navigationTitle("JS Playground")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        run()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear(perform: setup)
        }
    }

    private var editor: some View {
        TextEditor(text: $source)
            .font(.system(.callout, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 8)
    }

    private var consoleArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Console")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let ms = lastDurationMs {
                    Text(String(format: "%.2f ms", ms))
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(durationBackground(ms), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.primary)
                }

                if let r = lastResult {
                    Text("→ \(r)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Button {
                    output.removeAll()
                    lastDurationMs = nil
                    lastResult = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(output.isEmpty && lastDurationMs == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemBackground))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(output) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text(symbol(for: line.level))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, alignment: .center)
                                Text(line.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(color(for: line.level))
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: output.count) { _, _ in
                    if let last = output.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private struct OutputLine: Identifiable {
        let id = UUID()
        let level: JSEngine.LogLevel
        let text: String
    }

    private func setup() {
        let e = JSEngine()
        e.onLog = { level, text in
            output.append(OutputLine(level: level, text: text))
        }
        engine = e

        if UserDefaults.standard.bool(forKey: "autorun") {
            let result = e.evalTimed(source)
            lastDurationMs = result.elapsedMs
            lastResult = result.exception == nil ? result.result : nil
        }
    }

    private func run() {
        guard let engine else { return }
        let result = engine.evalTimed(source)
        lastDurationMs = result.elapsedMs
        lastResult = result.exception == nil ? result.result : nil
    }

    private func symbol(for level: JSEngine.LogLevel) -> String {
        switch level {
        case .log: return "›"
        case .info: return "i"
        case .warn: return "!"
        case .error: return "✕"
        }
    }

    private func color(for level: JSEngine.LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn: return .orange
        case .info: return .blue
        case .log: return .primary
        }
    }

    private func durationBackground(_ ms: Double) -> Color {
        if ms < 50 { return .green.opacity(0.2) }
        if ms < 200 { return .yellow.opacity(0.2) }
        return .red.opacity(0.2)
    }
}
