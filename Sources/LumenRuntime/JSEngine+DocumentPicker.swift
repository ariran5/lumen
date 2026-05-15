import Foundation
@preconcurrency import JavaScriptCore
import UIKit
import UniformTypeIdentifiers

/// `lumen.documentPicker.pick({types, multiple}) → Promise<PickedDocument[] | null>`
///
/// `PickedDocument = {uri: 'file:///tmp/lumen-docs/<uuid>.<ext>', name, size, mime?}`
///
/// `types` accepts either raw UTIs (`public.pdf`, `public.image`) or
/// friendly aliases (`image`, `pdf`, `text`, `data`). Default is `data`
/// (any file).
///
/// Files picked from Files.app / iCloud / providers (Dropbox etc.)
/// arrive as security-scoped URLs — we copy them into `tmp/lumen-docs/`
/// and give JS a local `file://` uri, similar to imagePicker. This way the fast-app
/// doesn't depend on an external scope and can read the file via `fetch()` or
/// anything else.
extension JSEngine {
    func installDocumentPickerBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let docPicker = JSValue(newObjectIn: context)!

        let nativePick: @convention(block) (JSValue?, JSValue, JSValue) -> Void = { config, resolve, reject in
            MainActor.assumeIsolated {
                Self.presentDocumentPicker(config: config, resolve: resolve, reject: reject)
            }
        }
        docPicker.setObject(nativePick, forKeyedSubscript: "_nativePick" as NSString)
        lumen.setObject(docPicker, forKeyedSubscript: "documentPicker" as NSString)

        let wrapper = """
        lumen.documentPicker.pick = function(opts) {
          return new Promise(function(resolve, reject) {
            lumen.documentPicker._nativePick(opts || {}, resolve, reject)
          })
        }
        """
        _ = context.evaluateScript(wrapper)
    }

    @MainActor
    fileprivate static func presentDocumentPicker(config: JSValue?, resolve: JSValue, reject: JSValue) {
        let types = parseContentTypes(from: config?.objectForKeyedSubscript("types"))
        let multiple = config?.objectForKeyedSubscript("multiple")?.toBool() ?? false

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple

        let coordinator = DocumentPickerCoordinator(resolve: resolve, reject: reject)
        picker.delegate = coordinator
        DocumentPickerCoordinator.alive[ObjectIdentifier(coordinator)] = coordinator

        TopViewController.find()?.present(picker, animated: true)
    }

    private static func parseContentTypes(from value: JSValue?) -> [UTType] {
        guard let value, !value.isUndefined, !value.isNull else {
            return [.data]
        }
        var raw: [String] = []
        if let arr = value.toArray() as? [String] {
            raw = arr
        } else if let s = value.toString(), !s.isEmpty {
            raw = [s]
        }
        let mapped = raw.compactMap { utiFromString($0) }
        return mapped.isEmpty ? [.data] : mapped
    }

    private static func utiFromString(_ s: String) -> UTType? {
        switch s.lowercased() {
        case "image": return .image
        case "pdf":   return .pdf
        case "text":  return .text
        case "data":  return .data
        case "content": return .content
        case "audio": return .audio
        case "video", "movie": return .movie
        case "json":  return .json
        case "zip":   return .zip
        case "html":  return .html
        default:      return UTType(s)
        }
    }
}

@MainActor
private final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    static var alive: [ObjectIdentifier: DocumentPickerCoordinator] = [:]

    let resolve: JSValue
    let reject: JSValue

    init(resolve: JSValue, reject: JSValue) {
        self.resolve = resolve
        self.reject = reject
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController,
                                    didPickDocumentsAt urls: [URL]) {
        let id = ObjectIdentifier(self)
        // `asCopy: true` already copied files into our inbox; still
        // move to lumen-docs/ so the fast-app has a stable uri regardless
        // of what the system did with the inbox.
        let snapshot: [[String: Any]] = urls.compactMap(copyPickedDocToTmp(sourceURL:))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = self.resolve.call(withArguments: [snapshot])
                DocumentPickerCoordinator.alive.removeValue(forKey: id)
            }
        }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let id = ObjectIdentifier(self)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = self.resolve.call(withArguments: [NSNull()])
                DocumentPickerCoordinator.alive.removeValue(forKey: id)
            }
        }
    }
}

private func copyPickedDocToTmp(sourceURL: URL) -> [String: Any]? {
    let needsScope = sourceURL.startAccessingSecurityScopedResource()
    defer { if needsScope { sourceURL.stopAccessingSecurityScopedResource() } }

    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("lumen-docs", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let originalName = sourceURL.lastPathComponent
    let ext = sourceURL.pathExtension
    let dest = dir
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext.isEmpty ? "bin" : ext)

    do {
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
    } catch {
        return nil
    }

    let size = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
    let mime = UTType(filenameExtension: ext)?.preferredMIMEType

    var dict: [String: Any] = [
        "uri": dest.absoluteString,
        "name": originalName,
        "size": size,
    ]
    if let mime { dict["mime"] = mime }
    return dict
}
