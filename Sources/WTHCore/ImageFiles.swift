import Foundation

/// Helpers for recognizing source images and deriving JPEG destinations.
public enum ImageFiles {
    /// File extensions, lowercased, that WTH treats as convertible sources.
    ///
    /// `.heic` is what iPhones produce. `.heif` is the broader container format
    /// and is included for completeness; both are handled by ImageIO.
    public static let sourceExtensions: Set<String> = ["heic", "heif"]

    /// The extension used for generated JPEG files.
    public static let jpegExtension = "jpg"

    /// Returns `true` when the URL has a supported source image extension.
    public static func isSupportedSource(_ url: URL) -> Bool {
        sourceExtensions.contains(url.pathExtension.lowercased())
    }

    /// Returns the sibling JPEG URL for a source image.
    ///
    /// The base name is preserved and only the extension changes:
    ///
    ///     /Users/me/Downloads/IMG_1234.HEIC -> /Users/me/Downloads/IMG_1234.jpg
    public static func jpegDestination(for source: URL) -> URL {
        source.deletingPathExtension().appendingPathExtension(jpegExtension)
    }
}
