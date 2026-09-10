import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageConversionError: Error, LocalizedError, Equatable, Sendable {
    case unreadableSource
    case emptySource
    case destinationUnavailable
    case encodingFailed
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .unreadableSource:
            return "The source image could not be read."
        case .emptySource:
            return "The source image contains no image data."
        case .destinationUnavailable:
            return "A JPEG could not be created at the destination."
        case .encodingFailed:
            return "The image could not be encoded as JPEG."
        case .writeFailed:
            return "The JPEG could not be written to disk."
        }
    }
}

public protocol ImageConverting: Sendable {
    func convert(source: URL, destination: URL, quality: Double) throws
}

/// Converts HEIC images to JPEG using Apple's ImageIO framework.
///
/// The primary path decodes the image, applies its EXIF orientation to the
/// pixels, copies the source metadata dictionaries (EXIF, GPS, TIFF, IPTC,
/// XMP), and encodes a JPEG at the requested quality. Baking the orientation
/// into the pixels guarantees the JPEG renders upright even in tools that
/// ignore EXIF orientation.
///
/// A metadata-copy fallback (`CGImageDestinationCopyImageSource`) handles
/// images that cannot be redrawn into a bitmap context.
///
/// Output is always written atomically: the JPEG is created next to the
/// destination under a temporary name and then moved into place. The move never
/// overwrites an existing file, so a pre-existing JPEG is always preserved.
public struct ImageConverter: ImageConverting {
    public init() {}

    public func convert(source: URL, destination: URL, quality: Double = 0.92) throws {
        guard let imageSource = CGImageSourceCreateWithURL(
            source as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImageConversionError.unreadableSource
        }

        guard CGImageSourceGetCount(imageSource) > 0 else {
            throw ImageConversionError.emptySource
        }

        let temporaryURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".wth-\(UUID().uuidString)")
            .appendingPathExtension(ImageFiles.jpegExtension)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try writeUsingRedraw(source: imageSource, destination: temporaryURL, quality: quality)
        } catch {
            Log.converter.debug("Redraw path failed, using metadata-copy fallback.")
            try? FileManager.default.removeItem(at: temporaryURL)
            try writeUsingMetadataCopy(source: imageSource, destination: temporaryURL)
        }

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            throw ImageConversionError.writeFailed
        }
    }

    private func writeUsingRedraw(
        source: CGImageSource,
        destination: URL,
        quality: Double
    ) throws {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        guard let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw ImageConversionError.unreadableSource
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let orientedImage = ImageOrientation.apply(orientation, to: image)

        var metadata = properties
        for key in [
            kCGImagePropertyPixelWidth,
            kCGImagePropertyPixelHeight,
            kCGImagePropertyColorModel,
            kCGImagePropertyProfileName,
            kCGImagePropertyDepth,
            kCGImagePropertyOrientation,
        ] {
            metadata.removeValue(forKey: key)
        }
        metadata[kCGImagePropertyOrientation] = 1
        metadata[kCGImageDestinationLossyCompressionQuality] = quality

        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageConversionError.destinationUnavailable
        }

        CGImageDestinationAddImage(imageDestination, orientedImage, metadata as CFDictionary)

        guard CGImageDestinationFinalize(imageDestination) else {
            throw ImageConversionError.writeFailed
        }
    }

    private func writeUsingMetadataCopy(source: CGImageSource, destination: URL) throws {
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageConversionError.destinationUnavailable
        }

        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(imageDestination, source, nil, &error) else {
            throw ImageConversionError.encodingFailed
        }

        guard CGImageDestinationFinalize(imageDestination) else {
            throw ImageConversionError.writeFailed
        }
    }
}
