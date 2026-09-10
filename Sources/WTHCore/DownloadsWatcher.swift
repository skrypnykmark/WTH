import Darwin
import Foundation

/// Watches a directory and reports newly added source images.
///
/// A directory file-system source (vnode events) provides an immediate signal
/// when entries change, and a low-frequency reconcile timer guards against a
/// missed event. Each newly observed file is reported as soon as it appears;
/// the conversion engine handles waiting for the file to finish copying.
///
/// Files present at start time form the baseline and are intentionally not
/// reported, so launching the app never retroactively converts an existing
/// library. The manual "Convert Existing Now" action covers that case
/// explicitly.
public final class DownloadsWatcher: @unchecked Sendable {
    public typealias NewFilesHandler = @Sendable ([URL]) -> Void

    private let directory: URL
    private let queue = DispatchQueue(label: "com.wth.watcher")
    private let reconcileInterval: TimeInterval

    private var knownFiles: Set<String> = []
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var reconcileTimer: DispatchSourceTimer?
    private var isStarted = false

    /// Invoked on the watcher's private queue with the files that just appeared.
    public var onNewFiles: NewFilesHandler?

    public init(
        directory: URL,
        reconcileInterval: TimeInterval = 30
    ) {
        self.directory = directory
        self.reconcileInterval = reconcileInterval
    }

    deinit {
        stop()
    }

    /// Starts watching. `emitExisting` is used by tests and never in the app.
    public func start(emitExisting: Bool = false) {
        queue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true

            let baseline = self.scan()
            if emitExisting, !baseline.isEmpty {
                self.onNewFiles?(baseline)
            }

            self.startDirectorySource()
            self.startReconcileTimer()
        }
    }

    /// Stops watching and releases the underlying file descriptor.
    public func stop() {
        queue.sync {
            guard isStarted else { return }
            isStarted = false

            source?.cancel()
            source = nil
            closeDescriptor()

            reconcileTimer?.cancel()
            reconcileTimer = nil
        }
    }

    private func startDirectorySource() {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.watcher.error("Unable to open \(self.directory.path, privacy: .public) for watching.")
            return
        }
        fileDescriptor = descriptor

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = newSource.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.source?.cancel()
                self.source = nil
                self.closeDescriptor()
                self.startDirectorySource()
            }
            self.reportNewFiles()
        }

        source = newSource
        newSource.resume()
    }

    private func startReconcileTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + reconcileInterval, repeating: reconcileInterval)
        timer.setEventHandler { [weak self] in
            self?.reportNewFiles()
        }
        reconcileTimer = timer
        timer.resume()
    }

    private func reportNewFiles() {
        let newFiles = scan()
        guard !newFiles.isEmpty else { return }
        Log.watcher.info("Detected \(newFiles.count, privacy: .public) new source image(s).")
        onNewFiles?(newFiles)
    }

    /// Enumerates the directory, updates the known set, and returns the files
    /// that were not seen before.
    private func scan() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var current: Set<String> = []
        var newFiles: [URL] = []

        for url in contents where ImageFiles.isSupportedSource(url) {
            let key = url.standardizedFileURL.path
            current.insert(key)
            if !knownFiles.contains(key) {
                newFiles.append(url)
            }
        }

        knownFiles = current
        return newFiles
    }

    private func closeDescriptor() {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }
}
