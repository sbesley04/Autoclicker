import Foundation
import AppKit

/// Watches system-level events that must stop a clicking session: sleep,
/// display reconfiguration, and frontmost-app changes.
final class SystemEventObserver {
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?
    var onDisplayChange: (() -> Void)?
    var onActiveAppChange: ((NSRunningApplication?) -> Void)?
    /// Fires with true/false as this app becomes / resigns frontmost.
    var onAppActiveChange: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onSleep?() })

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onWake?() })

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.onActiveAppChange?(app)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onDisplayChange?() })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onAppActiveChange?(true) })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.onAppActiveChange?(false) })
    }

    func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit { stop() }
}
