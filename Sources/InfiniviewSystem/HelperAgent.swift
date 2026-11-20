import Foundation
import ServiceManagement

/// The background helper that runs Folder Checks (ADR-0005): a launch agent inside the app,
/// started on demand by launchd when a preview extension connects to its Mach service.
public enum HelperAgent {
    public static let plistName = "com.mdrum.infiniview.helper.plist"

    static var service: SMAppService { .agent(plistName: plistName) }

    public enum State: Sendable, Equatable { case enabled, needsApproval, off }

    public static var state: State {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    /// Registers the agent with launchd. Safe to repeat; macOS may ask the user to allow it under
    /// System Settings → General → Login Items.
    @discardableResult
    public static func register() -> State {
        if service.status != .enabled {
            do { try service.register() } catch { NSLog("Infiniview: couldn't register the helper: \(error)") }
        }
        return state
    }

    public static func unregister() {
        try? service.unregister()
    }

    public static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
