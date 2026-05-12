import Foundation
import JavaScriptCore

@MainActor
final class JSEngine {
    let context: JSContext

    enum LogLevel: String, Sendable {
        case log, info, warn, error
    }

    struct EvalResult {
        let result: String
        let elapsedMs: Double
        let exception: String?
    }

    var onLog: (@MainActor (LogLevel, String) -> Void)?

    private var lastException: String?

    init() {
        guard let ctx = JSContext() else {
            fatalError("Failed to create JSContext")
        }
        self.context = ctx
        ctx.name = "Lumen"

        installExceptionHandler()
        installConsole()
        installGlobals()

        #if DEBUG
        if #available(iOS 16.4, *) {
            context.isInspectable = true
        }
        #endif
    }

    @discardableResult
    func eval(_ source: String) -> JSValue? {
        context.evaluateScript(source)
    }

    func evalTimed(_ source: String) -> EvalResult {
        lastException = nil
        let start = CFAbsoluteTimeGetCurrent()
        let value = context.evaluateScript(source)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let resultText: String = {
            guard let value, !value.isUndefined else { return "undefined" }
            if value.isNull { return "null" }
            return value.toString() ?? "<unprintable>"
        }()

        return EvalResult(result: resultText,
                          elapsedMs: elapsed,
                          exception: lastException)
    }

    private func installExceptionHandler() {
        context.exceptionHandler = { [weak self] _, exception in
            let msg = exception?.toString() ?? "<unknown exception>"
            guard let self else { return }
            self.lastException = msg
            MainActor.assumeIsolated {
                self.onLog?(.error, "Uncaught: \(msg)")
            }
        }
    }

    private func installConsole() {
        guard let console = JSValue(newObjectIn: context) else { return }

        for level in [LogLevel.log, .info, .warn, .error] {
            let handler: @convention(block) () -> Void = { [weak self] in
                guard let self,
                      let args = JSContext.currentArguments() as? [JSValue] else { return }
                let parts = args.map { Self.stringify($0) }
                let line = parts.joined(separator: " ")
                MainActor.assumeIsolated {
                    self.onLog?(level, line)
                }
            }
            console.setObject(handler, forKeyedSubscript: level.rawValue as NSString)
        }

        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func installGlobals() {
        guard let lumen = JSValue(newObjectIn: context) else { return }
        lumen.setObject("ios", forKeyedSubscript: "platform" as NSString)
        lumen.setObject("0.0.1", forKeyedSubscript: "version" as NSString)
        context.setObject(lumen, forKeyedSubscript: "lumen" as NSString)
    }

    private static func stringify(_ value: JSValue) -> String {
        if value.isUndefined { return "undefined" }
        if value.isNull { return "null" }
        if value.isString { return value.toString() ?? "" }
        if value.isObject {
            let json = value.context.objectForKeyedSubscript("JSON")
            if let str = json?.invokeMethod("stringify", withArguments: [value])?.toString(),
               str != "undefined" {
                return str
            }
        }
        return value.toString() ?? "<unprintable>"
    }
}
