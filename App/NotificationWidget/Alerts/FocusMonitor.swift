import Intents
import NotificationWidgetCore
import Observation

/// Reads whether a macOS Focus mode is on, with `INFocusStatusCenter` (ALR-7).
@MainActor
@Observable
final class FocusMonitor {
    private(set) var authorization: INFocusStatusAuthorizationStatus = INFocusStatusCenter.default.authorizationStatus

    /// Asks for permission the first time. The explanation is `NSFocusStatusUsageDescription` in Info.plist.
    func requestPermissionIfNeeded() {
        guard authorization == .notDetermined else { return }
        INFocusStatusCenter.default.requestAuthorization { status in
            Task { @MainActor in self.authorization = status }
        }
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Checked when each Alert fires. Without permission it's `.unknown`, and Alerts behave normally.
    func currentState() -> FocusState {
        authorization = INFocusStatusCenter.default.authorizationStatus
        guard authorization == .authorized, let isFocused = INFocusStatusCenter.default.focusStatus.isFocused else {
            return .unknown
        }
        return isFocused ? .on : .off
    }
}
