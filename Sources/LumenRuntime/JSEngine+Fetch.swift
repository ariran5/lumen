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

        // Sandbox network policy: blocks cross-origin requests not in manifest's
        // `connect` allowlist. См. NetworkPolicy.swift.
        let policy = engine.originContext.networkPolicy
        guard policy.allows(url: url) else {
            rejectWith(engine: engine,
                       reject: reject,
                       message: "fetch: blocked by sandbox — '\(url.host ?? "")' is not in this app's `connect` allowlist")
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
            // body: ArrayBuffer / typed array → raw bytes; иначе → toString()
            // как UTF-8. Так fetch остаётся совместим со старыми вызовами
            // (`body: JSON.stringify(...)`) и поддерживает binary upload.
            if let bodyVal = options.objectForKeyedSubscript("body"),
               !bodyVal.isUndefined, !bodyVal.isNull {
                if let bin = extractBinaryBytes(from: bodyVal) {
                    req.httpBody = bin
                } else if let s = bodyVal.toString(), !s.isEmpty, s != "undefined" {
                    req.httpBody = s.data(using: .utf8)
                }
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
                    let responseObj = makeResponseObject(engine: engine,
                                                         status: status,
                                                         ok: (200..<300).contains(status),
                                                         data: data)
                    resolveRef.value.call(withArguments: [responseObj as Any])
                }
            }
        }
        // Task-scoped delegate (iOS 15+): валидирует cross-origin редиректы
        // против policy. Hold ref до task'а — task ретейнит delegate'а.
        task.delegate = NetworkRedirectGuard(policy: policy)
        task.resume()
    }

    @MainActor
    private static func makeResponseObject(engine: JSEngine,
                                           status: Int,
                                           ok: Bool,
                                           data: Data?) -> JSValue {
        let response = JSValue(newObjectIn: engine.context)!
        response.setObject(status, forKeyedSubscript: "status" as NSString)
        response.setObject(ok, forKeyedSubscript: "ok" as NSString)

        // UTF-8 декод для text()/json(). Lossy для binary — но это и
        // ожидаемое поведение fetch'а: бинарные ответы читают через
        // arrayBuffer(), не text().
        let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        response.setObject(bodyText, forKeyedSubscript: "_body" as NSString)

        if let data, !data.isEmpty,
           let buf = makeArrayBuffer(in: engine.context, from: data) {
            response.setObject(buf, forKeyedSubscript: "_buffer" as NSString)
        }

        let helper = """
        (function(response) {
          response.text = function() { return Promise.resolve(response._body) }
          response.json = function() {
            return new Promise(function(resolve, reject) {
              try { resolve(JSON.parse(response._body)) }
              catch (e) { reject(e) }
            })
          }
          response.arrayBuffer = function() {
            return Promise.resolve(response._buffer || new ArrayBuffer(0))
          }
          return response
        })
        """
        if let helperFn = engine.context.evaluateScript(helper) {
            _ = helperFn.call(withArguments: [response])
        }

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

/// JSC C-API helpers — ArrayBuffer ↔ Data.
///
/// Read side: `extractBinaryBytes` принимает JSValue, проверяет это
/// ArrayBuffer или TypedArray, и копирует байты в `Data`. Для маленьких
/// файлов копия дешёвая; альтернатива — `noCopy` версия с retain'ом
/// исходного буфера, но это редко стоит сложности.
///
/// Write side: `makeArrayBuffer` копирует `Data` в malloc'нутый буфер и
/// отдаёт ownership JSC через `MakeArrayBufferWithBytesNoCopy` + free
/// deallocator. ArrayBuffer живёт пока его держит JS; когда GC соберёт —
/// JSC вызовет наш free.
@MainActor
private func extractBinaryBytes(from value: JSValue) -> Data? {
    let ctx = value.context.jsGlobalContextRef
    let ref: JSValueRef = value.jsValueRef

    let kind = JSValueGetTypedArrayType(ctx, ref, nil)
    if kind == kJSTypedArrayTypeArrayBuffer {
        guard let bytesPtr = JSObjectGetArrayBufferBytesPtr(ctx, ref, nil) else { return nil }
        let length = JSObjectGetArrayBufferByteLength(ctx, ref, nil)
        return Data(bytes: bytesPtr, count: length)
    }
    if kind != kJSTypedArrayTypeNone {
        // Uint8Array / Int8Array / прочие views.
        guard let bytesPtr = JSObjectGetTypedArrayBytesPtr(ctx, ref, nil) else { return nil }
        let length = JSObjectGetTypedArrayByteLength(ctx, ref, nil)
        let offset = JSObjectGetTypedArrayByteOffset(ctx, ref, nil)
        let start = bytesPtr.advanced(by: offset)
        return Data(bytes: start, count: length)
    }
    return nil
}

@MainActor
private func makeArrayBuffer(in context: JSContext, from data: Data) -> JSValue? {
    let ctx = context.jsGlobalContextRef
    let length = data.count
    guard length > 0, let ptr = malloc(length) else { return nil }
    data.copyBytes(to: ptr.assumingMemoryBound(to: UInt8.self), count: length)
    let deallocator: JSTypedArrayBytesDeallocator = { p, _ in free(p) }
    guard let bufRef = JSObjectMakeArrayBufferWithBytesNoCopy(ctx, ptr, length, deallocator, nil, nil) else {
        free(ptr)
        return nil
    }
    return JSValue(jsValueRef: bufRef, in: context)
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
