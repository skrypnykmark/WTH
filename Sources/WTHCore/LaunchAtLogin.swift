import Foundation
import ServiceManagement

/// Manages the "Launch at Login" login item using `SMAppService`.
public struct LaunchAtLogin: Sendable {
    public init() {}

    /// `true` when the app is registered and approved to launch at login.
    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` when macOS requires the user to approve the login item.
    public var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the main app as a login item.
    public func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled || service.status == .requiresApproval else { return }
            try service.unregister()
        }
    }
}
