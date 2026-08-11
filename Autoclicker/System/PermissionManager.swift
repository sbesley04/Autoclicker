import Foundation
import AppKit
import ApplicationServices
import IOKit.hid
import Combine

/// Tracks the macOS privacy permissions the app depends on and offers
/// deep links into System Settings. Status is re-checked whenever the app
/// becomes active and on a slow poll while anything is missing, so the UI
/// reacts as soon as the user flips a switch in System Settings.
final class PermissionManager: ObservableObject {
    enum Status: Equatable {
        case granted
        case denied
        case unknown

        var isGranted: Bool { self == .granted }
    }

    /// Required. Backs CGEventTap listening/suppression and CGEvent posting.
    @Published private(set) var accessibility: Status = .unknown
    /// Needed on some configurations for global keyboard capture.
    @Published private(set) var inputMonitoring: Status = .unknown

    var allGranted: Bool { accessibility.isGranted && inputMonitoring.isGranted }
    /// The app can do its core job (mouse triggers + posting) with
    /// Accessibility alone; keyboard triggers may additionally need
    /// Input Monitoring.
    var coreGranted: Bool { accessibility.isGranted }

    /// Fires when a previously granted permission disappears — AppState uses
    /// this to stop any running session immediately.
    var onPermissionsLost: (() -> Void)?

    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(autoRefresh: Bool = true) {
        refresh()
        guard autoRefresh else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })
        // Slow poll: catches revocation while the app is frontmost and grant
        // while the user is in System Settings.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        pollTimer?.tolerance = 1.0
    }

    deinit {
        pollTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver(_:))
    }

    func refresh() {
        let hadCore = coreGranted
        // Accessibility: AXIsProcessTrusted covers event taps + posting.
        accessibility = AXIsProcessTrusted() ? .granted : .denied

        // Input Monitoring: IOHIDCheckAccess reflects the "Input Monitoring"
        // privacy pane (kIOHIDRequestTypeListenEvent).
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: inputMonitoring = .granted
        case kIOHIDAccessTypeDenied: inputMonitoring = .denied
        default: inputMonitoring = .unknown
        }

        if hadCore && !coreGranted {
            onPermissionsLost?()
        }
    }

    /// Shows the system prompt for Accessibility (only has an effect the
    /// first time; afterwards the user must use System Settings).
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Triggers the Input Monitoring system prompt where available, falling
    /// back to System Settings when it can't.
    ///
    /// `IOHIDRequestAccess` only shows a prompt while the permission is
    /// *undetermined*. As soon as macOS has evaluated Input Monitoring once —
    /// which it does automatically when the app creates its keyboard event
    /// tap at launch — the status is "determined" and every later call
    /// returns immediately with no prompt. So a plain request often does
    /// nothing; when that happens, opening the correct Settings pane is the
    /// only way for the user to change it.
    func requestInputMonitoring() {
        // IOHIDCheckAccess reports .denied for BOTH "explicitly denied" and
        // "never asked", so we can't branch on it. Always call
        // IOHIDRequestAccess: this is the call that (a) shows the system
        // prompt when the status is still undetermined, and (b) registers
        // the app in the Input Monitoring list so it can be toggled in
        // System Settings at all. Without ever calling it, the app never
        // appears in that list.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
        // If it didn't grant (already-determined, or the user hasn't chosen
        // in the prompt yet), open the Settings pane — the app is now listed
        // there and can be toggled on.
        if !granted {
            openInputMonitoringSettings()
        }
    }

    /// Registers the app in the Input Monitoring list at launch (and prompts
    /// once if the status is still undetermined), so it is available to
    /// toggle in System Settings without the user having to hunt for it.
    func registerForInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
