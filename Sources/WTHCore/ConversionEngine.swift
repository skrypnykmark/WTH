import Foundation

/// The result of processing a single candidate file.
public enum ConversionOutcome: Sendable, Equatable {
    case converted(source: URL, destination: URL)
    case skippedExistingJPEG(source: URL, destination: URL)
    case failed(source: URL, message: String)
}

/// Serializes HEIC to JPEG conversions.
///
/// The engine waits for each file to finish copying, respects the destination
/// policy (never overwriting an existing JPEG), and remembers failures so a
/// broken file is not retried endlessly within a session.
public actor ConversionEngine {
    public typealias OutcomeHandler = @Sendable (ConversionOutcome) -> Void

    private let converter: ImageConverting
    private let stabilityChecker: FileStabilityChecker
    private let resolver: DestinationResolver
    private let quality: Double

    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var outcomeHandler: OutcomeHandler?

    public init(
        converter: ImageConverting = ImageConverter(),
        stabilityChecker: FileStabilityChecker = FileStabilityChecker(),
        resolver: DestinationResolver = .live,
        quality: Double = 0.92
    ) {
        self.converter = converter
        self.stabilityChecker = stabilityChecker
        self.resolver = resolver
        self.quality = quality
    }

    public func setOutcomeHandler(_ handler: @escaping OutcomeHandler) {
        outcomeHandler = handler
    }

    /// Processes a single candidate file.
    ///
    /// - Parameter force: When `true`, a file that previously failed is retried
    ///   (used by the manual "Convert Existing Now" action).
    public func process(_ source: URL, force: Bool = false) async {
        let key = source.standardizedFileURL.path

        guard !inFlight.contains(key) else { return }
        if failed.contains(key), !force { return }
        if force { failed.remove(key) }

        switch resolver.resolve(source: source) {
        case .skipUnsupported:
            return

        case .skipExistingJPEG(let destination):
            emit(.skippedExistingJPEG(source: source, destination: destination))

        case .convert(let destination):
            inFlight.insert(key)
            defer { inFlight.remove(key) }

            do {
                _ = try await stabilityChecker.waitUntilStable(at: source)
                try converter.convert(source: source, destination: destination, quality: quality)
                failed.remove(key)
                Log.engine.info("Converted \(source.lastPathComponent, privacy: .public) to JPEG.")
                emit(.converted(source: source, destination: destination))
            } catch {
                failed.insert(key)
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                Log.engine.error("Conversion failed for \(source.lastPathComponent, privacy: .public): \(message, privacy: .public)")
                emit(.failed(source: source, message: message))
            }
        }
    }

    /// Scans a directory and processes every supported source image.
    public func processAll(in directory: URL, force: Bool = false) async {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Log.engine.error("Unable to enumerate \(directory.path, privacy: .public).")
            return
        }

        for url in contents where ImageFiles.isSupportedSource(url) {
            await process(url, force: force)
        }
    }

    private func emit(_ outcome: ConversionOutcome) {
        outcomeHandler?(outcome)
    }
}
