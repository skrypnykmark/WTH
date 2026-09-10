import Foundation

/// A lightweight snapshot of the file attributes used to detect completion.
public struct FileSnapshot: Equatable, Sendable {
    public let size: Int64
    public let modificationDate: Date

    public init(size: Int64, modificationDate: Date) {
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// Reads the current snapshot of a file, or throws when it cannot be read.
public protocol FileProbing: Sendable {
    func snapshot(at url: URL) throws -> FileSnapshot
}

/// File-system backed probe used in production.
public struct DefaultFileProbe: FileProbing {
    public init() {}

    public func snapshot(at url: URL) throws -> FileSnapshot {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast
        return FileSnapshot(size: size, modificationDate: modificationDate)
    }
}

/// Tunable behavior for `FileStabilityChecker`.
public struct FileStabilityConfiguration: Sendable {
    public var pollInterval: TimeInterval
    public var requiredStableReadings: Int
    public var timeout: TimeInterval
    public var minimumSize: Int64

    public init(
        pollInterval: TimeInterval = 0.4,
        requiredStableReadings: Int = 3,
        timeout: TimeInterval = 60,
        minimumSize: Int64 = 1
    ) {
        self.pollInterval = pollInterval
        self.requiredStableReadings = requiredStableReadings
        self.timeout = timeout
        self.minimumSize = minimumSize
    }
}

public enum FileStabilityError: Error, Equatable, Sendable {
    case timedOut
}

/// Waits until a file stops changing before it is handed to the converter.
///
/// AirDrop (and other copy operations) reveal the destination file as soon as
/// the transfer starts. Converting that partially written file would produce a
/// corrupt or truncated JPEG, so we poll the file's size and modification date
/// until several consecutive readings are identical.
public struct FileStabilityChecker: Sendable {
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    public typealias Clock = @Sendable () -> TimeInterval

    private let configuration: FileStabilityConfiguration
    private let probe: FileProbing
    private let sleep: Sleeper
    private let now: Clock

    public init(
        configuration: FileStabilityConfiguration = FileStabilityConfiguration(),
        probe: FileProbing = DefaultFileProbe(),
        sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping Clock = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.configuration = configuration
        self.probe = probe
        self.sleep = sleep
        self.now = now
    }

    /// Blocks until `url` has a stable size greater than `minimumSize`.
    ///
    /// - Throws: `FileStabilityError.timedOut` if the file never stabilizes
    ///   within `configuration.timeout`.
    public func waitUntilStable(at url: URL) async throws -> FileSnapshot {
        let start = now()
        let maximumIterations = max(
            1,
            Int(configuration.timeout / max(configuration.pollInterval, 0.0001))
        ) + configuration.requiredStableReadings + 1

        var lastSnapshot: FileSnapshot?
        var stableReadings = 0
        var iterations = 0

        while true {
            if now() - start >= configuration.timeout || iterations >= maximumIterations {
                throw FileStabilityError.timedOut
            }
            iterations += 1

            if let snapshot = try? probe.snapshot(at: url) {
                if snapshot.size >= configuration.minimumSize, snapshot == lastSnapshot {
                    stableReadings += 1
                } else {
                    stableReadings = 1
                }
                if stableReadings >= configuration.requiredStableReadings,
                   snapshot.size >= configuration.minimumSize {
                    return snapshot
                }
                lastSnapshot = snapshot
            } else {
                lastSnapshot = nil
                stableReadings = 0
            }

            try await sleep(configuration.pollInterval)
        }
    }
}
