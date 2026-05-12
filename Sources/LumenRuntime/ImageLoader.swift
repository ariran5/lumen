import Foundation
import ImageIO
import UIKit

@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memoryCache: NSCache<NSURL, UIImage>
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024,
                                   diskPath: "LumenImageCache")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024
        self.memoryCache = cache
    }

    func loadImage(url: URL,
                   targetSize: CGSize,
                   scale: CGFloat = UIScreen.main.scale,
                   completion: @escaping @MainActor (UIImage?) -> Void) {
        let cacheKey = url as NSURL
        if let cached = memoryCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        if let task = inflight[url] {
            Task { @MainActor [weak self] in
                let image = await task.value
                if let image, let self {
                    self.memoryCache.setObject(image, forKey: cacheKey, cost: estimatedCost(image))
                }
                completion(image)
            }
            return
        }

        let task = Task<UIImage?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            do {
                let (data, _) = try await self.session.data(from: url)
                return Self.decode(data: data, targetSize: targetSize, scale: scale)
            } catch {
                return nil
            }
        }
        inflight[url] = task

        Task { @MainActor [weak self] in
            let image = await task.value
            guard let self else { return }
            self.inflight.removeValue(forKey: url)
            if let image {
                self.memoryCache.setObject(image, forKey: cacheKey, cost: estimatedCost(image))
            }
            completion(image)
        }
    }

    private static func decode(data: Data, targetSize: CGSize, scale: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }

        let maxPixelSize = max(targetSize.width, targetSize.height) * scale
        let downsampleOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize > 0 ? maxPixelSize : 1024,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOpts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    private func estimatedCost(_ image: UIImage) -> Int {
        let cgImage = image.cgImage
        let width = cgImage?.width ?? Int(image.size.width)
        let height = cgImage?.height ?? Int(image.size.height)
        return width * height * 4
    }
}
