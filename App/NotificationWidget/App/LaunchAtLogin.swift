import Observation
import ServiceManagement

/// Registers the app to start at login with `SMAppService.mainApp` (APP-1).
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    /// Makes the login item match `enabled`.
    func apply(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("Launch at login: \(error.localizedDescription, privacy: .public)")
        }
        status = service.status
    }

    /// macOS can ask the user to approve login items in System Settings.
    var needsApproval: Bool { status == .requiresApproval }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
