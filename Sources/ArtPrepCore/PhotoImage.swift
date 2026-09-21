import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PhotoImage: @unchecked Sendable {
    // CGImage is immutable; this wrapper can safely cross the loading task boundary.
    public let image: CGImage
    public let size: ImageSize

    public static func load(_ url: URL) throws -> PhotoImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let type = CGImageSourceGetType(source),
            [UTType.jpeg.identifier, UTType.png.identifier].contains(type as String),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
            let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
            let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
            width > 0, height > 0, width <= 32768, height <= 32768,
            Int64(width) * Int64(height) <= 200_000_000
        else {
            throw ArtPrepError(
                "Cannot read \(url.lastPathComponent). Choose a local JPEG or PNG photo.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            throw ArtPrepError("Cannot decode \(url.lastPathComponent). Try opening it in GIMP.")
        }
        return PhotoImage(image: image, size: ImageSize(width: image.width, height: image.height))
    }

    public static func normalize(_ input: URL, to output: URL, expected: ImageSize) throws {
        let photo = try load(input)
        guard photo.size == expected else {
            throw ArtPrepError(
                "The source photo dimensions changed. Add it again and redraw the outline.")
        }
        guard
            let destination = CGImageDestinationCreateWithURL(
                output as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw ArtPrepError("Cannot create a temporary image. Check free disk space.")
        }
        CGImageDestinationAddImage(
            destination, photo.image,
            [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ArtPrepError("Cannot write the temporary image. Check free disk space.")
        }
    }
}
