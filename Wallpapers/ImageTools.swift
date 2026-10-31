import ImageIO
import UIKit

enum ImageTools {
    /// Decodes a smaller copy straight from the file, without ever holding the 4K original in memory.
    static func image(at url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(source, maxPixel: maxPixel).map(UIImage.init(cgImage:))
    }

    /// A small JPEG for the grid, plus the original's size for photos X didn't report one for.
    static func thumbnail(from data: Data, maxPixel: Int) -> (jpeg: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = downsample(source, maxPixel: maxPixel),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? image.width
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? image.height
        return (jpeg, width, height)
    }

    private static func downsample(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

/// Thumbnails and full-screen copies already decoded, so scrolling back doesn't decode again.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 160 * 1024 * 1024
        return cache
    }()

    func image(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, _ key: String) {
        let pixels = Int(image.size.width * image.scale * image.size.height * image.scale)
        cache.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }

    func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
