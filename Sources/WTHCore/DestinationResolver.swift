import Foundation

/// What should happen to a candidate source image.
public enum ConversionDecision: Equatable, Sendable {
    case convert(destination: URL)
    case skipExistingJPEG(destination: URL)
    case skipUnsupported
}

/// Decides whether a source image should be converted and where the JPEG goes.
///
/// The resolver is intentionally pure apart from an injected file-existence
/// check, which keeps duplicate-handling logic easy to test.
public struct DestinationResolver: Sendable {
    public typealias FileExists = @Sendable (URL) -> Bool

    private let fileExists: FileExists

    public init(fileExists: @escaping FileExists) {
        self.fileExists = fileExists
    }

    /// Production resolver backed by the file system.
    public static let live = DestinationResolver { url in
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Resolves the destination for `source`.
    ///
    /// Existing JPEGs are never overwritten: if `<name>.jpg` already exists we
    /// skip the file and leave both the original HEIC and the existing JPEG
    /// untouched.
    public func resolve(source: URL) -> ConversionDecision {
        guard ImageFiles.isSupportedSource(source) else {
            return .skipUnsupported
        }
        let destination = ImageFiles.jpegDestination(for: source)
        if fileExists(destination) {
            return .skipExistingJPEG(destination: destination)
        }
        return .convert(destination: destination)
    }
}
