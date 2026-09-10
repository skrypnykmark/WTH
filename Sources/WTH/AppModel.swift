import AppKit
import Combine
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
