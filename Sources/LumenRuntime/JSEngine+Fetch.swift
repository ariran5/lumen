import Foundation
@preconcurrency import JavaScriptCore

extension JSEngine {
    func installFetchBridge() {
        let nativeFetch: @convention(block) (String?, JSValue?, JSValue, JSValue) -> Void = { [weak self] urlString, options, resolve, reject in
            guard let self else { return }
            MainActor.assumeIsolated {
                Self.performFetch(engine: self,
                                  urlString: urlString,
                                  options: options,
                                  resolve: resolve,
                                  reject: reject)
            }
        }
        context.setObject(nativeFetch, forKeyedSubscript: "_nativeFetch" as NSString)

        let wrapper = """
        globalThis.fetch = function(url, options) {
          return new Promise(function(resolve, reject) {
            _nativeFetch(url, options || null, resolve, reject)
          })
        }
        """
        _ = context.evaluateScript(wrapper)
    }

    @MainActor
    private static func performFetch(engine: JSEngine,
                                     urlString: String?,
                                     options: JSValue?,
                                     resolve: JSValue,
                                     reject: JSValue) {
        guard let urlString, let url = URL(string: urlString) else {
            rejectWith(engine: engine, reject: reject, message: "fetch: invalid URL")
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15

        if let options, options.isObject {
            if let method = options.objectForKeyedSubscript("method")?.toString(),
               !method.isEmpty, method != "undefined" {
                req.httpMethod = method.uppercased()
            }
            if let headers = options.objectForKeyedSubscript("headers"),
               headers.isObject,
               let headerDict = headers.toDictionary() as? [String: Any] {
                for (k, v) in headerDict {
                    req.setValue(String(describing: v), forHTTPHeaderField: k)
                }
            }
            if let body = options.objectForKeyedSubscript("body")?.toString(),
               !body.isEmpty, body != "undefined" {
                req.httpBody = body.data(using: .utf8)
            }
        }

        let resolveRef = JSValueBox(resolve)
        let rejectRef = JSValueBox(reject)
        let engineRef = WeakRef(engine)

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let engine = engineRef.value else { return }
                    if let error {
                        rejectWith(engine: engine,
                                   reject: rejectRef.value,
                                   message: error.localizedDescription)
                        return
                    }
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? 0
                    let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let responseObj = makeResponseObject(engine: engine,
                                                         status: status,
                                                         ok: (200..<300).contains(status),
                                                         bodyText: bodyText)
                    resolveRef.value.call(withArguments: [responseObj as Any])
                }
            }
        }
        task.resume()
    }

    @MainActor
    private static func makeResponseObject(engine: JSEngine,
                                           status: Int,
                                           ok: Bool,
                                           bodyText: String) -> JSValue {
        let response = JSValue(newObjectIn: engine.context)!
        response.setObject(status, forKeyedSubscript: "status" as NSString)
        response.setObject(ok, forKeyedSubscript: "ok" as NSString)

        let weakEngine = WeakRef(engine)
        let body = bodyText

        // text() returns a JS function that resolves a Promise with the body string.
        // The block returns Void; it stores the resolved Promise in a temp slot
        // accessible from JS by calling text() and chaining .then().
        // Easier: install as JS-side method that captures body.

        response.setObject(body, forKeyedSubscript: "_body" as NSString)

        let textHelper = """
        (function(response) {
          response.text = function() { return Promise.resolve(response._body) }
          response.json = function() {
            return new Promise(function(resolve, reject) {
              try { resolve(JSON.parse(response._body)) }
              catch (e) { reject(e) }
            })
          }
          return response
        })
        """
        if let helperFn = engine.context.evaluateScript(textHelper) {
            _ = helperFn.call(withArguments: [response])
        }

        // Suppress unused warnings
        _ = weakEngine

        return response
    }

    @MainActor
    private static func rejectWith(engine: JSEngine, reject: JSValue, message: String) {
        let safe = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        let err = engine.context.evaluateScript("new Error('\(safe)')")
        reject.call(withArguments: [err as Any])
    }
}

@MainActor
private final class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

@MainActor
private final class JSValueBox {
    let value: JSValue
    init(_ value: JSValue) { self.value = value }
}
