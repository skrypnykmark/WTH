import AppKit
import Combine
import UniformTypeIdentifiers
import WTHCore

/// The application's observable state and coordination layer.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var isAutomaticConversionEnabled: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var lastConversionDate: Date?
    @Published private(set) var statusText: String
    @Published private(set) var accessWarning: String?

    private enum Keys {
        static let automaticConversionEnabled = "automaticConversionEnabled"
    }

    private let downloadsURL: URL
    private let engine: ConversionEngine
    private let watcher: DownloadsWatcher
    private let launchAtLogin: LaunchAtLogin

    private weak var menuBarWindow: NSWindow?
    private var isStarted = false

    private init() {
        let defaults = UserDefaults.standard
        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)

        self.downloadsURL = downloadsURL
        self.isAutomaticConversionEnabled = defaults.object(forKey: Keys.automaticConversionEnabled) as? Bool ?? true
        self.launchAtLoginEnabled = LaunchAtLogin().isEnabled
        self.lastConversionDate = nil
        self.statusText = "Starting…"
        self.accessWarning = nil
        self.engine = ConversionEngine()
        self.watcher = DownloadsWatcher(directory: downloadsURL)
        self.launchAtLogin = LaunchAtLogin()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        Task {
            await engine.setOutcomeHandler { [weak self] outcome in
                Task { @MainActor in
                    self?.handle(outcome)
                }
            }
        }

        watcher.onNewFiles = { [weak self] urls in
            Task { @MainActor in
                guard let self else { return }
                for url in urls {
                    await self.engine.process(url)
                }
            }
        }

        Task {
            await refreshDownloadsAccess()
            applyAutomaticConversionState()
        }
    }

    func stop() {
        watcher.stop()
    }

    func setAutomaticConversionEnabled(_ enabled: Bool) {
        guard enabled != isAutomaticConversionEnabled else { return }
        isAutomaticConversionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.automaticConversionEnabled)
        applyAutomaticConversionState()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLogin.isEnabled
            if enabled, launchAtLogin.requiresApproval {
                accessWarning = "Approve WTH in System Settings › General › Login Items to finish enabling Launch at Login."
            }
        } catch {
            launchAtLoginEnabled = launchAtLogin.isEnabled
            accessWarning = "Couldn't update Launch at Login: \(error.localizedDescription)"
        }
    }

    func convertExistingNow() {
        statusText = "Scanning for HEIC files…"
        Task {
            await engine.processAll(in: downloadsURL, force: true)
            applyAutomaticConversionState()
        }
    }

    /// Presents a file picker and converts the chosen HEIC files to JPEG.
    func convertSelectedFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.heic, .heif]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose HEIC photos to convert to JPEG."
        panel.prompt = "Convert"

        dismissMenuBarUI()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        guard !urls.isEmpty else { return }

        statusText = "Converting \(urls.count) file\(urls.count == 1 ? "" : "s")…"
        Task {
            var converted = 0
            var skipped = 0
            var failed = 0
            var destinations: [URL] = []

            for url in urls {
                if let outcome = await engine.process(url, force: true, waitForStability: false) {
                    switch outcome {
                    case .converted(_, let destination):
                        converted += 1
                        destinations.append(destination)
                    case .skippedExistingJPEG:
                        skipped += 1
                    case .failed:
                        failed += 1
                    }
                }
            }

            applyAutomaticConversionState()
            presentConversionSummary(converted: converted, skipped: skipped, failed: failed)
            revealInFinder(destinations)
        }
    }

    /// Stores the hosting window of the menu bar extra so it can be dismissed.
    func attachMenuBarWindow(_ window: NSWindow?) {
        guard let window else { return }
        menuBarWindow = window
    }

    func retryAccess() {
        watcher.stop()
        Task {
            await refreshDownloadsAccess()
            applyAutomaticConversionState()
        }
    }

    func openDownloads() {
        NSWorkspace.shared.open(downloadsURL)
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func handle(_ outcome: ConversionOutcome) {
        if case .converted = outcome {
            lastConversionDate = Date()
        }
    }

    private func presentConversionSummary(converted: Int, skipped: Int, failed: Int) {
        var lines: [String] = []
        if converted > 0 {
            lines.append("Converted \(converted) file\(converted == 1 ? "" : "s") to JPEG.")
        }
        if skipped > 0 {
            lines.append("Skipped \(skipped) file\(skipped == 1 ? "" : "s") because a JPEG already exists.")
        }
        if failed > 0 {
            lines.append("Couldn't convert \(failed) file\(failed == 1 ? "" : "s").")
        }
        guard !lines.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = failed > 0 ? "Conversion finished with issues" : "Conversion complete"
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = failed > 0 ? .warning : .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func dismissMenuBarUI() {
        menuBarWindow?.close()
    }

    private func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func applyAutomaticConversionState() {
        if isAutomaticConversionEnabled {
            watcher.start(emitExisting: false)
            statusText = "Watching ~/Downloads"
        } else {
            watcher.stop()
            statusText = "Automatic conversion is off"
        }
    }

    private func refreshDownloadsAccess() async {
        let directory = downloadsURL
        let accessible = await Task.detached(priority: .utility) {
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) != nil
        }.value

        accessWarning = accessible
            ? nil
            : "WTH can't read your Downloads folder. Grant access in System Settings › Privacy & Security › Files and Folders, then choose Check Again."
    }
}
