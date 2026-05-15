import Foundation
@preconcurrency import JavaScriptCore
import UIKit
import PhotosUI
import ImageIO

/// `lumen.imagePicker.pick({limit}) → Promise<Asset | Asset[] | null>`
///
/// `Asset = {uri: 'file:///tmp/lumen-picker/<uuid>.<ext>', width, height}`.
/// With `limit > 1` returns an array. If user cancels — `null`.
///
/// PHPickerViewController doesn't require `NSPhotoLibraryUsageDescription` —
/// out-of-process picker from Photos.framework, the fast-app has no library access.
extension JSEngine {
    func installImagePickerBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let imagePicker = JSValue(newObjectIn: context)!

        let originRef = origin
        let nativePick: @convention(block) (JSValue?, JSValue, JSValue) -> Void = { config, resolve, reject in
            Task { @MainActor in
                // Photos gate. PHPickerViewController technically works
                // without `NSPhotoLibraryUsageDescription` (out-of-process picker),
                // but we gate anyway — origin must explicitly confirm
                // it wants to show the picker. Without this an untrusted site could
                // spam pickers for phishing UI.
                let grant = await PermissionStore.shared.request(origin: originRef, capability: .photos)
                guard grant == .granted else {
                    _ = resolve.call(withArguments: [NSNull()])
                    return
                }
                Self.presentImagePicker(config: config, resolve: resolve, reject: reject)
            }
        }
        imagePicker.setObject(nativePick, forKeyedSubscript: "_nativePick" as NSString)
        lumen.setObject(imagePicker, forKeyedSubscript: "imagePicker" as NSString)

        let wrapper = """
        lumen.imagePicker.pick = function(opts) {
          return new Promise(function(resolve, reject) {
            lumen.imagePicker._nativePick(opts || {}, resolve, reject)
          })
        }
        """
        _ = context.evaluateScript(wrapper)
    }

    @MainActor
    fileprivate static func presentImagePicker(config: JSValue?, resolve: JSValue, reject: JSValue) {
        var pickerConfig = PHPickerConfiguration()
        let limit = config?.objectForKeyedSubscript("limit")?.toNumber()?.intValue ?? 1
        pickerConfig.selectionLimit = max(1, limit)
        pickerConfig.filter = .images

        let coordinator = ImagePickerCoordinator(resolve: resolve,
                                                 reject: reject,
                                                 singleResult: limit <= 1)

        let picker = PHPickerViewController(configuration: pickerConfig)
        picker.delegate = coordinator
        ImagePickerCoordinator.alive[ObjectIdentifier(coordinator)] = coordinator

        TopViewController.find()?.present(picker, animated: true)
    }
}

/// Off-main accumulator for image dicts. Lock-protected NSLock + array.
/// Marked `@unchecked Sendable` so it can be passed into `@Sendable` closures
/// (`loadFileRepresentation` callback, `group.notify`).
private final class PickAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[String: Any]] = []

    func append(_ dict: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        items.append(dict)
    }

    func snapshot() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}

@MainActor
private final class ImagePickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    static var alive: [ObjectIdentifier: ImagePickerCoordinator] = [:]

    let resolve: JSValue
    let reject: JSValue
    let singleResult: Bool

    init(resolve: JSValue, reject: JSValue, singleResult: Bool) {
        self.resolve = resolve
        self.reject = reject
        self.singleResult = singleResult
    }

    nonisolated func picker(_ picker: PHPickerViewController,
                            didFinishPicking results: [PHPickerResult]) {
        let id = ObjectIdentifier(self)

        DispatchQueue.main.async {
            picker.dismiss(animated: true)
        }

        if results.isEmpty {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    _ = self.resolve.call(withArguments: [NSNull()])
                    ImagePickerCoordinator.alive.removeValue(forKey: id)
                }
            }
            return
        }

        let acc = PickAccumulator()
        let group = DispatchGroup()

        for result in results {
            group.enter()
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.image") { url, _ in
                defer { group.leave() }
                guard let url, let saved = copyPickedFileToTmp(sourceURL: url) else { return }
                var dict: [String: Any] = ["uri": saved.absoluteString]
                if let dims = readPickedImageDimensions(url: saved) {
                    dict["width"] = dims.width
                    dict["height"] = dims.height
                }
                acc.append(dict)
            }
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                let arr = acc.snapshot()
                let value: Any = self.singleResult ? (arr.first ?? NSNull()) : arr
                _ = self.resolve.call(withArguments: [value])
                ImagePickerCoordinator.alive.removeValue(forKey: id)
            }
        }
    }
}

private func copyPickedFileToTmp(sourceURL: URL) -> URL? {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("lumen-picker", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
    let dest = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    do {
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: sourceURL, to: dest)
        return dest
    } catch {
        return nil
    }
}

private func readPickedImageDimensions(url: URL) -> (width: Int, height: Int)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
        return nil
    }
    let w = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
    let h = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
    guard w > 0, h > 0 else { return nil }
    return (w, h)
}
